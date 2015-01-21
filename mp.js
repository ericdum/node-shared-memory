var fs = require('fs-extra');
var cluster = require('cluster');
var ep = require('event-pipe');

if(cluster.isMaster) {
  var cpu = require('os').cpus().length;
  cpu = cpu < 2 ? 2 : cpu;
  fs.remove('./tmp/mp', function(){
    var i=0;
    var j=1;
    while( i++ < cpu ) {
      worker = cluster.fork();
      worker.on('exit', function(){
        console.log(arguments);
        if(++j == cpu){ 
          console.log('done');
          process.exit(0);
        }
      })
    }
  })

} else {
  var max = process.argv[2] || 100;
  var max = parseInt(max);
  var db = require('./out/release/lib')({dir: './tmp/mp'})
  db.ready(function(){
    setTimeout(function(){
      var i = 0;
      var func = [];
      while(i++ < max){
        (function(i){
          func.push(function(){
          db.increase('key'+i, this);
        })
        })(i);
      }
      p = ep()
      p.on('error', function(err){
        a = new Error()
        console.log(a.stack)
        console.log(err, '=========')
        process.exit(1);
      })
      p.lazy(func)
      p.lazy(function(){
        process.exit(0);
      })
      p.run()
    }, 2000);
  });
}

