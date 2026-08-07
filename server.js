// VexarDrive - Fleet Ping Service
//
// Rewritten from the original single-file version as part of the DevOps
// assessment. See docs/REPORT.md for the full list of issues found and the
// reasoning behind each change. Summary of what changed here:
//   - No more hardcoded DB credentials / JWT secret (src/config.js, env-driven)
//   - No more `new Client()` per request (src/db.js, pooled)
//   - Auth bypass + SQL injection fixed (src/routes/auth.js)
//   - Unauthenticated admin endpoint now requires admin JWT (src/routes/admin.js)
//   - Added /healthz and /readyz for container orchestration
//   - Added structured (pino) logging
//   - Added graceful shutdown on SIGTERM/SIGINT

const express = require("express");
const helmet = require("helmet");
const pinoHttp = require("pino-http");

const config = require("./src/config");
const logger = require("./src/logger");
const { pool } = require("./src/db");

const healthRoutes = require("./src/routes/health");
const authRoutes = require("./src/routes/auth");
const fleetRoutes = require("./src/routes/fleet");
const adminRoutes = require("./src/routes/admin");

const app = express();

app.use(helmet());
app.use(express.json({ limit: "100kb" }));
app.use(pinoHttp({ logger }));

app.get("/", (req, res) => {
  res.send("VexarDrive Fleet Ping Service is running");
});

app.use("/", healthRoutes);
app.use("/api/auth", authRoutes);
app.use("/api/fleet", fleetRoutes);
app.use("/api/admin", adminRoutes);

// Centralized error handler - catches anything thrown/rejected in routes
// that wasn't already handled, so a bug can't leak stack traces to clients.
app.use((err, req, res, next) => {
  logger.error({ err }, "unhandled request error");
  res.status(500).json({ error: "internal server error" });
});

const server = app.listen(config.port, () => {
  logger.info(`Server listening on port ${config.port}`);
});

// Graceful shutdown: was completely absent, meaning every deploy/scale-down
// killed in-flight requests outright. Container Apps/AKS send SIGTERM and
// wait a grace period before SIGKILL - we use that window to stop accepting
// new connections, let in-flight ones finish, then close the DB pool.
function shutdown(signal) {
  logger.info(`${signal} received, shutting down gracefully`);
  server.close(async (err) => {
    if (err) {
      logger.error({ err }, "error during server close");
      process.exit(1);
    }
    try {
      await pool.end();
      logger.info("shutdown complete");
      process.exit(0);
    } catch (poolErr) {
      logger.error({ err: poolErr }, "error closing db pool");
      process.exit(1);
    }
  });

  // Safety net: force-exit if graceful shutdown hangs (e.g. a leaked
  // connection never releases).
  setTimeout(() => {
    logger.error("forced shutdown after timeout");
    process.exit(1);
  }, 10000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

module.exports = app;
