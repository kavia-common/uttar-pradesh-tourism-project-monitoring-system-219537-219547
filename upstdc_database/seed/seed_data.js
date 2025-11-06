/**
 * PUBLIC_INTERFACE
 * seedDatabase
 * Seeds base data for UPSTDC PMS: roles, admin user, and sample projects.
 * Idempotent: checks existence before inserting.
 */
async function seedDatabase(db) {
  // Roles
  const rolesColl = db.getCollection("roles");
  const now = new Date();

  const baseRoles = [
    {
      name: "admin",
      description: "System Administrator",
      permissions: [
        "users:read", "users:create", "users:update", "users:delete",
        "projects:*", "tenders:*", "contractors:*", "funds:*",
        "milestones:*", "progress:*", "inspections:*", "handovers:*",
        "payments:*", "reports:*", "audit:read", "settings:*"
      ],
      created_at: now, updated_at: now
    },
    {
      name: "project_manager",
      description: "Project Manager",
      permissions: [
        "projects:read", "projects:create", "projects:update",
        "milestones:*", "progress:*", "funds:*", "payments:*", "reports:*"
      ],
      created_at: now, updated_at: now
    },
    {
      name: "viewer",
      description: "Read-only access",
      permissions: ["projects:read", "tenders:read", "contractors:read", "reports:read"],
      created_at: now, updated_at: now
    }
  ];

  for (const role of baseRoles) {
    const exists = await rolesColl.findOne({ name: role.name });
    if (!exists) {
      await rolesColl.insertOne(role);
      print(`✓ Seeded role: ${role.name}`);
    } else {
      print(`• Role already exists: ${role.name}`);
    }
  }

  // Admin user
  const usersColl = db.getCollection("users");
  const adminRole = await rolesColl.findOne({ name: "admin" });

  // NOTE: password is a placeholder; backend should manage hashing during real user creation.
  // For seed, store a deterministic but clearly non-production hash-like string.
  const adminEmail = "admin@upstdc.local";
  const existingAdmin = await usersColl.findOne({ email: adminEmail });
  if (!existingAdmin) {
    const adminUser = {
      email: adminEmail,
      password_hash: "SEED_ONLY__CHANGE_IMMEDIATELY", // replace in production
      full_name: "System Administrator",
      phone: null,
      status: "active",
      roles: adminRole ? [adminRole._id] : [],
      created_at: now,
      updated_at: now,
      last_login_at: null
    };
    await usersColl.insertOne(adminUser);
    print("✓ Seeded admin user (email: admin@upstdc.local, password: set via backend)");
  } else {
    print("• Admin user already exists");
  }

  // Sample projects
  const projectsColl = db.getCollection("projects");
  const sampleProjects = [
    {
      code: "PMS-UP-001",
      title: "Restoration of Heritage Site - Agra",
      description: "Conservation and restoration of selected heritage structures.",
      status: "in_progress",
      start_date: new Date(now.getFullYear(), 0, 15),
      end_date: null,
      budget: 25000000,
      location: { type: "Point", coordinates: [77.987, 27.1767] },
      address: "Agra Fort, Agra, Uttar Pradesh",
      district: "Agra",
      created_by: null,
      created_at: now,
      updated_at: now
    },
    {
      code: "PMS-UP-002",
      title: "Tourist Amenities Upgrade - Varanasi Ghats",
      description: "Upgrade of sanitation and information facilities along ghats.",
      status: "planned",
      start_date: new Date(now.getFullYear(), 2, 1),
      end_date: null,
      budget: 18000000,
      location: { type: "Point", coordinates: [83.0, 25.3176] },
      address: "Dashashwamedh Ghat, Varanasi, Uttar Pradesh",
      district: "Varanasi",
      created_by: null,
      created_at: now,
      updated_at: now
    }
  ];

  for (const p of sampleProjects) {
    const exists = await projectsColl.findOne({ code: p.code });
    if (!exists) {
      await projectsColl.insertOne(p);
      print(`✓ Seeded project: ${p.code}`);
    } else {
      print(`• Project already exists: ${p.code}`);
    }
  }

  print("Seeding completed");
}

// Allow running directly via mongosh --file
if (typeof db !== "undefined") {
  (async () => { await seedDatabase(db); })();
}

// PUBLIC_INTERFACE
function getSeedDatabase() {
  /** Returns the seedDatabase function for programmatic use. */
  return seedDatabase;
}
