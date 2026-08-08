# VexarDrive Fleet Ping Service — Technical Report

**Author:** Vennela Vattiprolu
**Assessment:** DevOps & Cloud Infrastructure Engineer, VexarDrive Technologies

This report documents the review, changes, and infrastructure design produced
for the assessment. Each deliverable is a section below. Within each section,
findings follow a consistent structure: **Found → Risk → Fix → Verified**, so
the reasoning behind every change is traceable, not just the diff.

---

## AI Tool Usage Disclosure

Claude (Anthropic) was used throughout this assessment for: reviewing the
starter repository and identifying issues, drafting code fixes, scaffolding
Infrastructure as Code, and drafting sections of this report. All code was
reviewed, run, and manually tested by me against a local PostgreSQL instance
before being accepted. Architectural decisions (e.g. Container Apps vs AKS,
OTP storage approach, network boundaries) were discussed and made jointly,
with the final call and understanding of trade-offs being mine.

---

## Deliverable 1: Application Review & Production Readiness

### Approach to prioritization

Issues are ordered by **risk = impact × likelihood**, not by where they
appear in the file:

- **Critical** — exploitable immediately, by anyone, with severe
  consequences (auth bypass, SQL injection, PII exposure, secrets in
  source). Fixed first: these are the difference between "insecure" and
  "should not be exposed to the internet at all."
- **High** — not directly exploitable by an outside attacker, but the
  service fails under realistic production conditions (connection
  exhaustion under fleet-scale ping volume, no graceful shutdown, no
  health checks for orchestration). Fixed second, since the JD's own
  concern about "bursty traffic" makes this directly relevant.
- **Medium** — operational hygiene (image size, build caching, CI gates).
  Important for maintainability and cost, but nothing breaks today
  without them. Addressed in Deliverables 2 and 4.

### Critical findings

**1. Authentication bypass in `POST /api/auth/login`**
- *Found:* the original handler destructured `otp` from the request body
  but never checked it against any stored value.
- *Risk:* any phone number with any OTP value — including an empty string
  — returned a valid, signed 30-day JWT. This is a complete authentication
  bypass for every driver account.
- *Fix:* implemented a real OTP flow — `POST /api/auth/request-otp` issues
  a cryptographically random 6-digit code, hashed with bcrypt and stored
  with a 5-minute expiry and an attempt counter in a new `otp_codes` table.
  `POST /api/auth/login` now verifies the submitted code against the hash,
  rejects expired/exceeded-attempt codes, and burns the code on success so
  it can't be replayed. bcrypt was chosen over a fast hash (e.g. SHA-256)
  even though the OTP is short-lived and low-entropy (6 digits): bcrypt's
  deliberate slowness is what makes brute-forcing the stored hash itself
  expensive, and the added cost is negligible here since login is a
  low-frequency, human-triggered action rather than a hot path like the
  ping endpoint. Codes are stored in Postgres rather than in-memory
  specifically because the app will run as multiple replicas behind a load
  balancer (Container Apps) — an in-memory store would only work if the
  same replica handled both the OTP request and the login, which isn't
  guaranteed.
- *Verified:* manually tested end-to-end against a local Postgres
  instance — correct OTP returns a token; wrong OTP returns 401; replaying
  a used OTP returns 401; a SQL-injection-style phone value is handled
  safely (401, not a crash or bypass).

**2. SQL injection in `POST /api/auth/login`**
- *Found:* the driver lookup built the query via string interpolation:
  `` `SELECT * FROM drivers WHERE phone = '${phone}'` ``.
- *Risk:* trivially exploitable — a crafted `phone` value could alter
  query logic, extract data, or bypass the lookup entirely.
- *Fix:* replaced with a parameterized query (`WHERE phone = $1`) using
  `pg`'s built-in parameter binding everywhere in the codebase, not just
  this one call site.
- *Verified:* submitted a `' OR 1=1--`-style payload as `phone`; it is
  treated as a literal string and the request correctly returns 401
  rather than matching all rows or erroring.

**3. Unauthenticated admin endpoint `GET /api/admin/drivers`**
- *Found:* no authentication or authorization check at all — any client
  could retrieve every driver's name and phone number.
- *Risk:* unauthenticated PII disclosure for the entire driver base.
- *Fix:* added `requireAuth` (verifies JWT) and `requireAdmin` (checks a
  new `role` column on `drivers`) middleware, applied to this route. A
  `role` column was added rather than a separate hardcoded admin
  credential, so admin access can be granted/revoked per-user through
  normal data changes instead of a shared secret.
