class Pool
  constructor: (@name, @process) ->
    @acc = 0
    @cbs = []
    @updating = false

  add: (acc, cb) ->
    @acc += acc
    @cbs.push cb
    @update() unless @updating

  update: ->
    return if @updating
    return unless @acc
    @updating = true
    acc = @acc
    cbs = @cbs
    @acc = 0
    @cbs = []
    @process acc, =>
      while cb = cbs.pop()
        cb()
      @updating = false
      @update()



pool = {}
module.exports = (key, acc, cb, process) ->
  unless pool[key]
    pool[key] = new Pool key, process

  pool[key].add acc, cb
