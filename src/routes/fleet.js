const express = require("express");
const { z } = require("zod");
const { pool } = require("../db");
const logger = require("../logger");

const router = express.Router();

// Was: lat/lng/speed/timestamp accepted as-is with no validation, so a
// malformed or malicious device payload would either 500 or silently insert
// garbage location data into fleet_pings.
const pingSchema = z.object({
  vehicleId: z.string().min(1).max(50),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  speed: z.number().min(0).max(400), // km/h, generous upper bound
  timestamp: z.string().datetime().or(z.number()),
});

router.post("/ping", async (req, res) => {
  const parsed = pingSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: "invalid ping payload", details: parsed.error.issues });
  }
  const { vehicleId, lat, lng, speed, timestamp } = parsed.data;

  try {
    await pool.query(
      `INSERT INTO fleet_pings (vehicle_id, lat, lng, speed, ts) VALUES ($1, $2, $3, $4, $5)`,
      [vehicleId, lat, lng, speed, new Date(timestamp)]
    );
    res.json({ status: "ok" });
  } catch (err) {
    logger.error({ err, vehicleId }, "fleet ping insert failed");
    res.status(500).json({ error: "insert failed" });
  }
});

module.exports = router;
