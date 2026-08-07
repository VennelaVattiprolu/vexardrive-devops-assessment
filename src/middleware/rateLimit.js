const rateLimit = require("express-rate-limit");

// Fixing the auth bypass alone isn't enough - without this, an attacker could
// brute-force a 6-digit OTP (1e6 possibilities) against a real verification
// check. Kept generous enough not to lock out real drivers on typos.
const authRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "too many attempts, please try again later" },
});

module.exports = { authRateLimit };
