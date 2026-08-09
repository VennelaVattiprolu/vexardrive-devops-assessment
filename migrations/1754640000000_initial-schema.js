/* eslint-disable */
// Was: schema.sql applied by hand, once, with no record of what version
// of the schema any given environment is actually running. This
// migration is the first tracked change - node-pg-migrate records which
// migrations have run in a `pgmigrations` table, so `npm run migrate up`
// is idempotent and safe to run repeatedly (in CI, on every deploy).

exports.up = (pgm) => {
  pgm.createTable("drivers", {
    id: "id",
    phone: { type: "varchar(15)", notNull: true, unique: true },
    name: { type: "varchar(100)" },
    role: {
      type: "varchar(20)",
      notNull: true,
      default: "driver",
      check: "role IN ('driver', 'admin')",
    },
    created_at: { type: "timestamp", default: pgm.func("now()") },
  });

  pgm.createTable("otp_codes", {
    phone: {
      type: "varchar(15)",
      primaryKey: true,
      references: "drivers(phone)",
      onDelete: "CASCADE",
    },
    otp_hash: { type: "text", notNull: true },
    expires_at: { type: "timestamp", notNull: true },
    attempts: { type: "int", notNull: true, default: 0 },
  });

  pgm.createTable("fleet_pings", {
    id: "id",
    vehicle_id: { type: "varchar(50)", notNull: true },
    lat: { type: "decimal(9,6)" },
    lng: { type: "decimal(9,6)" },
    speed: { type: "decimal(5,2)" },
    ts: { type: "timestamp" },
    created_at: { type: "timestamp", default: pgm.func("now()") },
  });

  // Supports the primary access pattern: "recent pings for vehicle X".
  // DESC on ts since dashboards/queries almost always want the most
  // recent pings first (e.g. current vehicle position).
  pgm.createIndex("fleet_pings", ["vehicle_id", { name: "ts", sort: "DESC" }], {
    name: "idx_fleet_pings_vehicle_ts",
  });
};

exports.down = (pgm) => {
  pgm.dropTable("fleet_pings");
  pgm.dropTable("otp_codes");
  pgm.dropTable("drivers");
};
