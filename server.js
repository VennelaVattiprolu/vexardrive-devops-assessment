// VexarDrive - Fleet Ping Service (minimal demo backend)
// NOTE: This is a deliberately trimmed-down module extracted from a larger monorepo
// for the purposes of this assessment. Treat it as inherited legacy code.

const express = require("express");
const { Client } = require("pg");
const jwt = require("jsonwebtoken");

const app = express();
app.use(express.json());

// --- DB connection ---------------------------------------------------
// Hardcoded credentials (intentional - do not "just" move to .env and stop there)
const DB_CONFIG = {
  host: "vexar-pg-prod.postgres.database.azure.com",
  port: 5432,
  user: "vexaradmin",
  password: "V3xar@2024!Prod",
  database: "vexar_fleet",
};

const JWT_SECRET = "vexar-super-secret-key-2024";

// --- Routes ------------------------------------------------------------

app.get("/", (req, res) => {
  res.send("VexarDrive Fleet Ping Service is running");
});

// Fleet vehicle ping ingestion - called very frequently by devices in the field
app.post("/api/fleet/ping", async (req, res) => {
  const { vehicleId, lat, lng, speed, timestamp } = req.body;

  // A brand new client connection is opened and torn down on every single request.
  const client = new Client(DB_CONFIG);
  try {
    await client.connect();
    await client.query(
      `INSERT INTO fleet_pings (vehicle_id, lat, lng, speed, ts) VALUES ($1, $2, $3, $4, $5)`,
      [vehicleId, lat, lng, speed, timestamp]
    );
    res.json({ status: "ok" });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "insert failed" });
  } finally {
    await client.end();
  }
});

// Driver login
app.post("/api/auth/login", async (req, res) => {
  const { phone, otp } = req.body;

  const client = new Client(DB_CONFIG);
  await client.connect();
  const result = await client.query(
    `SELECT * FROM drivers WHERE phone = '${phone}'` // string-built query, left as-is intentionally
  );
  await client.end();

  if (result.rows.length === 0) {
    return res.status(401).json({ error: "not found" });
  }

  const token = jwt.sign({ driverId: result.rows[0].id }, JWT_SECRET, {
    expiresIn: "30d",
  });
  res.json({ token });
});

// Admin endpoint to fetch all driver data - no auth check
app.get("/api/admin/drivers", async (req, res) => {
  const client = new Client(DB_CONFIG);
  await client.connect();
  const result = await client.query(`SELECT * FROM drivers`);
  await client.end();
  res.json(result.rows);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});

module.exports = app;
