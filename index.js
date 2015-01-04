if (require.extensions['.coffee']) {
  module.exports = require('./lib/index.coffee');
} else {
  module.exports = require('./out/release/lib/index.js');
}
