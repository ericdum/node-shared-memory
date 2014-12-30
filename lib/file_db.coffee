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

class File_DB
  constructor: (options) ->
    @options = os
      dir: '/tmp'
      index_file: 'index.fd'
      data_file: 'data.fd'
      lock_dir: 'locks'
      min_length: 8
    , options

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

  ready: (cb) ->
    if @_error then cb @_error
    else cb null, @_ready

  get: (key, cb) ->
    unless cb then cb = ->
    return cb new Error 'key not found!' unless @index.get key
    pos = @index.get key
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
    @index.has key, val.length, (err, position) =>
      cb err
      task = new Task path.join @options.dir, @options.lock_dir, key+'.lock'
      task.process (cb) =>
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

  process: (_process) ->
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
        .lazy -> _process @
        .lazy -> that._unlock @
        .lazy ->
          that.trying = false
          @()
        .run()
      process.nextTick retry

  _lock: (cb) ->
    fs.exists @lock_file, (exists) =>
      return cb 'locked by others' if exists
      fs.open @lock_file, 'w', (err, fd) =>
        cb err if err
        fs.closeSync(fd)
        cb()

  _unlock: (cb) ->
    fs.unlink @lock_file, (err) ->
      #console.log 'unlock err', err if err
      cb()

class Index
  constructor: (@options, @dataHandle, cb) ->
    @path  = path.join @options.dir, @options.index_file
    @lock  = path.join @options.dir, @options.lock_dir, 'index.lock'
    @cache = {}
    @task  = new Task(@lock)
    @tasks = {}
    @cbs   = {}

    fs.open @path, 'a+', (err, fd) =>
      @handle = fd
      @_update cb

  get: (key) ->
    @cache[key]

  has: (key, length, cb) ->
    position = @get key
    unless position and length < position[1]
      @_try key, length, cb
    else
      cb null, position

  _try: (key, length, cb) ->
    length = @options.min_length if length < @options.min_length
    @tasks[key] = length if not @tasks[key] or @tasks[key] < length
    @cbs[key] = cb
    @task.process (cb)=>
      @_process cb
    
  _process: (callback) ->
    tasks = @tasks
    cbs = @cbs
    @tasks = {}
    @cbs = {}
    @_getDataLength (err, start) =>
      return cb err if err
      exists = false
      for key, length of tasks
        @cache[key] = [start, length]
        if @cache[key] then exists = true
      if exists
        data = JSON.stringify(@cache).replace(/^{|}$/g,"") + ','
        fs.write @handle, new Buffer(data), 0, data.length, 0, (err, written)=>
          for key, cb of cbs
            cb null, @cache[key]
          callback err
      else
        data = ""
        for key, length of tasks
          data += "\"#{key}\":#{JSON.stringify(@indexCache[key])},"
        @_getLength (err, size) =>
          fs.write @handle, new Buffer(data), 0, data.length, size, (err, written)=>
            for key, cb of cbs
              cb null, @cache[key]
            callback err

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
    fs.fstat @handle, (err, stat) ->
      cb err, stat.size

  _getDataLength: (cb) ->
    fs.fstat @dataHandle, (err, stat) ->
      cb err, stat.size

module.exports = (options) ->
  new File_DB options