- *Verified:* request without a token → 401. Request with a valid
  `driver`-role token → 403. Request with a valid `admin`-role token →
  200 with the driver list.

**4. Hardcoded production credentials in source**
- *Found:* the Postgres password, DB host, and JWT signing secret were
  literal strings committed to `server.js`.
- *Risk:* anyone with read access to the repository (or the built
  container image, since these were baked in at build time) had standing
  production database and token-signing access. If this were a real
  production system, it would already be compromised the moment the repo
  was shared for this assessment.
- *Fix:* introduced `src/config.js`, which reads all secrets and
  connection details from environment variables and **fails fast at
  startup** if any required variable is missing, rather than silently
  falling back to a default (which is the pattern that caused this issue
  in the first place). `.env.example` documents the required variables
  with placeholder values; a real `.env` is git-ignored and was never
  committed. In Azure, these values are supplied via Key Vault-backed
  Container Apps secrets (see Deliverable 6).
- *Verified:* confirmed the app refuses to start with a clear error if
  `JWT_SECRET` or any `DB_*` variable is unset; confirmed `.env` is not
  present in `git status` before any commit.

### High-priority findings

**5. New database connection per request**
- *Found:* `/api/fleet/ping` — the highest-frequency endpoint, hit
  continuously by every vehicle in the fleet — opened a new
  `pg.Client()` and tore it down on every single call.
- *Risk:* Postgres connection setup/teardown is comparatively expensive,
  and managed Postgres (Azure Database for PostgreSQL) has a hard
  `max_connections` ceiling per SKU. Under real fleet load this exhausts
  available connections quickly, and other endpoints (including login)
  would start failing.
- *Fix:* replaced with a single shared `pg.Pool` (`src/db.js`), sized via
  `DB_POOL_MAX` (default 10), reused across the process lifetime.
- *Verified:* confirmed the app serves multiple concurrent ping/login
  requests without opening new connections per request (pool behavior
  confirmed via Postgres's own connection count staying flat under
  repeated requests).

**6. No input validation on ping ingestion**
- *Found:* `lat`, `lng`, `speed`, `timestamp` were inserted as-is from the
  request body with no type or range checking.
- *Risk:* malformed device payloads either 500 or silently insert invalid
  location data (e.g. `lat: 999`) that would corrupt downstream fleet
  tracking/analytics.
- *Fix:* added a `zod` schema validating types and realistic ranges
  (lat -90..90, lng -180..180, speed 0..400 km/h) before any DB write.
  Chose a schema library over hand-written `if` checks because the
  validation rules will likely grow (more fields, nested payloads for
  batched pings) and a schema is self-documenting and easy to extend
  without the branching logic becoming hard to follow.
- *Verified:* a payload with `lat: 999` returns 400 with a clear error;
  a valid payload inserts correctly and is visible in `fleet_pings`.

**7. No health/readiness endpoints**
- *Found:* no way for a container orchestrator to know if the app is
  alive or able to serve traffic.
- *Risk:* Container Apps/AKS can't safely gate traffic routing, restarts,
  or rollout progression without these.
