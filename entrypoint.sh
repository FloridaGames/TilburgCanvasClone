#!/usr/bin/env bash
# Canvas LMS entrypoint for Klutch
# - Waits for Postgres + Redis
# - Generates SECRET_KEY_BASE if missing
# - Runs initial DB setup or migrations
# - Precompiles assets (idempotent)
# - Hands off to CMD (puma)
set -euo pipefail

: "${DATABASE_HOST:?DATABASE_HOST is required}"
: "${DATABASE_PORT:=5432}"
: "${DATABASE_USER:?DATABASE_USER is required}"
: "${DATABASE_PASSWORD:?DATABASE_PASSWORD is required}"
: "${DATABASE_NAME:?DATABASE_NAME is required}"
: "${REDIS_URL:?REDIS_URL is required}"
: "${CANVAS_DOMAIN:?CANVAS_DOMAIN is required}"

if [ -z "${SECRET_KEY_BASE:-}" ]; then
  echo "[entrypoint] WARNING: SECRET_KEY_BASE not set — generating ephemeral one. Set it in Klutch env vars to persist sessions across restarts."
  export SECRET_KEY_BASE="$(openssl rand -hex 64)"
fi

if [ -z "${ENCRYPTION_KEY:-}" ]; then
  echo "[entrypoint] WARNING: ENCRYPTION_KEY not set — generating ephemeral one. Encrypted columns will be unreadable after restart!"
  export ENCRYPTION_KEY="$(openssl rand -hex 32)"
fi

echo "[entrypoint] Waiting for Postgres at ${DATABASE_HOST}:${DATABASE_PORT}..."
until PGPASSWORD="$DATABASE_PASSWORD" psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USER" -d "$DATABASE_NAME" -c '\q' 2>/dev/null; do
  sleep 2
done
echo "[entrypoint] Postgres is up."

echo "[entrypoint] Waiting for Redis..."
until redis-cli -u "$REDIS_URL" ping >/dev/null 2>&1; do
  sleep 2
done
echo "[entrypoint] Redis is up."

cd /app

# Detect first run by checking for the schema_migrations table
SCHEMA_EXISTS=$(PGPASSWORD="$DATABASE_PASSWORD" psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USER" -d "$DATABASE_NAME" -tAc "SELECT to_regclass('public.schema_migrations') IS NOT NULL;" || echo "f")

if [ "$SCHEMA_EXISTS" != "t" ]; then
  echo "[entrypoint] First run detected — running Canvas initial setup. This takes 20–40 minutes."
  bundle exec rake db:initial_setup
else
  echo "[entrypoint] Existing schema detected — running migrations."
  bundle exec rake db:migrate
fi

# Asset compilation (idempotent; skips if up-to-date)
if [ ! -f /app/public/assets/.compiled ]; then
  echo "[entrypoint] Compiling assets..."
  bundle exec rake canvas:compile_assets
  touch /app/public/assets/.compiled
fi

echo "[entrypoint] Starting Canvas: $*"
exec "$@"
