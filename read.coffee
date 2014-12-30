Benchmark = require 'benchmark'
suite = new Benchmark.Suite
ab = require 'ab'

fs = require 'fs'

file = '/private/var/www/test/shared-memory/tmp/index.fd'
fs.open file, 'a+', (err, fd) ->

  fn = (cb) ->
    fs.fstat fd, (err, stat) ->
      buffer = new Buffer stat.size
      fs.read fd, buffer, 0, stat.size, 0, cb
  ab.run fn, {concurrency: 50, requests: 10000}
