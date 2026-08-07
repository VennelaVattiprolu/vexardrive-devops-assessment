-- VexarDrive Fleet Ping Service - schema
--
-- Changes from the original starter schema (see docs/REPORT.md):
--   1. Added `role` to drivers, so /api/admin/drivers can require an actual
--      admin-role driver instead of having no auth check at all.
--   2. Added `otp_codes` table to support real OTP verification (was
--      previously not checked at all).
--   3. Added an index on fleet_pings(vehicle_id, ts) - this is the
--      highest-write-volume table in the system, and the obvious query
--      pattern (recent pings for a given vehicle) was doing a full scan.

CREATE TABLE IF NOT EXISTS drivers (
  id SERIAL PRIMARY KEY,
  phone VARCHAR(15) UNIQUE NOT NULL,
  name VARCHAR(100),
  role VARCHAR(20) NOT NULL DEFAULT 'driver' CHECK (role IN ('driver', 'admin')),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS otp_codes (
  phone VARCHAR(15) PRIMARY KEY REFERENCES drivers(phone) ON DELETE CASCADE,
  otp_hash TEXT NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  attempts INT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS fleet_pings (
  id SERIAL PRIMARY KEY,
  vehicle_id VARCHAR(50) NOT NULL,
  lat DECIMAL(9,6),
  lng DECIMAL(9,6),
  speed DECIMAL(5,2),
  ts TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Supports the primary access pattern: "recent pings for vehicle X".
-- DESC on ts since dashboards/queries almost always want the most recent
-- pings first (e.g. current vehicle position).
CREATE INDEX IF NOT EXISTS idx_fleet_pings_vehicle_ts
  ON fleet_pings (vehicle_id, ts DESC);
