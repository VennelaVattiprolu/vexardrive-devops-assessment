const jwt = require("jsonwebtoken");
const config = require("../config");

// Verifies the bearer JWT and attaches the decoded driver to req.driver.
// Was: no auth check at all on /api/admin/drivers.
function requireAuth(req, res, next) {
  const header = req.headers.authorization || "";
  const [scheme, token] = header.split(" ");

  if (scheme !== "Bearer" || !token) {
    return res.status(401).json({ error: "missing or malformed authorization header" });
  }

  try {
    req.driver = jwt.verify(token, config.jwt.secret);
    return next();
  } catch (_err) {
    // Deliberately not logging the raw error here (could contain parts of
    // the malformed/expired token) - just the generic 401 the client sees.
    return res.status(401).json({ error: "invalid or expired token" });
  }
}

// Restricts a route to admin-role drivers. Requires requireAuth to have run first.
// This introduces a `role` column on `drivers` (see
// migrations/1754640000000_initial-schema.js) rather than a
// separate hardcoded admin credential, so access can be revoked/granted per-user.
function requireAdmin(req, res, next) {
  if (!req.driver || req.driver.role !== "admin") {
    return res.status(403).json({ error: "admin role required" });
  }
  return next();
}

module.exports = { requireAuth, requireAdmin };
