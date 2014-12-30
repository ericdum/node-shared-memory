Benchmark = require 'benchmark'
path = require 'path'
fs = require 'fs'

suite = new Benchmark.Suite

buffer = new Buffer(12)

buffer.write ' ', 5,1
buffer.write 'hello', 0, 5
buffer.write '!', 11, 1
buffer.fill 'world', 6, 11
file = path.join __dirname, 'test.data'
fs.open file, 'r+', (err, fd) ->
  console.log buffer.toString()
  #fs.write fd, buffer, 0, 12, 12, -> console.log arguments
  buf = new Buffer 12
  fs.read fd, buf, 0, 12, 12, (err, d, buffer)-> console.log arguments; console.log buf.toString()
  console.log err, fd

fs.open file, 'a+', (err, fd) ->
  fs.fstat fd, (err, stat) ->
    console.log stat.size

  
