Benchmark = require 'benchmark'
suite = new Benchmark.Suite

file_db = require('./file_db') dir: '/private/var/www/test/shared-memory/tmp'
levelup = require('levelup') './tmp/levelup'

length = 10000
keys1 = []
keys2 = []


setTimeout ->
  ab = require('ab')
  fn = (callback)->
    key = data[parseInt(Math.random()*(data.length-1))]
    #process.nextTick callback
    file_db.get key, callback
  ab.run fn, {concurrency: 50, requests: 10000}
, 1000
###
ab = require('ab')
fn = (callback)->
  key = 'somekey' + parseInt(Math.random()*length)
  levelup.put key, key, callback
ab.run fn, {concurrency: 50, requests: 10000}

suite.add 'as', ->
  key = 'somekey' + parseInt(Math.random()*length)
  keys1.push key
  file_db.set key, key

.add 'levelup', ->
  key = 'somekey' + parseInt(Math.random()*length)
  keys2.push key
  levelup.put key, key

.add 'file db change keys', ->
  i = parseInt(Math.random()*(keys1.length-1))
  file_db.put get, ->
  file_db.set keys1[i], i

.add 'levelup', ->
  i = parseInt(Math.random()*(keys2.length-1))
  levelup.put keys2[i], i

.add 'file db get value', ->
  i = parseInt(Math.random()*(keys1.length-1))
  file_db.get keys1[i], ->

.add 'levelup', ->
  i = parseInt(Math.random()*(keys2.length-1))
  levelup.get keys2[i], ->

.on 'complete', ->
  console.log 'Fastest is ' + @filter('fastest').pluck 'name'

.on 'cycle', (event) ->
  console.log(String(event.target))

.on 'error', (err) ->
  throw err.target.error

.run async: false
  ####
