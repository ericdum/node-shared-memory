path = require 'path'
fs = require 'fs'
os = require 'options-stream'
ep = require 'event-pipe'
lockfile = require 'lockfile'
lockfile = require './filelock'
accpool = require './pool'

###
# properties:
#   options
#   indexPath
#   dataPath
#   indexHandle
#   dataHandle
#
#   indexCache
#
# usage:
# new
# ready
# set
# get
#
###

mkdirpSync = (uri) ->
  try
    unless fs.existsSync uri
      mkdirpSync uri.split('/').slice(0, -1).join('/')
      console.log 'mkdir', uri
      fs.mkdirSync uri

class File_DB
  constructor: (options) ->
    @options = os
      dir: '/tmp/'
      index_file: 'index.fd'
      data_file: 'data.fd'
      lock_dir: 'locks'
      min_length: 8
      lock_opt:
        pollPeriod: 10
        wait: 50000
    , options

    if fs.existsSync '/dev/shm/'
      @options.dir = path.join '/dev/shm', @options.dir

    unless fs.existsSync @options.dir
      mkdirpSync @options.dir

    lock_dir = path.join @options.dir, @options.lock_dir
    if fs.existsSync lock_dir
      for file in fs.readdirSync lock_dir
        fs.unlinkSync path.join lock_dir, file
      fs.rmdirSync lock_dir
    fs.mkdirSync lock_dir

    @indexPath = path.join @options.dir, @options.index_file
    @dataPath = path.join @options.dir, @options.data_file

    @indexCache = {}
    @_tasks = {}

    @_ready = false
    cb = (err) =>
      if err
        @_error = err
      else
        @_ready = true
      callback(@_error, @_ready) for callback in @callbacks

    _db = @
    flow = ep()
    flow.on 'error', cb
    .lazy ->
      fs.open _db.dataPath, 'a', @
    .lazy (fd) ->
      fs.close fd, @
    .lazy ->
      ws = fs.createWriteStream _db.dataPath, {flags:'r+', encoding: 'utf8', mode: '0666'}
      ws.on 'open', (fd) => @ null, fd
    .lazy (fd) ->
      _db.dataHandle = fd
      _db.index = new Index _db.options, fd, @
    .lazy ->
      cb()
    .run()

    @callbacks = []

  ready: (callback) ->
    unless @_ready
      return @callbacks.push callback
    else
      callback @_error, @_ready

  get: (key, cb) ->
    unless cb then cb = ->
    @index.get key, (err, pos) =>
      return cb new Error 'key not found!' unless pos
      @_getData pos, cb

  getAll: ( cb ) ->
    @index.getAll (err, data) =>
      func = []
      result = {}
      for key, position of data
        func.push @_getdataMaker key, position
      unless func.length
        return cb null, result
      flow = ep()
      flow.lazy func
      flow.lazy ->
        for [key, num] in arguments
          result[key] = num if num
        cb null, result
      flow.run()

  pop: (key, cb) ->
    unless cb then cb = ->
    @index.get key, (err, pos) =>
      return cb new Error 'key not found!' unless pos
      @_popData pos, cb

  popAll: ( cb ) ->
    @index.getAll (err, data) =>
      func = []
      result = {}
      for key, position of data
        func.push @_popdataMaker key, position
      unless func.length
        return cb null, result
      flow = ep()
      flow.lazy func
      flow.lazy ->
        for [key, num] in arguments
          result[key] = num if num
        cb null, result
      flow.run()

  _getdataMaker: (key, position) ->
    that = @
    ->
      flow = @
      that._getData position, (err, num) ->
        flow err, key, num

  _popdataMaker: (key, position) ->
    that = @
    ->
      flow = @
      that._popData position, (err, num) ->
        flow err, key, num

  increase: (key, num, cb) ->
    unless cb then cb = ->
    return cb() if num is 0
    if typeof num is 'function'
      cb = num
      num = 1
    unless num then num = 1
    @_accumulate key, num, cb

  decrease: (key, num, cb) ->
    unless cb then cb = ->
    return cb() if num is 0
    if typeof num is 'function'
      cb = num
      num = -1
    unless num then num = -1
    if num>0 then num = -num
    @_accumulate key, num, cb

  _accumulate: (key, acc, cb ) ->
    accpool key, acc, cb, (acc, cb) =>
      # lock
      @_process key, cb, (done) =>
        @index.get key, (err, pos) =>
          # create if not exists
          unless pos
            @_write key, acc.toString(), done
          else
            # get data
            @_getData pos, (err, num) =>
              num += acc
              num = num.toString()
              # set data
              if num.length > pos[1]
                # extend space
                @_write key, num, done
              else
                @_saveData num, pos, done

  _process: (key, done, cb) ->
    the = @
    lock_file = path.join @options.dir, @options.lock_dir, key+'.lock'
    lockfile.lock lock_file, ->
      cb -> lockfile.unlock lock_file, done

  _getData: (pos, cb) ->
    _buffer = new Buffer pos[1]
    fs.read @dataHandle, _buffer, 0, pos[1], pos[0], (err) =>
      return cb err if err
      @_parseData _buffer, cb

  _popData: (pos, cb) ->
    _buffer = new Buffer pos[1]
    fs.read @dataHandle, _buffer, 0, pos[1], pos[0], (err) =>
      return cb err if err
      @_saveData '', pos, (err) =>
        return cb err if err
        @_parseData _buffer, cb

  _parseData: (_buffer, cb) ->
    data = _buffer.toString().trim()
    unless isNaN(data)
      cb null, 1*data
    else
      cb null, @_try_object data

  set: (key, val, cb) ->
    unless cb then cb = ->
    if typeof val isnt 'string'
      val = JSON.stringify val
    @_write key, val, cb

  _write: (key, val, cb) ->
    @index.ensure key, val.length, (err, position) =>
      return cb err if err
      @_saveData val, position, cb

  _saveData: (val, [start, length], cb) ->
    val = val.toString()
    if val.length < length
      val = (new Array(length-val.length+1)).join(' ') + val
    data = new Buffer(val)
    fs.write @dataHandle, new Buffer(val), 0, length, start, cb

  _try_object: (data) ->
    try
      return JSON.parse data
    catch e
      return data

