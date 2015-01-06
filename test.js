var fs = require('fs-extra')
var expect = require("expect.js");
var ep = require('event-pipe')
var db = null

describe("ready", function(){
  before(function(done){
    fs.remove('./tmp', done)
  });
  before(function(){
    db = require('./lib')({dir: './tmp'})
  });
  it('should call all callback for ready when it\'s ready', function(done){
    var i = 0;
    db.ready(function(){
      if(++i==2) done();
    })
    db.ready(function(){
      if(++i==2) done();
    })
  })
  it('should call all callback for ready after it\'s ready', function(done){
    var i = 0;
    db.ready(function(){
      if(++i==2) done();
    })
    db.ready(function(){
      if(++i==2) done();
    })
  })
});

describe("set", function(){
  it('hundred keys', function(done){
    xxx( 100, function(j){
      return function(){ db.set('key'+j, j, this) }
    }, function(){
      i = 100
      while(i-->0) {
        expect(db.index.cache['key'+i]).to.be.ok()
      }
      done()
    })
  })

  it('hundred same keys', function(done){
    xxx( 100, function(j){
      return function(){ db.set('key', j, this) }
    }, done )
  })

  it('should have a callback', function(done){
    db.set('test', 1, function(){
      db.get('test', function(err, data){
        expect(data).to.be(1)
        done()
      })
    })
  })
});

describe("accumulate", function(){
  describe("increase", function(){
    it('second variable default to 1', function(done) {
      db.increase('newkey1', function(){
        regularExpect('newkey1', 1, done);
      })
    })
    it('should create a new varible unless it\'s exists', function(done) {
      db.increase('newkey2', 5, function(){
        regularExpect('newkey2', 5, done);
      })
    })
    it('increase to 501', function(done) {
      xxx( 100, function(j){
        return function(){
          db.increase('newkey1', 5, this)
        }
      }, function(){
        regularExpect('newkey1', 501, done);
      })
    })
  })
  describe("decrease", function(){
    it('second variable default to -1', function(done) {
      db.decrease('newkey3', function(){
        regularExpect('newkey3', -1, done);
      })
    })
    it('should create a new varible unless it\'s exists', function(done) {
      db.decrease('newkey4', 5, function(){
        regularExpect('newkey4', -5, done);
      })
    })
    it('decrease to 201', function(done) {
      xxx( 30, function(j){
        return function(){
          db.decrease('newkey1', 10, this)
        }
      }, function(){
        regularExpect('newkey1', 201, done);
      })
    })
  })
});

describe("getAll", function(){
  it('get All the data', function(done){
    db.getAll(function(err, data){
      expect(err).to.not.be.ok()
      expect(data).to.be.ok()
      expect(Object.keys(data).length).to.above(100)
      done()
    })
  })
});

function regularExpect(key, value, cb) {
  db.get(key, function(err, data){
    expect(data).to.be(value)
    cb()
  });
}

function bench(func, done) {
  p = ep()
  p.lazy(func)
  p.on('error', function(err){
    expect().fail(err)
  })
  p.lazy(function(){
    done()
  })
  p.run()
}

function xxx(i, maker, done) {
  func = []
  while(i-->0) {
    func.push(maker(i))
  }
  bench(func, done)
}
