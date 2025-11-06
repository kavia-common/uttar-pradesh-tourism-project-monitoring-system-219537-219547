/**
 * PUBLIC_INTERFACE
 * applyIndexes
 * This script creates required indexes for the UPSTDC PMS MongoDB database.
 * It is idempotent: repeated runs are safe. Intended to be run from mongosh --file.
 */
async function applyIndexes(db) {
  // Helper to create index safely
  async function ensureIndex(coll, keys, options = {}) {
    try {
      // In mongosh, prefer db.getCollection('name') then call createIndex
      const name = await db.getCollection(coll).createIndex(keys, { background: true, ...options });
      // mongosh doesn't define tojson; use printjson for objects and print for scalars
      print(`✓ Index ensured on ${coll}:`);
      printjson({ keys, options: { background: true, ...options }, name });
    } catch (e) {
      print(`✗ Failed to create index on ${coll}: ${e.message}`);
    }
  }

  // roles
  await ensureIndex("roles", { name: 1 }, { unique: true });

  // users
  await ensureIndex("users", { email: 1 }, { unique: true });
  await ensureIndex("users", { status: 1 });
  await ensureIndex("users", { roles: 1 });

  // projects
  await ensureIndex("projects", { code: 1 }, { unique: true });
  await ensureIndex("projects", { status: 1, start_date: -1 });
  await ensureIndex("projects", { district: 1, status: 1 });
  await ensureIndex("projects", { location: "2dsphere" });

  // tenders
  await ensureIndex("tenders", { project_id: 1, tender_no: 1 }, { unique: true });

  // contractors
  await ensureIndex("contractors", { gstin: 1 }, { unique: true });
  await ensureIndex("contractors", { name: 1 });

  // funds
  await ensureIndex("funds", { project_id: 1, released_date: -1 });

  // milestones
  await ensureIndex("milestones", { project_id: 1, status: 1 });
  await ensureIndex("milestones", { project_id: 1, due_date: 1 });

  // progress_updates
  await ensureIndex("progress_updates", { project_id: 1, reported_at: -1 });
  await ensureIndex("progress_updates", { milestone_id: 1, reported_at: -1 });
  await ensureIndex("progress_updates", { location: "2dsphere" });

  // inspections
  await ensureIndex("inspections", { project_id: 1, inspected_at: -1 });

  // handovers
  await ensureIndex("handovers", { project_id: 1, handover_date: -1 });

  // payments
  await ensureIndex("payments", { project_id: 1, contractor_id: 1, paid_at: -1 });

  // reports
  await ensureIndex("reports", { project_id: 1, generated_at: -1, type: 1 });

  // audit_logs
  await ensureIndex("audit_logs", { entity: 1, entity_id: 1, performed_at: -1 });

  // sessions
  await ensureIndex("sessions", { user_id: 1, created_at: -1 });
  await ensureIndex("sessions", { refresh_token: 1 }, { unique: true });

  print("Index application completed");
}

// Allow running directly via mongosh --file
if (typeof db !== "undefined") {
  // running inside mongosh context
  (async () => { await applyIndexes(db); })();
}

// PUBLIC_INTERFACE
function getApplyIndexes() {
  /** Returns the applyIndexes function for programmatic use. */
  return applyIndexes;
}
