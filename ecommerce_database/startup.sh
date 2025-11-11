#!/bin/bash
set -euo pipefail

# Minimal PostgreSQL startup script with robust readiness checks.
# Internal Postgres will listen on standard port 5432 and all interfaces.
# External port mapping (e.g., 3020->5432) is handled by the platform.

DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"

# Internal Postgres port inside the container
INTERNAL_PG_PORT="5432"
export PGPORT="${INTERNAL_PG_PORT}"

echo "[startup] Starting PostgreSQL setup..."

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ | head -1 || true)
if [ -z "${PG_VERSION}" ]; then
  echo "[startup][error] PostgreSQL binaries not found in /usr/lib/postgresql"
  exit 1
fi
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "[startup] Found PostgreSQL version: ${PG_VERSION}"
echo "[startup] Internal port: ${INTERNAL_PG_PORT}"

# Helper to check readiness
wait_for_ready() {
  local retries=${1:-20}
  local delay=${2:-2}
  local i=1
  while [ $i -le $retries ]; do
    if sudo -u postgres "${PG_BIN}/pg_isready" -h 127.0.0.1 -p "${INTERNAL_PG_PORT}" > /dev/null 2>&1; then
      echo "[startup] PostgreSQL is ready (attempt ${i}/${retries})"
      return 0
    fi
    echo "[startup] Waiting for PostgreSQL to be ready... (${i}/${retries})"
    sleep "${delay}"
    i=$((i+1))
  done
  return 1
}

# If already ready, short-circuit
if sudo -u postgres "${PG_BIN}/pg_isready" -h 127.0.0.1 -p "${INTERNAL_PG_PORT}" > /dev/null 2>&1; then
  echo "[startup] PostgreSQL is already running on port ${INTERNAL_PG_PORT}"
  echo "psql -h 127.0.0.1 -U ${DB_USER} -d ${DB_NAME} -p ${INTERNAL_PG_PORT}"
  echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@127.0.0.1:${INTERNAL_PG_PORT}/${DB_NAME}" > db_connection.txt
  echo "[startup] Existing instance detected. Exiting."
  exit 0
fi

# Also check for existing postgres process with matching port
if pgrep -f "postgres.*-p ${INTERNAL_PG_PORT}" > /dev/null 2>&1; then
  echo "[startup] Found existing PostgreSQL process on port ${INTERNAL_PG_PORT}, verifying..."
  if sudo -u postgres "${PG_BIN}/psql" -h 127.0.0.1 -p "${INTERNAL_PG_PORT}" -d postgres -c '\q' >/dev/null 2>&1; then
    echo "[startup] Existing PostgreSQL instance is responsive."
    echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@127.0.0.1:${INTERNAL_PG_PORT}/${DB_NAME}" > db_connection.txt
    exit 0
  fi
fi

# Initialize PostgreSQL data directory if it doesn't exist
if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
  echo "[startup] Initializing PostgreSQL data directory..."
  sudo -u postgres "${PG_BIN}/initdb" -D /var/lib/postgresql/data
fi

# Start PostgreSQL server in background with explicit port and listen_addresses
echo "[startup] Starting PostgreSQL server on 0.0.0.0:${INTERNAL_PG_PORT} ..."
sudo -u postgres "${PG_BIN}/postgres" \
  -D /var/lib/postgresql/data \
  -p "${INTERNAL_PG_PORT}" \
  -c listen_addresses='*' &

# Wait for readiness
if ! wait_for_ready 30 2; then
  echo "[startup][error] PostgreSQL did not become ready on 127.0.0.1:${INTERNAL_PG_PORT} within timeout."
  # Try to print last few lines of server log if available
  if [ -f "/var/lib/postgresql/data/log/postgresql-%Y-%m-%d_%H%M%S.log" ]; then
    echo "[startup] Recent PostgreSQL logs:"
    tail -n 100 /var/lib/postgresql/data/log/postgresql-*.log || true
  fi
  exit 1
fi

# Create database (idempotent)
echo "[startup] Ensuring database (${DB_NAME}) exists..."
if ! sudo -u postgres "${PG_BIN}/psql" -h 127.0.0.1 -p "${INTERNAL_PG_PORT}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres "${PG_BIN}/createdb" -h 127.0.0.1 -p "${INTERNAL_PG_PORT}" "${DB_NAME}"
else
  echo "[startup] Database ${DB_NAME} already exists."
fi

# Create/ensure user and permissions
echo "[startup] Ensuring user (${DB_USER}) and permissions..."
sudo -u postgres "${PG_BIN}/psql" -h 127.0.0.1 -p "${INTERNAL_PG_PORT}" -d postgres << EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

# Schema-level grants
sudo -u postgres "${PG_BIN}/psql" -h 127.0.0.1 -p "${INTERNAL_PG_PORT}" -d "${DB_NAME}" << EOF
GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};

-- Show current permissions for debugging
\\dn+ public
EOF

# Save connection command to a file (internal port)
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@127.0.0.1:${INTERNAL_PG_PORT}/${DB_NAME}" > db_connection.txt
echo "[startup] Connection string saved to db_connection.txt"

# Save environment variables for optional local viewer (internal port)
cat > db_visualizer/postgres.env << EOF
export POSTGRES_URL="postgresql://localhost:${INTERNAL_PG_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${INTERNAL_PG_PORT}"
EOF

echo "[startup] PostgreSQL setup complete!"
echo "[startup] Database: ${DB_NAME}"
echo "[startup] User: ${DB_USER}"
echo "[startup] Internal Port: ${INTERNAL_PG_PORT}"
echo ""
echo "[startup] Optional local viewer (not started here):"
echo "  cd db_visualizer && source postgres.env && npm install && npm run start"
echo ""
echo "[startup] To connect from inside container:"
echo "  psql -h 127.0.0.1 -U ${DB_USER} -d ${DB_NAME} -p ${INTERNAL_PG_PORT}"
echo "  $(cat db_connection.txt)"
