Benchmark = require 'benchmark'
suite = new Benchmark.Suite

buffer = new Buffer(12)

json = {}
#csv = []
i=0
while i++ < 10000
  json['somekey'+i] = i
  #csv.push 'somekey'+i+'='+i

j=0
suite.add 'json', ->
  JSON.parse JSON.stringify json

.add 'csv', ->
  csv = []
  for i of json
    csv.push i+'='+json[i]
  csv = csv.join(',')
  csv = csv.split(',')
  json2 = {}
  for i of csv
    v = csv[i].split '='
    json2[v[0]] = v[1]

.on 'complete', ->
  console.log 'Fastest is ' + @filter('fastest').pluck 'name'

.on 'cycle', (event) ->
  console.log(String(event.target))

.run async: false
