path = require 'path'
fs = require 'fs'
os = require 'options-stream'
ep = require 'event-pipe'

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
  unless fs.existsSync uri
    mkdirpSync uri.split('/').slice(0, -1).join('/')
    console.log 'mkdir', uri
    fs.mkdirSync uri

class File_DB
  constructor: (options) ->
    @options = os
      dir: '/tmp'
      index_file: 'index.fd'
      data_file: 'data.fd'
      lock_dir: 'locks'
      min_length: 8
    , options

    if fs.existsSync '/shm/'
      @options.dir = path.join '/shm', @options.dir

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
      fs.open _db.dataPath, 'a+', @
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
      _buffer = new Buffer pos[1]
      fs.read @dataHandle, _buffer, 0, pos[1], pos[0], (err) =>
        return cb err if err
        data = _buffer.toString().trim()
        unless isNaN(data)
          cb null, new Number data
        else
          cb null, @_try_object data

  set: (key, val, cb) ->
    unless cb then cb = ->
    if typeof val isnt 'string'
      val = JSON.stringify val
    @_write key, val, cb

  _write: (key, val, cb) ->
    @index.make key, val.length, (err, position) =>
      cb err if err
      @_saveData key, val, position, cb

  _saveData: (key, val, [start, length], cb) ->
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

class Task
  constructor: (@lock_file)->
    @trying = false

  process: (cb, done) ->
    console.log arguments
    unless @trying
      @trying = true
      that = @
      retry = ->
        flow = ep()
        flow.on 'error', (err) ->
          if err is 'locked by others'
            return process.nextTick retry
          else
            cb err
          
        .lazy -> that._lock @
        .lazy -> cb @
        .lazy -> that._unlock @
        .lazy ->
          that.trying = false
          done()
        .run()
      process.nextTick retry

  _lock: (cb) ->
    if fs.existsSync @lock_file
      cb 'locked by others'
    else
      fs.writeFileSync @lock_file, 'lock'
      cb()

  _unlock: (cb) ->
    fs.unlink @lock_file, (err) ->
      cb()

class Index
  constructor: (@options, @dataHandle, cb) ->
    @path  = path.join @options.dir, @options.index_file
    @lock  = path.join @options.dir, @options.lock_dir, 'index.lock'
    @cache = {}
    @task  = new Task(@lock)
    @tasks = {}
    @cbs   = []
    @mtime = 0

    fs.open @path, 'a+', (err, fd, stat) =>
      @handle = fd
      @_update cb

  get: (key, cb) ->
    position = @cache[key]
    unless position
      fs.fstat @handle, (err, stat) =>
        if stat.mtime.getTime() is @mtime
          cb()
        else
          @_update => cb null, @cache[key]
    else
      cb null, position

  make: (key, length, cb) ->
    @get key, (err, position) =>
      unless position and length >= position[1]
        @_add key, length, cb
      else
        cb null, position

  _add: (key, length, cb) ->
    length = @options.min_length if length < @options.min_length
    @tasks[key] = length if not @tasks[key] or @tasks[key] < length
    @cbs.push [key, cb]
    @_clearup()

  _clearup: ->
    if @cbs.length
      @task.process (done) =>
        @_process done
      , =>
        @_clearup()
    
  _process: (callback) ->
    tasks = @tasks
    cbs = @cbs
    @tasks = {}
    @cbs = []
    @_getDataLength (err, start) =>
      return cb err if err
      exists = false
      for key, length of tasks
        if @cache[key] then exists = true
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
    @_getLength (err, size) =>
      unless size
        @cache = {}
        return cb()
      buffer = new Buffer size
      fs.read @handle, buffer, 0, size, 0, (err) =>
        @cache = JSON.parse '{'+buffer.toString().trim().replace(/,$/, '')+'}'
        cb()

  _getLength: (cb) ->
    fs.fstat @handle, (err, stat) =>
      @mtime = stat.mtime.getTime()
      cb err, stat.size

  _getDataLength: (cb) ->
    fs.fstat @dataHandle, (err, stat) ->
      cb err, stat.size

module.exports = (options) ->
  new File_DB options
