// Was: `new Client()` opened and torn down on EVERY request (including the
// high-frequency /api/fleet/ping endpoint). Under any real fleet load this
// exhausts Postgres's max_connections almost immediately, since each
// connection carries real setup/teardown cost and Postgres connections are
// comparatively expensive relative to e.g. a threadpool.
//
// Fix: a single shared connection pool for the process lifetime. Sized
// conservatively (default 10) because Azure Database for PostgreSQL Flexible
// Server has a hard connection ceiling per SKU - see docs/REPORT.md, Database
// Operations, for how this is expected to evolve (PgBouncer/pooler) as fleet
// size grows and we run multiple app replicas each holding their own pool.

const { Pool } = require("pg");
const config = require("./config");
const logger = require("./logger");

const pool = new Pool({
  host: config.db.host,
  port: config.db.port,
  user: config.db.user,
  password: config.db.password,
  database: config.db.database,
  ssl: config.db.ssl,
  max: config.db.poolMax,
  idleTimeoutMillis: config.db.poolIdleTimeoutMs,
  connectionTimeoutMillis: 5000,
});

pool.on("error", (err) => {
  // Fired on idle client errors (e.g. connection dropped by server) - must be
  // handled or an unhandled 'error' event crashes the whole process.
  logger.error({ err }, "Unexpected error on idle Postgres client");
});

async function healthCheck() {
  const client = await pool.connect();
  try {
    await client.query("SELECT 1");
    return true;
  } finally {
    client.release();
  }
}

module.exports = { pool, healthCheck };
