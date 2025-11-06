#!/bin/bash

# MongoDB startup and initialization script for UPSTDC PMS
# Applies JSON schema validation, indexes, and seed data idempotently.
set -euo pipefail

# ENV with defaults (can be overridden by .env or environment)
DB_NAME="${MONGODB_DB:-myapp}"
DB_USER="${MONGODB_ADMIN_USER:-appuser}"
DB_PASSWORD="${MONGODB_ADMIN_PASSWORD:-dbuser123}"
DB_PORT="${MONGODB_PORT:-3020}"

echo "=== UPSTDC MongoDB setup start ==="
echo "Target DB: ${DB_NAME} on port ${DB_PORT}"

# Ensure data/log directories and permissions
DBPATH="${MONGODB_DBPATH:-/var/lib/mongodb}"
LOGDIR="${MONGODB_LOGDIR:-/var/lib/mongodb}"
SOCKDIR="${MONGODB_SOCKDIR:-/var/run/mongodb}"

sudo mkdir -p "${DBPATH}" "${LOGDIR}" "${SOCKDIR}" || true
sudo chown -R "$(id -u)":"$(id -g)" "${DBPATH}" "${LOGDIR}" "${SOCKDIR}" || true
sudo chmod 700 "${DBPATH}" || true
touch "${LOGDIR}/mongod.log" || true

# Helper: wait for mongod readiness with backoff
wait_for_mongo() {
  local attempts=${1:-60}
  local delay=${2:-1}
  local i=1
  while [ $i -le $attempts ]; do
    if mongosh --host 127.0.0.1 --port "${DB_PORT}" --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
      echo "MongoDB is ready (127.0.0.1:${DB_PORT})"
      return 0
    fi
    sleep "$delay"
    i=$((i+1))
  done
  return 1
}

# If MongoDB already running on desired port, skip starting but proceed to schema/index/seed
if mongosh --host 127.0.0.1 --port "${DB_PORT}" --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
  echo "MongoDB is already running on port ${DB_PORT}"
else
  # If mongod is running on another port, stop it (best effort)
  if pgrep -x mongod > /dev/null; then
    echo "Detected mongod running on a different configuration, attempting to stop..."
    sudo pkill -x mongod || true
    sleep 2
  fi

  # Clean up sockets
  sudo rm -f /tmp/mongodb-*.sock 2>/dev/null || true

  echo "Starting MongoDB server on port ${DB_PORT} and bind to 0.0.0.0..."
  nohup sudo mongod \
    --dbpath "${DBPATH}" \
    --port "${DB_PORT}" \
    --bind_ip 0.0.0.0 \
    --unixSocketPrefix "${SOCKDIR}" \
    > "${LOGDIR}/mongod.log" 2>&1 &
  
  echo "Waiting for MongoDB to start (healthcheck via mongosh ping)..."
  if ! wait_for_mongo 60 1; then
    echo "ERROR: MongoDB did not become ready on 127.0.0.1:${DB_PORT}"
    echo "Last 100 log lines:"
    tail -n 100 "${LOGDIR}/mongod.log" || true
    exit 1
  fi
fi

# Healthcheck (non-fatal here): demonstrate readiness for CI/preview
if mongosh --host 127.0.0.1 --port "${DB_PORT}" --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
  echo "Healthcheck OK: mongosh ping succeeded on 127.0.0.1:${DB_PORT}"
else
  echo "WARN: Healthcheck ping failed unexpectedly (will continue due to idempotent init)."
fi

# Create admin and app user idempotently (retry-safe)
echo "Ensuring admin and app users exist..."
mongosh --host 127.0.0.1 --port "${DB_PORT}" << 'EOF'
const adminUser = Deno ? null : null; // placeholder to keep syntax highlighters calm
EOF

