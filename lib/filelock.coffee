fs = require 'fs'
class Filelock
  constructor: ->

  _try: (path, cb) ->
    try
      @_do path, cb
    catch e
      console.log e, 'xxxxxxx'
      @lock path, cb

  _do: (path, cb) ->
    _this = @
    fs.open path, 'wx', (err, fd) ->
      if err
        _this.lock path, cb
      else
        fs.close fd, cb

  lock: (path, cb) ->
    process.nextTick =>
      @_try path, cb

  unlock: (path, cb) ->
    fs.unlink path, cb

module.exports = new Filelock()
