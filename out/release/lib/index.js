// Generated by CoffeeScript 1.8.0
var File_DB, Index, ep, fs, lockfile, mkdirpSync, os, path;

path = require('path');

fs = require('fs');

os = require('options-stream');

ep = require('event-pipe');

lockfile = require('lockfile');


/*
 * properties:
 *   options
 *   indexPath
 *   dataPath
 *   indexHandle
 *   dataHandle
 *
 *   indexCache
 *
 * usage:
 * new
 * ready
 * set
 * get
 *
 */

mkdirpSync = function(uri) {
  if (!fs.existsSync(uri)) {
    mkdirpSync(uri.split('/').slice(0, -1).join('/'));
    console.log('mkdir', uri);
    return fs.mkdirSync(uri);
  }
};

File_DB = (function() {
  function File_DB(options) {
    var cb, file, flow, lock_dir, _db, _i, _len, _ref;
    this.options = os({
      dir: '/tmp',
      index_file: 'index.fd',
      data_file: 'data.fd',
      lock_dir: 'locks',
      min_length: 8,
      lock_opt: {
        wait: 50000,
        pollPeriod: 5,
        stale: 10000
      }
    }, options);
    if (fs.existsSync('/shm/')) {
      this.options.dir = path.join('/shm', this.options.dir);
    }
    if (!fs.existsSync(this.options.dir)) {
      mkdirpSync(this.options.dir);
    }
    lock_dir = path.join(this.options.dir, this.options.lock_dir);
    if (fs.existsSync(lock_dir)) {
      _ref = fs.readdirSync(lock_dir);
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        file = _ref[_i];
        fs.unlinkSync(path.join(lock_dir, file));
      }
      fs.rmdirSync(lock_dir);
    }
    fs.mkdirSync(lock_dir);
    this.indexPath = path.join(this.options.dir, this.options.index_file);
    this.dataPath = path.join(this.options.dir, this.options.data_file);
    this.indexCache = {};
    this._tasks = {};
    this._ready = false;
    cb = (function(_this) {
      return function(err) {
        var callback, _j, _len1, _ref1, _results;
        if (err) {
          _this._error = err;
        } else {
          _this._ready = true;
        }
        _ref1 = _this.callbacks;
        _results = [];
        for (_j = 0, _len1 = _ref1.length; _j < _len1; _j++) {
          callback = _ref1[_j];
          _results.push(callback(_this._error, _this._ready));
        }
        return _results;
      };
    })(this);
    _db = this;
    flow = ep();
    flow.on('error', cb).lazy(function() {
      return fs.open(_db.dataPath, 'a+', this);
    }).lazy(function(fd) {
      _db.dataHandle = fd;
      return _db.index = new Index(_db.options, fd, this);
    }).lazy(function() {
      return cb();
    }).run();
    this.callbacks = [];
  }

  File_DB.prototype.ready = function(callback) {
    if (!this._ready) {
      return this.callbacks.push(callback);
    } else {
      return callback(this._error, this._ready);
    }
  };

  File_DB.prototype.get = function(key, cb) {
    if (!cb) {
      cb = function() {};
    }
    return this.index.get(key, (function(_this) {
      return function(err, pos) {
        if (!pos) {
          return cb(new Error('key not found!'));
        }
        return _this._getData(pos, cb);
      };
    })(this));
  };

  File_DB.prototype.increase = function(key, num, cb) {
    if (num === 0) {
      return cb();
    }
    if (typeof num === 'function') {
      cb = num;
      num = 1;
    }
    if (!num) {
      num = 1;
    }
    return this._accumulate(key, num, cb);
  };

  File_DB.prototype.decrease = function(key, num, cb) {
    if (num === 0) {
      return cb();
    }
    if (typeof num === 'function') {
      cb = num;
      num = -1;
    }
    if (!num) {
      num = -1;
    }
    if (num > 0) {
      num = -num;
    }
    return this._accumulate(key, num, cb);
  };

  File_DB.prototype._accumulate = function(key, acc, cb) {
    if (!cb) {
      cb = function() {};
    }
    return this._process(key, cb, (function(_this) {
      return function(done) {
        return _this.index.get(key, function(err, pos) {
          if (!pos) {
            return _this._write(key, acc.toString(), done);
          } else {
            return _this._getData(pos, function(err, num) {
              num += acc;
              num = num.toString();
              if (num.length > pos[1]) {
                return _this._write(key, num, done);
              } else {
                return _this._saveData(key, num, pos, done);
              }
            });
          }
        });
      };
    })(this));
  };

  File_DB.prototype._process = function(key, done, cb) {
    var lock_file, the;
    the = this;
    lock_file = path.join(this.options.dir, this.options.lock_dir, key + '.lock');
    return lockfile.lock(lock_file, this.options.lock_opt, function(err) {
      if (err) {
        return done(err);
      } else {
        return cb(function() {
          return lockfile.unlock(lock_file, done);
        });
      }
    });
  };

  File_DB.prototype._getData = function(pos, cb) {
    var _buffer;
    _buffer = new Buffer(pos[1]);
    return fs.read(this.dataHandle, _buffer, 0, pos[1], pos[0], (function(_this) {
      return function(err) {
        var data;
        if (err) {
          return cb(err);
        }
        data = _buffer.toString().trim();
        if (!isNaN(data)) {
          return cb(null, 1 * data);
        } else {
          return cb(null, _this._try_object(data));
        }
      };
    })(this));
  };

  File_DB.prototype.set = function(key, val, cb) {
    if (!cb) {
      cb = function() {};
    }
    if (typeof val !== 'string') {
      val = JSON.stringify(val);
    }
    return this._write(key, val, cb);
  };

  File_DB.prototype._write = function(key, val, cb) {
    return this.index.ensure(key, val.length, (function(_this) {
      return function(err, position) {
        if (err) {
          return cb(err);
        }
        return _this._saveData(key, val, position, cb);
      };
    })(this));
  };

  File_DB.prototype._saveData = function(key, val, _arg, cb) {
    var data, length, start;
    start = _arg[0], length = _arg[1];
    val = val.toString();
    if (val.length < length) {
      val = (new Array(length - val.length + 1)).join(' ') + val;
    }
    data = new Buffer(val);
    return fs.write(this.dataHandle, new Buffer(val), 0, length, start, cb);
  };

  File_DB.prototype._try_object = function(data) {
    var e;
    try {
      return JSON.parse(data);
    } catch (_error) {
      e = _error;
      return data;
    }
  };

  return File_DB;

})();

