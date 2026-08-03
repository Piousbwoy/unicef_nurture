// Loads and validates environment configuration. Fails fast and loudly at
// startup rather than misbehaving at runtime — a sync server that silently
// drops to defaults is how health records go missing.
'use strict';

require('dotenv').config();

function required(name) {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(
      `Missing required environment variable ${name}. ` +
        'Copy .env.example to .env and fill it in.'
    );
  }
  return value.trim();
}

const config = {
  db: {
    host: required('DB_HOST'),
    port: parseInt(process.env.DB_PORT || '3306', 10),
    user: required('DB_USER'),
    password: required('DB_PASSWORD'),
    name: required('DB_NAME'),
  },
  port: parseInt(process.env.PORT || '3000', 10),
  // A sync server with no token configured must refuse everything. Failing
  // open would let anyone on the network write to the district database.
  syncApiToken: required('SYNC_API_TOKEN'),
};

// Guard against shipping the placeholder straight into production.
if (config.syncApiToken === 'change-me-to-a-long-random-token') {
  // eslint-disable-next-line no-console
  console.warn(
    'WARNING: SYNC_API_TOKEN is still the placeholder from .env.example. ' +
      'Set a real random token before trusting this server with records.'
  );
}

module.exports = config;
