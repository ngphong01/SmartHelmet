const http = require('http');
const app = require('./app');
const sockets = require('./sockets');
const { PORT, CORS_ORIGIN, MONGODB_URI } = require('./config');
const logger = require('./utils/logger');
const { connectMongo } = require('./config/db');

(async () => {
  try {
    await connectMongo(MONGODB_URI);
    const server = http.createServer(app);
    sockets.init(server, CORS_ORIGIN);

    // THÊM '0.0.0.0' ĐỂ NGHE TỪ MẠNG LAN
    server.listen(PORT, '0.0.0.0', () => {
      logger.info(`API + Socket.IO listening on http://0.0.0.0:${PORT}`);
      logger.info(`LAN access depends on your machine IP, not a hardcoded value.`);
    });
  } catch (e) {
    logger.error('Failed to start:', e.message); 
    process.exit(1);
  }
})();