Index = (function() {
  function Index(options, dataHandle, cb) {
    this.options = options;
    this.dataHandle = dataHandle;
    this.path = path.join(this.options.dir, this.options.index_file);
    this.lock = path.join(this.options.dir, this.options.lock_dir, 'index.lock');
    this.cache = {};
    this.tasks = {};
    this.cbs = [];
    this.mtime = 0;
    fs.open(this.path, 'a+', (function(_this) {
      return function(err, fd, stat) {
        _this.handle = fd;
        return _this._update(cb);
      };
    })(this));
  }

  Index.prototype.get = function(key, cb) {
    var position;
    position = this.cache[key];
    if (!position) {
      return fs.fstat(this.handle, (function(_this) {
        return function(err, stat) {
          if (stat.mtime.getTime() === _this.mtime) {
            return cb();
          } else {
            return _this._update(function() {
              return cb(null, _this.cache[key]);
            });
          }
        };
      })(this));
    } else {
      return cb(null, position);
    }
  };

  Index.prototype.ensure = function(key, length, cb) {
    return this.get(key, (function(_this) {
      return function(err, position) {
        if (!(position && length >= position[1])) {
          return _this._add(key, length, cb);
        } else {
          return cb(null, position);
        }
      };
    })(this));
  };

  Index.prototype._add = function(key, length, cb) {
    if (length < this.options.min_length) {
      length = this.options.min_length;
    }
    if (!this.tasks[key] || this.tasks[key] < length) {
      this.tasks[key] = length;
    }
    this.cbs.push([key, cb]);
    return this._clearup();
  };

  Index.prototype._clearup = function() {
    if (this.clearing) {
      return;
    }
    this.clearing = true;
    return lockfile.lock(this.lock, this.options.lock_opt, (function(_this) {
      return function(err) {
        if (err) {
          return setTimeout(function() {
            _this.clearing = false;
            return _this._clearup();
          }, 10);
        } else {
          return _this._process(function() {
            return lockfile.unlock(_this.lock, function() {
              _this.clearing = false;
              if (_this.cbs.length) {
                return _this._clearup();
              }
            });
          });
        }
      };
    })(this));
  };

  Index.prototype._process = function(callback) {
    var cbs, tasks;
    tasks = this.tasks;
    cbs = this.cbs;
    this.tasks = {};
    this.cbs = [];
    return this._getDataLength((function(_this) {
      return function(err, start) {
        var data, exists, key, length;
        if (err) {
          return cb(err);
        }
        exists = false;
        for (key in tasks) {
          length = tasks[key];
          if (_this.cache[key]) {
            if (_this.cache[key][1] <= length) {
              continue;
            }
            exists = true;
          }
          _this.cache[key] = [start, length];
          start += length;
        }
        if (exists) {
          data = JSON.stringify(_this.cache).replace(/^{|}$/g, "") + ',';
          return fs.write(_this.handle, new Buffer(data), 0, data.length, 0, function(err, written) {
            var cb, _i, _len, _ref;
            for (_i = 0, _len = cbs.length; _i < _len; _i++) {
              _ref = cbs[_i], key = _ref[0], cb = _ref[1];
              cb(null, _this.cache[key]);
            }
            return callback();
          });
        } else {
          data = "";
          for (key in tasks) {
            length = tasks[key];
            data += "\"" + key + "\":" + (JSON.stringify(_this.cache[key])) + ",";
          }
          return _this._getLength(function(err, size) {
            return fs.write(_this.handle, new Buffer(data), 0, data.length, size, function(err, written) {
              var cb, _i, _len, _ref;
              for (_i = 0, _len = cbs.length; _i < _len; _i++) {
                _ref = cbs[_i], key = _ref[0], cb = _ref[1];
                cb(null, _this.cache[key]);
              }
              return callback();
            });
          });
        }
      };
    })(this));
  };

  Index.prototype._update = function(cb) {
    return this._getLength((function(_this) {
      return function(err, size) {
        var buffer;
        if (!size) {
          _this.cache = {};
          return cb();
        }
        buffer = new Buffer(size);
        return fs.read(_this.handle, buffer, 0, size, 0, function(err) {
          _this.cache = JSON.parse('{' + buffer.toString().trim().replace(/,$/, '') + '}');
          return cb();
        });
      };
    })(this));
  };

  Index.prototype._getLength = function(cb) {
    return fs.fstat(this.handle, (function(_this) {
      return function(err, stat) {
        _this.mtime = stat.mtime.getTime();
        return cb(err, stat.size);
      };
    })(this));
  };

  Index.prototype._getDataLength = function(cb) {
    return fs.fstat(this.dataHandle, function(err, stat) {
      return cb(err, stat.size);
    });
  };

  return Index;

})();

module.exports = function(options) {
  return new File_DB(options);
};