mongosh --host 127.0.0.1 --port "${DB_PORT}" << EOF
use admin
if (db.getUser("${DB_USER}") == null) {
  try {
    db.createUser({
      user: "${DB_USER}",
      pwd: "${DB_PASSWORD}",
      roles: [
        { role: "userAdminAnyDatabase", db: "admin" },
        { role: "readWriteAnyDatabase", db: "admin" }
      ]
    });
    print("✓ Admin user created");
  } catch (e) { print("• Admin user create skipped: " + e.message); }
} else {
  print("• Admin user exists");
}

use ${DB_NAME}
if (db.getUser("appuser") == null) {
  try {
    db.createUser({
      user: "appuser",
      pwd: "${DB_PASSWORD}",
      roles: [ { role: "readWrite", db: "${DB_NAME}" } ]
    });
    print("✓ App user created");
  } catch (e) { print("• App user create skipped: " + e.message); }
} else {
  print("• App user exists");
}
EOF

# Apply JSON Schema validations for collections (idempotent, non-fatal)
echo "Applying collection validators (JSON Schema)..."
mongosh --host 127.0.0.1 --port "${DB_PORT}" ${DB_NAME} << 'EOF'
function applyValidator(collName, validator, options = {}) {
  try {
    const cmd = { collMod: collName, validator: { $jsonSchema: validator }, validationLevel: (options.validatorLevel || "moderate") };
    // If collection doesn't exist yet, create with validator
    const exists = db.getCollectionNames().includes(collName);
    if (!exists) {
      db.createCollection(collName, { validator: { $jsonSchema: validator }, validationLevel: (options.validatorLevel || "moderate") });
      print("✓ Created collection with validator: " + collName);
    } else {
      db.runCommand(cmd);
      print("✓ Updated validator for: " + collName);
    }
  } catch (e) {
    print("✗ Validator error for " + collName + ": " + e.message);
  }
}

const specRaw = cat("schema/collections.json");
let spec = {};
try {
  spec = JSON.parse(specRaw);
} catch (e) {
  print("✗ Failed to parse collections.json: " + e.message);
  spec = {};
}

const collSpec = (spec && typeof spec === 'object' && spec.collections && typeof spec.collections === 'object') ? spec.collections : {};
for (const [name, def] of Object.entries(collSpec)) {
  if (!def || !def.validator) {
    print("• Skipping collection without validator spec: " + name);
    continue;
  }
  applyValidator(name, def.validator, def.options || {});
}
print("Validators applied");
EOF

# Apply indexes (idempotent)
echo "Applying indexes..."
mongosh --host 127.0.0.1 --port "${DB_PORT}" ${DB_NAME} schema/indexes.js || echo "WARN: Index application encountered errors but will continue"

# Seed data (idempotent)
echo "Seeding data..."
mongosh --host 127.0.0.1 --port "${DB_PORT}" ${DB_NAME} seed/seed_data.js || echo "WARN: Seed script encountered errors but will continue"

# Output connection helpers (use 127.0.0.1 for healthchecks)
echo "mongosh mongodb://${DB_USER}:${DB_PASSWORD}@127.0.0.1:${DB_PORT}/${DB_NAME}?authSource=admin" > db_connection.txt
cat > db_visualizer/mongodb.env << EOF
export MONGODB_URL="mongodb://${DB_USER}:${DB_PASSWORD}@127.0.0.1:${DB_PORT}/?authSource=admin"
export MONGODB_DB="${DB_NAME}"
EOF

echo "Connection string saved to db_connection.txt"
echo "Environment variables saved to db_visualizer/mongodb.env"

echo "=== UPSTDC MongoDB setup complete ==="
echo "DB: ${DB_NAME} | Port: ${DB_PORT}"
echo "Admin user: ${DB_USER} / ${DB_PASSWORD}"
echo "App user: appuser / ${DB_PASSWORD}"
echo "Healthcheck example: mongosh --host 127.0.0.1 --port ${DB_PORT} --eval \"db.adminCommand('ping')\""