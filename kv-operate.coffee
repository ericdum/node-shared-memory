Benchmark = require 'benchmark'
suite = new Benchmark.Suite

buffer = new Buffer(12)

json = {}
csv = []
partition = [[], []]
length = 10000
i=-1
while i++ < length
  json['somekey'+i] = i
  csv.push 'somekey'+i+'='+i
csv = csv.join(',')

suite.add 'json', ->
  key = 'somekey' + parseInt(Math.random()*length)
  parseInt(json[key])
  JSON.stringify json

  ###
.add 'csv', ->
  key = 'somekey' + parseInt(Math.random()*length)
  w = csv.match(new RegExp('\\b'+key+'=(\\d+)'))[1]
  a = parseInt(csv.search(new RegExp('(?:^|,)'+key)))
  b = w.length
  parseInt w

.add 'split', ->
  key = 'somekey' + parseInt(Math.random()*length)
  _csv = csv.split new RegExp '\\b'+key+'='
  w = _csv[1].match(/\d+/)[0]
  a = _csv[0].length
  b = w.length
  parseInt w
  ###

.add 'split 2', ->
  key = 'somekey' + parseInt(Math.random()*length)
  a = csv.search new RegExp '\\b'+key+'='
  w = csv.substr( a+key.length+1).match(/\d+/)[0]
  b = w.length
  parseInt w

.on 'complete', ->
  console.log 'Fastest is ' + @filter('fastest').pluck 'name'

.on 'cycle', (event) ->
  console.log(String(event.target))

.on 'error', (err) ->
  throw err.target.error

.run async: false
