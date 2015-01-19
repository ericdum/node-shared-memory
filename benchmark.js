var ab = require('ab');
var db = require('./')({dir: '/tmp/smbh'});
var expect = require('expect.js')

var i = 0
var fn = function (callback) {
  db.increase('benchmark_increase', 1, function(){
    if( i++ >= 5) {
      i = 0
      db.popAll(function(err, data){
        expect(err).to.not.be.ok()
        expect(data.benchmark_increase).above(4)
        callback()
      })
    } else {
      callback()
    }
  })
};

db.ready(function(){
  ab.run(fn, {
      concurrency: 50,
      requests: 10000
  });
});