- *Fix:* added `GET /healthz` (liveness — process is up, no DB
  dependency, so a DB blip doesn't cause healthy instances to be killed)
  and `GET /readyz` (readiness — actually checks DB connectivity,
  returns 503 if unreachable).
- *Verified:* both return 200 under normal operation; `/readyz` was
  confirmed to return 503 when pointed at an unreachable DB host.

**8. No graceful shutdown**
- *Found:* no `SIGTERM`/`SIGINT` handling — the process died immediately
  on any deploy or scale-down signal.
- *Risk:* in-flight requests are killed mid-request on every single
  deployment, not just rare incidents. For a service ingesting continuous
  vehicle pings, this means periodic silent data loss.
- *Fix:* added a shutdown handler that stops accepting new connections,
  lets in-flight requests finish, closes the DB pool, then exits — with a
  10-second forced-exit safety net in case something hangs.
- *Verified:* sent `SIGTERM` to a running instance mid-request and
  confirmed the in-flight request completed before the process exited.

**9. No structured logging**
- *Found:* only `console.error` on failure paths, no structured output.
- *Risk:* unusable for real log aggregation, correlation, or alerting
  (Deliverable 7 depends on this).
- *Fix:* added `pino` structured JSON logging with automatic redaction of
  secrets/PII (`authorization` header, `password`, `otp`, `token` fields)
  so sensitive values can never leak into logs even by accident.

### Schema-level finding

**10. Missing index on `fleet_pings(vehicle_id, ts)`**
- *Found:* no index beyond the primary key on the highest-write-volume
  table in the system.
- *Risk:* the obvious and most common query pattern — recent pings for a
  given vehicle — requires a full table scan, and this degrades further
  as ping volume grows with fleet size.
- *Fix:* added `idx_fleet_pings_vehicle_ts` on `(vehicle_id, ts DESC)` —
  descending on `ts` since the common case is "most recent pings first"
  (e.g. current vehicle position).
- *Verified:* confirmed present via `\d fleet_pings` after applying the
  schema.

### What I chose not to change, and why

- **Real SMS delivery for OTPs** — out of scope for this assessment; no
  SMS provider account was available. The OTP is logged server-side in
  non-production environments as a stand-in, with a clearly marked
  integration point (`config.otp.devLogOtp`) for where a provider like
  Twilio or Azure Communication Services would plug in. Faking a "sent"
  response without a real send would be misleading rather than a genuine
  simplification.
- **Refresh tokens / short-lived access tokens** — I shortened the JWT
  lifetime from 30 days to 24 hours as a reasonable default, but did not
  implement a full refresh-token rotation flow. A 30-day token is a real
  risk (a leaked token stays valid for a month), but building refresh
  rotation correctly (storage, revocation, rotation-on-use) is a
  meaningfully larger change than this assessment's scope warrants for a
  single ping/login service. I'd revisit this with more time — see below.
- **Full automated test suite** — I verified behavior manually and
  systematically (documented above) rather than writing a full Jest/
  Supertest suite, given the time budget across all nine deliverables.
  `npm test` is wired up and ready for tests to be added; this is called
  out explicitly as a known limitation, not silently skipped.
- **Rewriting the data model beyond what the fixes required** — e.g. I
  did not restructure `fleet_pings` into a time-series-optimized layout
  (partitioning, TimescaleDB) since current scale doesn't justify the
  added operational complexity. This is addressed as a scaling
  consideration in Deliverable 5.

### What I'd address next with more time

1. Automated tests (unit tests for OTP/auth logic, integration tests for
   the full request flow) wired into the CI pipeline as a real gate,
   not just a placeholder script.
2. Refresh-token rotation instead of a single longer-lived access token.
3. Real SMS provider integration for OTP delivery.
4. Rate limiting keyed by phone number/IP more precisely (current
   limiter is a reasonable first pass but not tuned against real traffic
   patterns).
5. Partitioning or a time-series extension for `fleet_pings` once ping
   volume/fleet size crosses a threshold where the flat table + index
   stops being sufficient (see Deliverable 5).

---

## Deliverable 2: Containerization

### Findings

**1. Unpinned, oversized base image**
- *Found:* `FROM node:latest`.
- *Risk:* non-reproducible builds (the "latest" tag can silently point to
  a different image tomorrow), and `node:latest` is a full Debian-based
  image with build tools that are never needed at runtime — unnecessarily
  large and a wider attack surface.
- *Fix:* pinned to `node:20.17-alpine3.20`, and split the build into two
  stages (`build` installs dependencies via `npm ci`; `runtime` copies
  only `node_modules` and application code, discarding npm's cache and
  any build-time-only files).
- *Verified:* `docker images vexar-fleet-ping:test` → **207MB total image
  size, 49.3MB unique content** on top of the shared Alpine base layers.

**2. Broken layer caching**
- *Found:* `COPY . .` ran before `npm install`.
- *Risk:* every single code change (even a one-line edit to `server.js`)
  invalidated the dependency-install layer, forcing a full `npm install`
  on every build — slow CI, slow local iteration.
- *Fix:* `package.json`/`package-lock.json` are copied and `npm ci` run
  *before* the rest of the source is copied in, so the dependency layer
  is only rebuilt when dependencies actually change.
- *Verified:* observed in the build log — `[build 5/5] COPY . .` and the
  runtime `COPY --chown=appuser:appgroup src ./src` steps show `CACHED`
  on a rebuild after only touching application code, confirming the
  dependency-install layer was reused.

**3. Root user at runtime**
- *Found:* no `USER` directive — the container ran as root by default.
- *Risk:* if the app process were ever compromised (e.g. a future
  dependency vulnerability), root inside the container is a meaningfully
  worse starting position for an attacker than a scoped-down user.
- *Fix:* added a dedicated `appuser`/`appgroup`, and the runtime stage
  runs as that user.
- *Verified:* `docker run --rm vexar-fleet-ping:test node -e
  "console.log(process.getuid())"` → returned `100` (non-root), not `0`.

**4. No signal handling for graceful shutdown**
- *Found:* `node server.js` ran directly as PID 1 with no init process.
- *Risk:* Node.js run as PID 1 does not reliably forward/handle
  `SIGTERM` the way a normal process would, and doesn't reap zombie
  processes. This would have silently undermined the graceful-shutdown
  handler built in Deliverable 1 — `docker stop`/an orchestrator's
  scale-down signal might never actually reach the app's shutdown logic.
- *Fix:* added `tini` as the container's `ENTRYPOINT`, with `node
  server.js` as its child command.
- *Verified:* `docker run --rm vexar-fleet-ping:test ps aux` → PID 1 is
  `/sbin/tini -- node server.js`, confirming correct signal forwarding is
  in place.

**5. No container health check**
- *Found:* no `HEALTHCHECK` instruction.
- *Risk:* `docker ps` / an orchestrator has no way to know the container
  is actually able to serve traffic versus just having a running process.
- *Fix:* added a `HEALTHCHECK` calling the real `/healthz` endpoint from
  Deliverable 1.
- *Verified:* `docker compose ps` shows both the `app` and `db`
  containers as `healthy` after `docker compose up`.

**6. Unnecessary attack surface**
- *Found:* `EXPOSE 22` in the Dockerfile, despite no SSH server existing
  anywhere in the image.
- *Risk:* none directly (an unused `EXPOSE` doesn't open a port by
  itself), but it's misleading boilerplate that suggests the image
  supports SSH access when it doesn't, and needlessly widens the
  documented/declared surface.
- *Fix:* removed.

**7. `docker-compose.yml` (local dev) network/secret exposure**
- *Found:* Postgres was bound to `0.0.0.0:5432` (the entire host network,
  not just localhost), with a hardcoded password committed directly in
  the compose file.
- *Risk:* anyone else on the same network as a developer's machine could
  connect directly to the local Postgres instance. The hardcoded password
  is also a bad habit that risks leaking into a real environment via
  copy-paste.
- *Fix:* bound to `127.0.0.1:5432` only (kept accessible for local tools
  like `psql`/a DB GUI, but not the network), and credentials now come
  from a git-ignored local `.env` file (`.env.example` documents the
  required keys). Also added a healthcheck-gated `depends_on` so the app
  container doesn't race the database being ready on startup.
- *Verified:* `docker compose ps` shows the `db` service's port mapping
  as `127.0.0.1:5432->5432/tcp`, not `0.0.0.0`.

### Full end-to-end verification (against the actual built image)

Unlike Deliverable 1 (verified against a bare Node process locally), this
was verified against the **actual production Docker image**, run via
`docker compose`, on a separate machine from where the image was built —
closer to how it will really be deployed. Sequence performed:

1. `docker build` — succeeded, 207MB image.
2. Non-root user confirmed (`getuid()` → `100`).
3. `tini` confirmed as PID 1.
4. `docker compose up -d --build` — both `app` and `db` reached `healthy`
   status.
5. `GET /healthz` and `GET /readyz` — both `200`.
6. Full OTP flow against the containerized app + containerized Postgres:
   `request-otp` → OTP retrieved from container logs → `login` → valid
   JWT returned.
7. `GET /api/admin/drivers` with the admin token → `200`, correct data.
8. `GET /api/admin/drivers` with a `driver`-role token → `403`.
9. `GET /api/admin/drivers` with no token → `401`.
10. `POST /api/fleet/ping` with a valid payload → `200`.
11. `POST /api/fleet/ping` with `lat: 999` → `400`.

All behaved identically to the non-containerized verification in
Deliverable 1, confirming the containerization changes didn't alter
application behavior — only how it's packaged and run.

### What I chose not to change, and why

- **Distroless or scratch-based images** — Alpine was chosen as a
  reasonable middle ground between image size and having a usable shell
  for debugging (`docker exec` into a running container). A distroless
  image would be marginally smaller and reduce attack surface further,
  but makes troubleshooting a live container meaningfully harder. Given
  this is a small team's service (per the JD/company stage), the
  debuggability trade-off favors Alpine.
- **Docker Content Trust / image signing** — not configured for this
  assessment; relevant once images are pushed through a real registry
  pipeline (see Deliverable 4, CI/CD).

### What I'd address next with more time

1. Image vulnerability scanning wired into CI (Trivy/Grype) as an actual
   pipeline gate, not just a manual `docker build` — see Deliverable 4.
2. Resource limits (`mem_limit`/`cpus` in compose, and equivalent
   requests/limits in the Azure Container Apps definition) — not set
   here since local dev doesn't need them, but required for production.
3. Multi-arch build (`linux/amd64` + `linux/arm64`) if the team ever
   develops on Apple Silicon and wants local images to match prod
   architecture exactly.
