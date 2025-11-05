#!/bin/bash

# MongoDB startup and initialization script for UPSTDC PMS
# Applies JSON schema validation, indexes, and seed data idempotently.

# ENV with defaults (can be overridden by .env or environment)
DB_NAME="${MONGODB_DB:-myapp}"
DB_USER="${MONGODB_ADMIN_USER:-appuser}"
DB_PASSWORD="${MONGODB_ADMIN_PASSWORD:-dbuser123}"
DB_PORT="${MONGODB_PORT:-5000}"

echo "=== UPSTDC MongoDB setup start ==="
echo "Target DB: ${DB_NAME} on port ${DB_PORT}"

# If MongoDB already running on desired port, skip starting but proceed to schema/index/seed
if mongosh --port ${DB_PORT} --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
  echo "MongoDB is already running on port ${DB_PORT}"
else
  # If mongod is running on another port, stop it (best effort)
  if pgrep -x mongod > /dev/null; then
    echo "Detected mongod running on different port, attempting to stop..."
    sudo pkill -x mongod || true
    sleep 2
  fi

  # Clean up sockets
  sudo rm -f /tmp/mongodb-*.sock 2>/dev/null

  echo "Starting MongoDB server on port ${DB_PORT}..."
  nohup sudo mongod --dbpath /var/lib/mongodb --port ${DB_PORT} --bind_ip 0.0.0.0 --unixSocketPrefix /var/run/mongodb > /var/lib/mongodb/mongod.log 2>&1 &
  echo "Waiting for MongoDB to start..."
  for i in {1..20}; do
    if mongosh --port ${DB_PORT} --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
      echo "MongoDB is ready!"
      break
    fi
    sleep 1
  done
fi

# Create admin and app user idempotently
echo "Ensuring admin and app users exist..."
mongosh --port ${DB_PORT} << 'EOF'
const adminUser = Deno ? null : null; // placeholder to keep syntax highlighters calm
EOF

mongosh --port ${DB_PORT} << EOF
use admin
if (db.getUser("${DB_USER}") == null) {
  db.createUser({
    user: "${DB_USER}",
    pwd: "${DB_PASSWORD}",
    roles: [
      { role: "userAdminAnyDatabase", db: "admin" },
      { role: "readWriteAnyDatabase", db: "admin" }
    ]
  });
  print("✓ Admin user created");
} else {
  print("• Admin user exists");
}

use ${DB_NAME}
if (db.getUser("appuser") == null) {
  db.createUser({
    user: "appuser",
    pwd: "${DB_PASSWORD}",
    roles: [ { role: "readWrite", db: "${DB_NAME}" } ]
  });
  print("✓ App user created");
} else {
  print("• App user exists");
}
EOF

# Apply JSON Schema validations for collections
echo "Applying collection validators (JSON Schema)..."
mongosh --port ${DB_PORT} ${DB_NAME} << 'EOF'
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

const spec = JSON.parse(cat("schema/collections.json"));
const entries = Object.entries(spec.collections || {});
for (const [name, def] of entries) {
  applyValidator(name, def.validator, def.options || {});
}
print("Validators applied");
EOF

# Apply indexes
echo "Applying indexes..."
mongosh --port ${DB_PORT} ${DB_NAME} schema/indexes.js

# Seed data
echo "Seeding data..."
mongosh --port ${DB_PORT} ${DB_NAME} seed/seed_data.js

# Output connection helpers
echo "mongosh mongodb://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}?authSource=admin" > db_connection.txt
cat > db_visualizer/mongodb.env << EOF
export MONGODB_URL="mongodb://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/?authSource=admin"
export MONGODB_DB="${DB_NAME}"
EOF

echo "Connection string saved to db_connection.txt"
echo "Environment variables saved to db_visualizer/mongodb.env"

echo "=== UPSTDC MongoDB setup complete ==="
echo "DB: ${DB_NAME} | Port: ${DB_PORT}"
echo "Admin user: ${DB_USER} / ${DB_PASSWORD}"
echo "App user: appuser / ${DB_PASSWORD}"
echo "Use: source db_visualizer/mongodb.env && curl http://localhost:3000/api/mongodb/tables"