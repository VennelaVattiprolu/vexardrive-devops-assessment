const express = require("express");
const { pool } = require("../db");
const { requireAuth, requireAdmin } = require("../middleware/auth");

const router = express.Router();

// Was: zero auth check - anyone could GET every driver's PII (name, phone).
// Fix: requires a valid JWT belonging to a driver with role = 'admin'.
router.get("/drivers", requireAuth, requireAdmin, async (req, res) => {
  const result = await pool.query("SELECT id, phone, name, role, created_at FROM drivers");
  res.json(result.rows);
});

module.exports = router;
