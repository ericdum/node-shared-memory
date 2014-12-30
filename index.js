// Generated by CoffeeScript 1.8.0
(function() {
  var File_DB, Index, Task, ep, fs, mkdirpSync, os, path;

  path = require('path');

  fs = require('fs');

  os = require('options-stream');

  ep = require('event-pipe');


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
      var cb, flow, _db;
      this.options = os({
        dir: '/tmp',
        index_file: 'index.fd',
        data_file: 'data.fd',
        lock_dir: 'locks',
        min_length: 8
      }, options);
      if (fs.existsSync('/shm/')) {
        this.options.dir = path.join('/shm', this.options.dir);
      }
      if (!fs.existsSync(this.options.dir)) {
        mkdirpSync(this.options.dir);
      }
      this.indexPath = path.join(this.options.dir, this.options.index_file);
      this.dataPath = path.join(this.options.dir, this.options.data_file);
      this.indexCache = {};
      this._tasks = {};
      this._ready = false;
      cb = (function(_this) {
        return function(err) {
          var callback, _i, _len, _ref, _results;
          if (err) {
            console.log(err);
            _this._error = err;
          } else {
            _this._ready = true;
          }
          _ref = _this.callbacks;
          _results = [];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            callback = _ref[_i];
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
      var pos, _buffer;
      if (!cb) {
        cb = function() {};
      }
      if (!this.index.get(key)) {
        return cb(new Error('key not found!'));
      }
      pos = this.index.get(key);
      _buffer = new Buffer(pos[1]);
      return fs.read(this.dataHandle, _buffer, 0, pos[1], pos[0], (function(_this) {
        return function(err) {
          var data;
          if (err) {
            return cb(err);
          }
          data = _buffer.toString().trim();
          if (!isNaN(data)) {
            return cb(null, new Number(data));
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
      return this.index.has(key, val.length, (function(_this) {
        return function(err, position) {
          var task;
          if (err) {
            cb(err);
          }
          task = new Task(path.join(_this.options.dir, _this.options.lock_dir, key + '.lock'));
          return task.process(function() {
            return _this._saveData(key, val, position, cb);
          });
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

  Task = (function() {
    function Task(lock_file) {
      this.lock_file = lock_file;
      this.trying = false;
    }

    Task.prototype.process = function(cb) {
      var retry, that;
      if (!this.trying) {
        this.trying = true;
        that = this;
        retry = function() {
          var flow;
          flow = ep();
          return flow.on('error', function(err) {
            if (err === 'locked by others') {
              return process.nextTick(retry);
            } else {
              return cb(err);
            }
          }).lazy(function() {
            return that._lock(this);
          }).lazy(function() {
            return _process(this);
          }).lazy(function() {
            return that._unlock(this);
          }).lazy(function() {
            that.trying = false;
            return cb();
          }).run();
        };
        return process.nextTick(retry);
      }
    };

    Task.prototype._lock = function(cb) {
      return fs.exists(this.lock_file, (function(_this) {
        return function(exists) {
          if (exists) {
            return cb('locked by others');
          }
          return fs.open(_this.lock_file, 'w', function(err, fd) {
            if (err) {
              return cb(err);
            }
            fs.closeSync(fd);
            return cb();
          });
        };
      })(this));
    };

    Task.prototype._unlock = function(cb) {
      return fs.unlink(this.lock_file, function(err) {
        if (err) {
          console.log('unlock error', err);
        }
        return cb();
      });
    };

    return Task;

  })();

  Index = (function() {
    function Index(options, dataHandle, cb) {
      this.options = options;
      this.dataHandle = dataHandle;
      this.path = path.join(this.options.dir, this.options.index_file);
      this.lock = path.join(this.options.dir, this.options.lock_dir, 'index.lock');
      this.cache = {};
      this.task = new Task(this.lock);
      this.tasks = {};
      this.cbs = [];
      fs.open(this.path, 'a+', (function(_this) {
        return function(err, fd) {
          _this.handle = fd;
          return _this._update(cb);
        };
      })(this));
    }

    Index.prototype.get = function(key) {
      return this.cache[key];
    };

    Index.prototype.has = function(key, length, cb) {
      var position;
      position = this.get(key);
      if (!(position && length < position[1])) {
        return this._try(key, length, cb);
      } else {
        return cb(null, position);
      }
    };

    Index.prototype._try = function(key, length, cb) {
      if (length < this.options.min_length) {
        length = this.options.min_length;
      }
      if (!this.tasks[key] || this.tasks[key] < length) {
        this.tasks[key] = length;
      }
      this.cbs.push([key, cb]);
      return this.task.process((function(_this) {
        return function() {
          return _this._process(cb);
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
            _this.cache[key] = [start, length];
            if (_this.cache[key]) {
              exists = true;
            }
          }
          if (exists) {
            data = JSON.stringify(_this.cache).replace(/^{|}$/g, "") + ',';
            return fs.write(_this.handle, new Buffer(data), 0, data.length, 0, function(err, written) {
              var cb, _i, _len, _ref, _results;
              _results = [];
              for (_i = 0, _len = cbs.length; _i < _len; _i++) {
                _ref = cbs[_i], key = _ref[0], cb = _ref[1];
                _results.push(cb(null, _this.cache[key]));
              }
              return _results;
            });
          } else {
            data = "";
            for (key in tasks) {
              length = tasks[key];
              data += "\"" + key + "\":" + (JSON.stringify(_this.indexCache[key])) + ",";
            }
            return _this._getLength(function(err, size) {
              return fs.write(_this.handle, new Buffer(data), 0, data.length, size, function(err, written) {
                var cb, _i, _len, _ref, _results;
                _results = [];
                for (_i = 0, _len = cbs.length; _i < _len; _i++) {
                  _ref = cbs[_i], key = _ref[0], cb = _ref[1];
                  _results.push(cb(null, _this.cache[key]));
                }
                return _results;
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
      return fs.fstat(this.handle, function(err, stat) {
        return cb(err, stat.size);
      });
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

}).call(this);
