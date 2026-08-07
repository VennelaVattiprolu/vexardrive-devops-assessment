// Centralized configuration loader.
//
// Design decision: fail fast at startup if required secrets/config are missing,
// rather than falling back to hardcoded defaults (which is what caused the
// original hardcoded-credentials issue). In Azure this is populated via
// Key Vault references injected as env vars / Container Apps secrets - see
// infra/ and docs/REPORT.md for how these are supplied in each environment.

require("dotenv").config();

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const config = {
  env: process.env.NODE_ENV || "development",
  port: parseInt(process.env.PORT || "3000", 10),

  db: {
    host: required("DB_HOST"),
    port: parseInt(process.env.DB_PORT || "5432", 10),
    user: required("DB_USER"),
    password: required("DB_PASSWORD"),
    database: required("DB_NAME"),
    // Azure Database for PostgreSQL requires SSL; allow opt-out only for local dev.
    ssl: process.env.DB_SSL === "false" ? false : { rejectUnauthorized: true },
    poolMax: parseInt(process.env.DB_POOL_MAX || "10", 10),
    poolIdleTimeoutMs: parseInt(process.env.DB_POOL_IDLE_TIMEOUT_MS || "30000", 10),
  },

  jwt: {
    secret: required("JWT_SECRET"),
    expiresIn: process.env.JWT_EXPIRES_IN || "24h",
  },

  otp: {
    ttlSeconds: parseInt(process.env.OTP_TTL_SECONDS || "300", 10), // 5 minutes
    maxAttempts: parseInt(process.env.OTP_MAX_ATTEMPTS || "5", 10),
    // In production this integrates with an SMS provider (Twilio/Azure
    // Communication Services). Out of scope for this assessment - we log
    // the OTP server-side instead so the flow can be demoed end-to-end.
    devLogOtp: process.env.NODE_ENV !== "production",
  },
};

module.exports = config;
