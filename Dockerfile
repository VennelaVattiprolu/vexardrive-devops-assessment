# --- Build stage -----------------------------------------------------------
# Was: FROM node:latest (unpinned -> non-reproducible builds, and a full
# ~1GB image shipping compilers/build tools that are never needed at runtime).
# Pinned to a specific LTS minor version on Alpine for a small, reproducible
# base. Using a separate build stage means npm's build-time footprint
# (dev deps if any, npm cache) never makes it into the image we actually ship.
FROM node:20.17-alpine3.20 AS build

WORKDIR /app

# Copy only the package manifests first. Was: `COPY . .` before `npm install`,
# which invalidates Docker's layer cache on every single code change (even a
# one-line change to server.js would force a full npm install on next build).
# With manifests copied first, the npm ci layer is only invalidated when
# dependencies actually change.
COPY package.json package-lock.json ./

# npm ci (not install) for reproducible installs from the lockfile exactly,
# and --omit=dev since this is a production image.
RUN npm ci --omit=dev

COPY . .

# --- Runtime stage -----------------------------------------------------------
FROM node:20.17-alpine3.20 AS runtime

# tini as PID 1: Node run directly as PID 1 does not correctly forward
# SIGTERM to itself in all cases and does not reap zombie processes. This
# matters concretely here because server.js implements graceful shutdown on
# SIGTERM (drain in-flight requests, close the DB pool) - without tini, that
# handler may never actually receive the signal from `docker stop` / the
# container orchestrator, silently defeating the fix.
RUN apk add --no-cache tini

# Non-root user - was: container ran as root by default. If the app process
# were ever compromised (e.g. via a future dependency vulnerability), running
# as root inside the container gives an attacker a meaningfully worse
# starting position than a scoped-down user.
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=build --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=build --chown=appuser:appgroup /app/package.json ./package.json
COPY --chown=appuser:appgroup server.js ./server.js
COPY --chown=appuser:appgroup src ./src

USER appuser

ENV NODE_ENV=production
EXPOSE 3000

# Was: no HEALTHCHECK at all. Wired to the real readiness endpoint added in
# Deliverable 1 - this is what lets `docker ps` and container orchestrators
# know the app is actually able to serve traffic, not just that the process
# is running.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/healthz', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
