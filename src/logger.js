// Structured JSON logging (was: bare console.error, unusable for real
// log aggregation/alerting - see Deliverable 7, Monitoring).
// pino is chosen over winston for its low overhead and default JSON output,
// which is what Azure Monitor / Log Analytics ingest cleanly.

const pino = require("pino");
const config = require("./config");

const logger = pino({
  level: process.env.LOG_LEVEL || (config.env === "production" ? "info" : "debug"),
  redact: {
    // Never let secrets or PII leak into logs, even accidentally via req/err objects.
    paths: ["req.headers.authorization", "*.password", "*.otp", "*.token"],
    censor: "[REDACTED]",
  },
  formatters: {
    level(label) {
      return { level: label };
    },
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});

module.exports = logger;
