const express = require('express');
const cors = require('cors');
const path = require('path');
const routes = require('./routes');
const errorHandler = require('./middlewares/errorHandler');
const { CORS_ORIGIN } = require('./config');

const app = express();

// Middleware cơ bản
app.use(cors({ origin: CORS_ORIGIN }));
app.use(express.json());

// Web Dashboard (static)
app.use('/dashboard', express.static(path.join(__dirname, '..', 'dashboard')));

// Routes
app.use(routes);

// Error handler
app.use(errorHandler);

module.exports = app;
