# Multi-stage build: run the full artifact pipeline, then serve the
# built React renderer as static files. SQLite is embedded, so there is
# no database service to orchestrate.
FROM node:22-slim AS build
WORKDIR /app

# Enable pnpm via corepack.
RUN corepack enable

# Install dependencies (better-sqlite3 needs build tools for its native
# addon if a prebuilt binary is unavailable).
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*

COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY packages ./packages
RUN pnpm install --frozen-lockfile

# Copy the rest and run the deterministic pipeline + build the renderer.
COPY . .
RUN pnpm pipeline && pnpm screenshots && pnpm --filter @design-playground/renderer build

# --- runtime: static file server for the demo app --------------------
FROM nginx:1.27-alpine AS demo
COPY --from=build /app/packages/renderer/dist /usr/share/nginx/html
EXPOSE 80
