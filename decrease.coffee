Benchmark = require 'benchmark'
suite = new Benchmark.Suite

file_db = require('./file_db') dir: '/private/var/www/test/shared-memory/tmp'
levelup = require('levelup') './tmp/levelup'

a={b:{length : 10000}}

suite.add '1', ->
  a.b.length-- >= 0

.add '2', ->
  if(a.b.length)
    a.b.length--
  return a.b.length

.on 'complete', ->
  console.log 'Fastest is ' + @filter('fastest').pluck 'name'

.on 'cycle', (event) ->
  console.log a.b.length
  length = 10000
  console.log(String(event.target))

.on 'error', (err) ->
  throw err.target.error

.run async: false
