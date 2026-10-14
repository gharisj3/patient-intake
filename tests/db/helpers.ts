import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { btree_gist } from "@electric-sql/pglite/contrib/btree_gist";

const root = process.cwd();

// Minimal stand-in for the parts of Supabase the migrations rely on.
const SUPABASE_SHIM = `
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;
  create schema auth;
  create table auth.users (id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
`;

export async function createDb(opts: { seed?: boolean } = {}): Promise<PGlite> {
  const db = new PGlite({ extensions: { btree_gist } });
  await db.exec(SUPABASE_SHIM);
  const dir = join(root, "supabase", "migrations");
  for (const file of readdirSync(dir)
    .filter((f) => f.endsWith(".sql"))
    .sort()) {
    await db.exec(readFileSync(join(dir, file), "utf8"));
  }
  if (opts.seed) await db.exec(readFileSync(join(root, "supabase", "seed.sql"), "utf8"));
  return db;
}

/** Run `fn` as a Supabase-like caller (anon, or authenticated as `userId`). */
export async function asUser<T>(
  db: PGlite,
  userId: string | null,
  fn: () => Promise<T>,
): Promise<T> {
  if (userId) {
    await db.exec(
      `set role authenticated; select set_config('request.jwt.claim.sub', '${userId}', false);`,
    );
  } else {
    await db.exec(`set role anon; select set_config('request.jwt.claim.sub', '', false);`);
  }
  try {
    return await fn();
  } finally {
    await db.exec(`reset role; select set_config('request.jwt.claim.sub', '', false);`);
  }
}

export const ids = {
  clinicA: "00000000-0000-4000-8000-0000000000c1",
  clinicB: "00000000-0000-4000-8000-0000000000c2",
  doctorA1: "00000000-0000-4000-8000-0000000000d1",
  doctorA2: "00000000-0000-4000-8000-0000000000d2",
  doctorB1: "00000000-0000-4000-8000-0000000000d3",
  serviceA1: "00000000-0000-4000-8000-0000000000e1",
  serviceB1: "00000000-0000-4000-8000-0000000000e4",
  patientA1: "00000000-0000-4000-8000-0000000000f1",
  patientA2: "00000000-0000-4000-8000-0000000000f2",
  patientB1: "00000000-0000-4000-8000-0000000000f3",
  // auth users created by tests
  superAdmin: "00000000-0000-4000-8000-00000000a001",
  adminA: "00000000-0000-4000-8000-00000000a002",
  adminB: "00000000-0000-4000-8000-00000000a003",
  receptionA: "00000000-0000-4000-8000-00000000a004",
  doctorUserA1: "00000000-0000-4000-8000-00000000a005",
  doctorUserA2: "00000000-0000-4000-8000-00000000a006",
  patientUserA1: "00000000-0000-4000-8000-00000000a007",
};

/** Create auth users + profiles and link doctor/patient rows to them. */
export async function seedUsers(db: PGlite): Promise<void> {
  const u = ids;
  await db.exec(`
    insert into auth.users (id) values
      ('${u.superAdmin}'), ('${u.adminA}'), ('${u.adminB}'), ('${u.receptionA}'),
      ('${u.doctorUserA1}'), ('${u.doctorUserA2}'), ('${u.patientUserA1}');
    insert into public.profiles (id, clinic_id, role, full_name) values
      ('${u.superAdmin}', null, 'super_admin', 'Super Admin'),
      ('${u.adminA}', '${u.clinicA}', 'clinic_admin', 'Admin A'),
      ('${u.adminB}', '${u.clinicB}', 'clinic_admin', 'Admin B'),
      ('${u.receptionA}', '${u.clinicA}', 'receptionist', 'Reception A'),
      ('${u.doctorUserA1}', '${u.clinicA}', 'doctor', 'Doc A1'),
      ('${u.doctorUserA2}', '${u.clinicA}', 'doctor', 'Doc A2'),
      ('${u.patientUserA1}', null, 'patient', 'Pat Example');
    update public.doctors set profile_id = '${u.doctorUserA1}' where id = '${u.doctorA1}';
    update public.doctors set profile_id = '${u.doctorUserA2}' where id = '${u.doctorA2}';
    update public.patients set user_id = '${u.patientUserA1}' where id = '${u.patientA1}';
  `);
}
