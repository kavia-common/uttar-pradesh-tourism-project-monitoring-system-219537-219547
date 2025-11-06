# UPSTDC Database (MongoDB)

This container provides the MongoDB datastore for the UPSTDC Project Monitoring System. It includes:
- JSON Schema validation for all collections
- Required indexes (unique, compound, 2dsphere)
- Seed data for roles, admin user, and sample projects
- Idempotent startup script to apply validators, indexes, and seed data

Environment variables
- MONGODB_URL: Full MongoDB connection string including credentials and authSource
- MONGODB_DB: Target database name used by the application and scripts

Startup
- Run upstdc_database/startup.sh. It will:
  - Ensure MongoDB service is running on the configured port (default 27017) and binds to 0.0.0.0 for previews
  - Readiness uses a TCP-only probe to 127.0.0.1:27017 (no mongosh or auth required)
  - Ensure admin user and app user exist
  - Apply collection JSON Schema validators from schema/collections.json
  - Apply indexes from schema/indexes.js
  - Seed base data from seed/seed_data.js
  - Readiness does NOT depend on validators/indexes/seed; these run after TCP is ready
  - Write connection helper: db_connection.txt
  - Write db_visualizer/mongodb.env with MONGODB_URL and MONGODB_DB

Preview (HTTP)
- A lightweight database visualizer Node app is provided under db_visualizer.
- It now listens on port 3020 and binds to 0.0.0.0 to work with preview routing.
- Ensure MongoDB_URL and MONGODB_DB are present in db_visualizer/mongodb.env (startup.sh writes this).
- Start the visualizer from the repo root or its directory:
  - cd upstdc_database/db_visualizer && npm install && npm run start
- Access:
  - Databases list: GET /api/databases
  - Mongo collections: GET /api/mongodb/tables
  - Sample data: GET /api/mongodb/tables/<collection>/data?limit=50
  - Status: GET /api/v1/db/status (returns { ok: true, details: { mongodb: { ok: true }}} on success)

Collections (summary)
- roles
  - Unique: name
  - Fields: name, description, permissions[]
- users
  - Unique: email
  - Fields: email, password_hash, full_name, roles[ObjectId], status, last_login_at
- projects
  - Unique: code
  - Geo: location (2dsphere)
  - Fields: code, title, status, dates, budget, address, district
- tenders
  - Unique compound: project_id + tender_no
- contractors
  - Unique: gstin
- funds
  - Fields: project_id, amount, source, released_date
- milestones
  - Fields: project_id, title, weightage, status, due_date
- progress_updates
  - Geo: location (2dsphere)
  - Fields: project_id, milestone_id, progress_percent, images[], reported_at, created_by
- inspections
  - Fields: project_id, inspected_by, inspected_at
- handovers
  - Fields: project_id, handover_date
- payments
  - Fields: project_id, contractor_id, amount, status, paid_at
- reports
  - Fields: project_id, type, generated_at, filters
- audit_logs
  - Fields: action, entity, entity_id, performed_by, performed_at
- sessions
  - Unique: refresh_token
  - Fields: user_id, refresh_token, ip, user_agent, expires_at, revoked_at

Indexes (key examples)
- users: { email: 1 } unique
- projects: { code: 1 } unique, { location: "2dsphere" }
- progress_updates: { location: "2dsphere" }, { project_id: 1, reported_at: -1 }
- sessions: { refresh_token: 1 } unique

Relationships (logical)
- users.roles -> roles._id
- tenders.project_id -> projects._id
- funds.project_id -> projects._id
- milestones.project_id -> projects._id
- progress_updates.project_id -> projects._id; milestone_id -> milestones._id
- inspections.project_id -> projects._id
- handovers.project_id -> projects._id
- payments.project_id -> projects._id; contractor_id -> contractors._id
- reports.project_id -> projects._id
- audit_logs.performed_by -> users._id

Operational notes
- Readiness: TCP-only check to 127.0.0.1:27017; no mongosh/auth is needed for readiness.
- mongod binding: server listens on 0.0.0.0:27017 to support preview routing.
- Initialization (validators, indexes, seed) runs after TCP readiness and does not block readiness.
- Scripts are idempotent; safe to re-run startup.sh.
- Do not hardcode secrets in code. Provide:
  - MONGODB_URL
  - MONGODB_DB
- Default dev credentials (override in production):
  - Admin user: appuser / dbuser123 (admin DB)
  - App user: appuser / dbuser123 (application DB)

Backups and restore
- backup_db.sh: Creates database_backup.archive for MongoDB
- restore_db.sh: Restores from database_backup.archive when present
