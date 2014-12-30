file_db = require('./lib') dir: '/tmp/shared-memory/tmp'
file_db.ready ->
  file_db.set 'test7', '1done', ->
    file_db.get 'test7', console.log
