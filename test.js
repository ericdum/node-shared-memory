var fs = require('fs-extra')
var expect = require("expect.js");
var ep = require('event-pipe')
var db = null
var path = require('path')

//var mp = require('child_process').spawn('node', [path.join(__dirname, '/mp.js'), 10000]);

describe("ready", function(){
  /*
  before.skip(function(done){
    this.timeout = 0;
    mp.stdout.on('data', function(data) {
      console.log(data.toString());
    });
    mp.stderr.on('data', function(data) {
      console.log(data)
    });
    mp.on('close', function (code) {
      console.log('child process exited with code ' + code);
      done()
    });
  });
  //*/
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

describe('mutil-process', function(){
})

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

  it('json', function(done){
    db.set('json', {
      a: 1,
      b: "b",
      c: {
        d: 2,
        c: "c"
      }
    }, function() {
      db.get('json', function(err, data){
        expect(data).to.be.eql({ a: 1, b: 'b', c: { d: 2, c: 'c' } });
        done()
      });
    });
  })

  it('longer json', function(done){
    db.set('json', {
      a: 1,
      b: "b",
      c: {
        d: 2,
        e: "e"
      },
      f: 7572
    }, function() {
      db.get('json', function(err, data){
        expect(data).to.be.eql({ a: 1, b: 'b', c: { d: 2, e: 'e' }, f:7572 });
        done()
      });
    });
  })
});
describe("pop", function(){
  it('should get data back and delete it', function(done){
    db.pop('test', function(err, data){
      expect(data).to.be(1)
      db.get('test', function(err, data){
        expect(data).to.not.be.ok()
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

  it('get empty data', function(done){
    _c = db.index.getAll;
    db.index.getAll = function(cb){
      db.index.getAll = _c;
      cb(null, {})
    }
    db.getAll(function(err, data){
      expect(err).to.not.be.ok()
      expect(data).to.be.eql({})
      done()
    })
  })
});

describe("popAll", function(){
  it('pop All the data', function(done){
    db.popAll(function(err, data){
      expect(err).to.not.be.ok()
      expect(data).to.be.ok()
      expect(Object.keys(data).length).to.above(100)
      db.getAll(function(err, data){
        expect(err).to.not.be.ok()
        expect(data).to.be.ok()
        expect(Object.keys(data).length).to.be(0)
        done()
      })
    })
  })

  it('pop empty data', function(done){
    _c = db.index.getAll;
    db.index.getAll = function(cb){
      db.index.getAll = _c;
      cb(null, {})
    }
    db.popAll(function(err, data){
      expect(err).to.not.be.ok()
      expect(data).to.be.eql({})
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
