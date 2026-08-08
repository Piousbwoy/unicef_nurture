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
  // Legacy global bearer token — kept for a brief transition window only.
  // Set to a non-empty string to allow legacy-device writes during rollout;
  // clear it completely once every device is on the JWT auth flow.
  syncApiToken: process.env.SYNC_API_TOKEN ? process.env.SYNC_API_TOKEN.trim() : null,
  jwt: {
    issuer: process.env.JWT_ISSUER || 'carebridge-sync',
    audience: process.env.JWT_AUDIENCE || 'carebridge-clients',
    accessSecret: required('JWT_ACCESS_SECRET'),
    refreshSecret: required('JWT_REFRESH_SECRET'),
    accessTtlMinutes: parseInt(process.env.JWT_ACCESS_TTL_MINUTES || '720', 10),
    refreshTtlDays: parseInt(process.env.JWT_REFRESH_TTL_DAYS || '30', 10),
  },
  rate: {
    maxAttempts: parseInt(process.env.AUTH_RATE_MAX_ATTEMPTS || '10', 10),
    windowSeconds: parseInt(process.env.AUTH_RATE_WINDOW_SECONDS || '60', 10),
    lockSeconds: parseInt(process.env.AUTH_RATE_LOCK_SECONDS || '300', 10),
  },
};

const jwt = config.jwt;
if (jwt.accessSecret.length < 32 || jwt.refreshSecret.length < 32) {
  console.warn(
    'WARNING: JWT secrets are shorter than 32 characters. ' +
      'Generate with: node -e "console.log(require(\'crypto\').randomBytes(48).toString(\'hex\'))"'
  );
}
if (jwt.accessSecret === jwt.refreshSecret) {
  throw new Error(
    'JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be different values.'
  );
}

module.exports = config;
