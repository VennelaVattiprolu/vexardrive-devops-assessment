const express = require("express");
const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");

const { pool } = require("../db");
const config = require("../config");
const logger = require("../logger");
const { authRateLimit } = require("../middleware/rateLimit");

const router = express.Router();

function generateOtp() {
  // 6-digit numeric OTP. crypto.randomInt is cryptographically strong,
  // unlike Math.random().
  return crypto.randomInt(100000, 999999).toString();
}

// --- POST /api/auth/request-otp -----------------------------------------
// Issues a one-time code for a known phone number. Was not present in the
// original code (login accepted any otp value) - added so the fix is a real,
// demoable end-to-end flow rather than just deleting the vulnerable check.
router.post("/request-otp", authRateLimit, async (req, res) => {
  const { phone } = req.body;

  if (!phone || typeof phone !== "string" || !/^\+?[0-9]{7,15}$/.test(phone)) {
    return res.status(400).json({ error: "valid phone number required" });
  }

  const driverResult = await pool.query("SELECT id FROM drivers WHERE phone = $1", [phone]);
  if (driverResult.rows.length === 0) {
    // Same response whether or not the phone exists, to avoid leaking which
    // numbers are registered drivers.
    return res.json({ status: "ok" });
  }

  const otp = generateOtp();
  const otpHash = await bcrypt.hash(otp, 10);
  const expiresAt = new Date(Date.now() + config.otp.ttlSeconds * 1000);

  await pool.query(
    `INSERT INTO otp_codes (phone, otp_hash, expires_at, attempts)
     VALUES ($1, $2, $3, 0)
     ON CONFLICT (phone) DO UPDATE SET otp_hash = $2, expires_at = $3, attempts = 0`,
    [phone, otpHash, expiresAt]
  );

  if (config.otp.devLogOtp) {
    // Dev/staging only - stands in for the SMS provider integration.
    logger.info({ phone }, `[DEV ONLY] OTP for ${phone}: ${otp}`);
  } else {
    // Production integration point: SMS provider (Twilio / Azure
    // Communication Services) call goes here. Intentionally out of scope.
    logger.info({ phone }, "OTP issued, dispatch to SMS provider");
  }

  res.json({ status: "ok" });
});

// --- POST /api/auth/login -------------------------------------------------
// Was: destructured `otp` from the body and never checked it against
// anything - any phone + any otp value returned a valid 30-day token.
// Fix: verify against the hashed, time-limited OTP issued above, with an
// attempt limit, and fail closed on every branch.
router.post("/login", authRateLimit, async (req, res) => {
  const { phone, otp } = req.body;

  if (!phone || !otp) {
    return res.status(400).json({ error: "phone and otp are required" });
  }

  // Parameterized query - was string-interpolated (`WHERE phone = '${phone}'`),
  // a direct SQL injection vector.
  const driverResult = await pool.query(
    "SELECT id, phone, name, role FROM drivers WHERE phone = $1",
    [phone]
  );
  if (driverResult.rows.length === 0) {
    return res.status(401).json({ error: "invalid phone or otp" });
  }
  const driver = driverResult.rows[0];

  const otpResult = await pool.query("SELECT * FROM otp_codes WHERE phone = $1", [phone]);
  if (otpResult.rows.length === 0) {
    return res.status(401).json({ error: "invalid phone or otp" });
  }
  const otpRecord = otpResult.rows[0];

  if (new Date(otpRecord.expires_at) < new Date()) {
    await pool.query("DELETE FROM otp_codes WHERE phone = $1", [phone]);
    return res.status(401).json({ error: "otp expired, request a new one" });
  }

  if (otpRecord.attempts >= config.otp.maxAttempts) {
    await pool.query("DELETE FROM otp_codes WHERE phone = $1", [phone]);
    return res.status(429).json({ error: "too many failed attempts, request a new otp" });
  }

  const isValid = await bcrypt.compare(otp, otpRecord.otp_hash);
  if (!isValid) {
    await pool.query("UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = $1", [phone]);
    return res.status(401).json({ error: "invalid phone or otp" });
  }

  // Success - burn the OTP so it can't be replayed.
  await pool.query("DELETE FROM otp_codes WHERE phone = $1", [phone]);

  const token = jwt.sign(
    { driverId: driver.id, phone: driver.phone, role: driver.role },
    config.jwt.secret,
    { expiresIn: config.jwt.expiresIn }
  );

  res.json({ token });
});

module.exports = router;
