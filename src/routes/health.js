const express = require("express");
const { healthCheck } = require("../db");
const logger = require("../logger");

const router = express.Router();

// Liveness: process is up and able to serve requests at all. Should NOT
// depend on the database - if it did, a DB blip would cause the orchestrator
// to kill and restart healthy app instances too, worsening an outage.
router.get("/healthz", (req, res) => {
  res.status(200).json({ status: "ok" });
});

// Readiness: process is up AND able to serve real traffic (DB reachable).
// Used by the orchestrator to decide whether to route traffic to this
// instance, and by deploy pipelines to gate rollout.
router.get("/readyz", async (req, res) => {
  try {
    await healthCheck();
    res.status(200).json({ status: "ready" });
  } catch (err) {
    logger.error({ err }, "readiness check failed: database unreachable");
    res.status(503).json({ status: "not ready", reason: "database unreachable" });
  }
});

module.exports = router;