class Index
  constructor: (@options, @dataHandle, cb) ->
    @path  = path.join @options.dir, @options.index_file
    @lock  = path.join @options.dir, @options.lock_dir, 'index.lock'
    @cache = {}
    @tasks = {}
    @cbs   = []
    @mtime = 0

    _index = @
    flow = ep()
    flow.on 'error', cb
    .lazy ->
      fs.open _index.path, 'a', @
    .lazy (fd) ->
      fs.close fd, @
    .lazy ->
      ws = fs.createWriteStream _index.path, {flags:'r+', encoding: 'utf8', mode: '0666'}
      ws.on 'open', (fd) => @ null, fd
    .lazy (fd) ->
      _index.handle = fd
      _index._update cb
    .lazy ->
      cb()
    .run()

  getAll: (cb) ->
    @_update => cb null, @cache

  get: (key, cb) ->
    position = @cache[key]
    unless position
      @_update => cb null, @cache[key]
    else
      cb null, position

  ensure: (key, length, cb) ->
    @get key, (err, position) =>
      unless position and length <= position[1]
        @_add key, length, cb
      else
        cb null, position

  _add: (key, length, cb) ->
    length = @options.min_length if length < @options.min_length
    @tasks[key] = length if not @tasks[key] or @tasks[key] < length
    @cbs.push [key, cb]
    @_clearup()

  _clearup: ->
    return if @clearing
    @clearing = true
    # 默认重试5秒，如果文件锁1000ms未更新则抢锁，防止雪崩
    lockfile.lock @lock, (err) =>
      if err
        setTimeout =>
          @clearing = false
          @_clearup()
        , 10
      else
        @_process =>
          lockfile.unlock @lock, =>
            @clearing = false
            if @cbs.length then @_clearup()
    
  _process: (callback) ->
    tasks = @tasks
    cbs = @cbs
    @tasks = {}
    @cbs = []
    @_getDataLength (err, start) =>
      return cb err if err
      exists = false
      for key, length of tasks
        if @cache[key]
          continue if @cache[key][1] >= length
          exists = true
        @cache[key] = [start, length]
        start += length
      if exists
        data = JSON.stringify(@cache).replace(/^{|}$/g,"") + ','
        fs.write @handle, new Buffer(data), 0, data.length, 0, (err, written)=>
          for [key, cb] in cbs
            cb null, @cache[key]
          callback()
      else
        data = ""
        for key, length of tasks
          data += "\"#{key}\":#{JSON.stringify(@cache[key])},"
        @_getLength (err, size) =>
          fs.write @handle, new Buffer(data), 0, data.length, size, (err, written)=>
            for [key, cb] in cbs
              cb null, @cache[key]
            callback()

  _update: (cb) ->
    fs.fstat @handle, (err, stat) =>
      if stat.mtime.getTime() is @mtime
        cb()
      else
        @_getLength (err, size, stat) =>
          @mtime = stat.mtime.getTime()
          unless size
            @cache = {}
            return cb()
          buffer = new Buffer size
          fs.read @handle, buffer, 0, size, 0, (err) =>
            @cache = JSON.parse '{'+buffer.toString().trim().replace(/,$/, '')+'}'
            cb()

  _getLength: (cb) ->
    fs.fstat @handle, (err, stat) ->
      cb err, stat.size, stat

  _getDataLength: (cb) ->
    fs.fstat @dataHandle, (err, stat) ->
      cb err, stat.size

module.exports = (options) ->
  new File_DB options

