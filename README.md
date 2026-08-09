# Fleet Ping Service — VexarDrive DevOps Assessment

Node.js/Express backend receiving vehicle location pings and handling
driver authentication, for VexarDrive's fleet management platform.

This repo is the completed submission for the VexarDrive DevOps & Cloud
Infrastructure Engineer technical assessment. **The full write-up —
what was found, what changed, why, and what was deliberately left
unchanged — is in [`docs/REPORT.md`](docs/REPORT.md).** This README
covers only how to actually run the thing.

## Technology stack

- Node.js 20 / Express
- PostgreSQL (via a connection pool — see `src/db.js`)
- Docker (multi-stage, non-root, see `Dockerfile`)
- Terraform for Azure (see `infra/`)
- GitHub Actions for CI/CD (see `.github/workflows/deploy.yml`)

## API endpoints

- `POST /api/auth/request-otp`, `POST /api/auth/login` — driver auth
- `POST /api/fleet/ping` — vehicle location ping ingestion
- `GET /api/admin/drivers` — admin-only driver list
- `GET /healthz`, `GET /readyz` — liveness/readiness

See `src/routes/` for exact request/response shapes.

## Local setup

**Fastest path — Docker Compose** (recommended, matches production closer):

```bash
cp .env.example .env   # edit values as needed
docker compose up --build
npm run migrate:up      # DATABASE_URL should point at localhost:5432 for this
```

**Without Docker:**

```bash
npm install
cp .env.example .env   # point DB_HOST at your local Postgres
npm run migrate:up
npm start
```

## Database

Schema changes are tracked migrations in `migrations/` (via
`node-pg-migrate`), not a hand-applied `.sql` file — see
`docs/REPORT.md`, Deliverable 5, for why.

```bash
npm run migrate:up      # apply all pending migrations
npm run migrate:down    # roll back the most recent migration
npm run migrate:create some-change-name   # scaffold a new migration
```

## Testing and linting

```bash
npm test    # see docs/REPORT.md, Deliverable 1, Known Limitations
npm run lint
```

## Docker

```bash
docker build -t vexar-fleet-ping .
docker compose up --build   # app + local Postgres together
```

## Infrastructure (Azure)

Terraform in `infra/` — see `infra/README.md` for how to run it,
environment separation (`infra/environments/*.tfvars`), and how to wire
the deployed identity into GitHub Actions.

## CI/CD

`.github/workflows/deploy.yml` — test → build & scan → push → deploy →
verify → rollback-on-failure. See `docs/REPORT.md`, Deliverable 4, and
`infra/README.md` for the GitHub Environment setup this depends on.

## Repository structure

```text
.
├── .github/workflows/deploy.yml   # CI/CD pipeline
├── docs/
│   └── REPORT.md                  # full technical report - start here
├── infra/                         # Terraform (Azure)
│   ├── environments/*.tfvars
│   └── README.md
├── migrations/                    # tracked schema changes
├── src/
│   ├── config.js
│   ├── db.js
│   ├── logger.js
│   ├── middleware/
│   └── routes/
├── server.js
├── Dockerfile
├── docker-compose.yml
├── eslint.config.js
├── package.json
└── README.md
```

## Assessment context

Submitted for the VexarDrive Technologies DevOps & Cloud Infrastructure
Engineer Technical Assessment. AI tool usage is disclosed in
`docs/REPORT.md`.
