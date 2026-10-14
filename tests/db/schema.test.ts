import { beforeAll, describe, expect, it } from "vitest";
import type { PGlite } from "@electric-sql/pglite";
import { asUser, createDb, ids, seedUsers } from "./helpers";

let db: PGlite;

beforeAll(async () => {
  db = await createDb({ seed: true });
  await seedUsers(db);
}, 60_000);

const count = async (sql: string) =>
  Number((await db.query<{ n: string }>(`select count(*) n from (${sql}) t`)).rows[0].n);

function insertAppt(opts: {
  clinic?: string;
  patient?: string;
  doctor?: string;
  service?: string;
  start: string;
  end: string;
  status?: string;
}) {
  return db.query(
    `insert into public.appointments
      (clinic_id, patient_id, doctor_id, service_id, appointment_type, status, booked_via, starts_at, ends_at)
     values ($1,$2,$3,$4,'in_person',$5,'form',$6,$7)`,
    [
      opts.clinic ?? ids.clinicA,
      opts.patient ?? ids.patientA2,
      opts.doctor ?? ids.doctorA1,
      opts.service ?? ids.serviceA1,
      opts.status ?? "scheduled",
      opts.start,
      opts.end,
    ],
  );
}

describe("double booking", () => {
  const day = "2031-03-03";
  it("rejects an overlapping appointment for the same doctor", async () => {
    await insertAppt({ start: `${day}T10:00:00Z`, end: `${day}T10:30:00Z` });
    await expect(
      insertAppt({ start: `${day}T10:15:00Z`, end: `${day}T10:45:00Z` }),
    ).rejects.toThrow(/appointments_no_overlap/);
  });
  it("allows back-to-back appointments", async () => {
    await insertAppt({ start: `${day}T10:30:00Z`, end: `${day}T11:00:00Z` });
  });
  it("allows the same time for a different doctor", async () => {
    await insertAppt({ doctor: ids.doctorA2, start: `${day}T10:00:00Z`, end: `${day}T10:30:00Z` });
  });
  it("lets a cancelled slot be rebooked", async () => {
    await insertAppt({ start: `${day}T12:00:00Z`, end: `${day}T12:30:00Z`, status: "cancelled" });
    await insertAppt({ start: `${day}T12:00:00Z`, end: `${day}T12:30:00Z` });
  });
});

describe("tenant integrity", () => {
  it("rejects an appointment mixing clinic A with clinic B's doctor", async () => {
    await expect(
      insertAppt({
        doctor: ids.doctorB1,
        start: "2031-04-01T10:00:00Z",
        end: "2031-04-01T10:30:00Z",
      }),
    ).rejects.toThrow(/foreign key/i);
  });
  it("rejects a timed appointment without a doctor or time", async () => {
    await expect(
      db.query(
        `insert into public.appointments (clinic_id, patient_id, appointment_type, booked_via)
         values ($1,$2,'in_person','form')`,
        [ids.clinicA, ids.patientA1],
      ),
    ).rejects.toThrow(/appointments_shape/);
  });
  it("issues unique walk-in queue tokens per clinic per day", async () => {
    const t1 = (
      await db.query<{ t: number }>(`select app.next_queue_token($1,'2031-05-01') t`, [ids.clinicA])
    ).rows[0].t;
    const t2 = (
      await db.query<{ t: number }>(`select app.next_queue_token($1,'2031-05-01') t`, [ids.clinicA])
    ).rows[0].t;
    const other = (
      await db.query<{ t: number }>(`select app.next_queue_token($1,'2031-05-01') t`, [ids.clinicB])
    ).rows[0].t;
    expect([t1, t2, other]).toEqual([1, 2, 1]);
  });
});

describe("RLS: anonymous visitors", () => {
  it("can read public clinic, doctor and service data", async () => {
    await asUser(db, null, async () => {
      expect(await count("select 1 from public.clinics")).toBe(2);
      expect(await count("select 1 from public.doctors")).toBe(4);
      expect(await count("select 1 from public.services")).toBeGreaterThan(0);
    });
  });
  it("cannot read patients, appointments, invoices or agent data", async () => {
    await asUser(db, null, async () => {
      for (const t of [
        "appointments",
        "invoices",
        "invoice_items",
        "audit_log",
        "doctor_schedules",
        "profiles",
      ]) {
        await expect(db.query(`select 1 from public.${t}`)).rejects.toThrow(/permission denied/);
      }
      await expect(db.query(`select 1 from public.patients`)).rejects.toThrow(/permission denied/);
      await expect(db.query(`select 1 from public.agent_messages`)).rejects.toThrow(
        /permission denied/,
      );
    });
  });
  it("cannot write anything", async () => {
    await asUser(db, null, async () => {
      await expect(
        db.query(
          `insert into public.patients (clinic_id, full_name, email) values ($1,'x','x@x.test')`,
          [ids.clinicA],
        ),
      ).rejects.toThrow(/permission denied/);
    });
  });
  it("does not see inactive doctors", async () => {
    await db.exec(`update public.doctors set is_active = false where id = '${ids.doctorA2}'`);
    await asUser(db, null, async () => {
      expect(await count("select 1 from public.doctors")).toBe(3);
    });
    await db.exec(`update public.doctors set is_active = true where id = '${ids.doctorA2}'`);
  });
});

describe("RLS: tenant isolation", () => {
  it("clinic A admin sees only clinic A patients and appointments", async () => {
    await asUser(db, ids.adminA, async () => {
      expect(await count(`select 1 from public.patients where clinic_id = '${ids.clinicB}'`)).toBe(
        0,
      );
      expect(
        await count(`select 1 from public.appointments where clinic_id = '${ids.clinicB}'`),
      ).toBe(0);
      expect(await count(`select 1 from public.patients where clinic_id = '${ids.clinicA}'`)).toBe(
        2,
      );
    });
  });
  it("clinic A admin cannot insert into clinic B", async () => {
    await asUser(db, ids.adminA, async () => {
      await expect(
        db.query(
          `insert into public.patients (clinic_id, full_name, email) values ($1,'x','leak@x.test')`,
          [ids.clinicB],
        ),
      ).rejects.toThrow(/row-level security/);
    });
  });
  it("clinic A admin cannot update or delete clinic B rows (silently 0 rows)", async () => {
    await asUser(db, ids.adminA, async () => {
      const upd = await db.query(
        `update public.patients set full_name = 'hacked' where clinic_id = $1`,
        [ids.clinicB],
      );
      const del = await db.query(`delete from public.appointments where clinic_id = $1`, [
        ids.clinicB,
      ]);
      expect(upd.affectedRows).toBe(0);
      expect(del.affectedRows).toBe(0);
    });
  });
  it("clinic admins cannot read other clinics' profiles or audit log", async () => {
    await db.exec(
      `insert into public.audit_log (clinic_id, action) values ('${ids.clinicB}', 'test')`,
    );
    await asUser(db, ids.adminA, async () => {
      expect(await count(`select 1 from public.profiles where clinic_id = '${ids.clinicB}'`)).toBe(
        0,
      );
      expect(await count(`select 1 from public.audit_log where clinic_id = '${ids.clinicB}'`)).toBe(
        0,
      );
    });
  });
  it("super admin sees every clinic", async () => {
    await asUser(db, ids.superAdmin, async () => {
      expect(await count("select 1 from public.patients")).toBe(3);
      expect(await count("select 1 from public.appointments")).toBeGreaterThan(2);
    });
  });
  it("clinic admin cannot create a super admin profile", async () => {
    await db.exec(`insert into auth.users (id) values ('00000000-0000-4000-8000-00000000b001')`);
    await asUser(db, ids.adminA, async () => {
      await expect(
        db.query(
          `insert into public.profiles (id, clinic_id, role, full_name)
           values ('00000000-0000-4000-8000-00000000b001', null, 'super_admin', 'x')`,
        ),
      ).rejects.toThrow(/row-level security/);
    });
  });
});

describe("RLS: roles inside a clinic", () => {
  it("receptionist can manage appointments but not doctors or clinic settings", async () => {
    await asUser(db, ids.receptionA, async () => {
      expect(
        await count(`select 1 from public.appointments where clinic_id = '${ids.clinicA}'`),
      ).toBeGreaterThan(0);
      const upd = await db.query(`update public.doctors set full_name = 'x' where id = $1`, [
        ids.doctorA1,
      ]);
      expect(upd.affectedRows).toBe(0);
      const clinic = await db.query(`update public.clinics set name = 'x' where id = $1`, [
        ids.clinicA,
      ]);
      expect(clinic.affectedRows).toBe(0);
    });
  });
  it("doctor only sees patients they have an appointment with", async () => {
    await asUser(db, ids.doctorUserA1, async () => {
      expect(await count(`select 1 from public.patients where id = '${ids.patientA1}'`)).toBe(1);
      expect(await count(`select 1 from public.patients where clinic_id = '${ids.clinicB}'`)).toBe(
        0,
      );
      // every visible patient must have an appointment with this doctor
      expect(
        await count(
          `select 1 from public.patients p where not exists
             (select 1 from public.appointments a where a.patient_id = p.id and a.doctor_id = '${ids.doctorA1}')`,
        ),
      ).toBe(0);
    });
    await asUser(db, ids.doctorUserA2, async () => {
      expect(await count(`select 1 from public.patients where id = '${ids.patientA1}'`)).toBe(0);
    });
  });
  it("doctor sees only their own appointments and no invoices", async () => {
    await asUser(db, ids.doctorUserA2, async () => {
      expect(
        await count(`select 1 from public.appointments where doctor_id = '${ids.doctorA1}'`),
      ).toBe(0);
      expect(await count("select 1 from public.invoices")).toBe(0);
    });
  });
  it("a patient with an account sees only their own records", async () => {
    await db.exec(`
      insert into public.invoices (clinic_id, patient_id, invoice_number, currency)
      values ('${ids.clinicA}', '${ids.patientA1}', 'INV-1', 'USD'), ('${ids.clinicA}', '${ids.patientA2}', 'INV-2', 'USD');
    `);
    await asUser(db, ids.patientUserA1, async () => {
      expect(await count("select 1 from public.patients")).toBe(1);
      expect(await count("select 1 from public.invoices")).toBe(1);
      expect(
        await count(`select 1 from public.appointments where patient_id <> '${ids.patientA1}'`),
      ).toBe(0);
    });
  });
});

describe("server-only and append-only tables", () => {
  it("agent tables, consents and queue counters are denied to every signed-in role", async () => {
    for (const user of [ids.adminA, ids.superAdmin]) {
      await asUser(db, user, async () => {
        for (const t of ["agent_sessions", "agent_messages", "consents", "queue_counters"]) {
          await expect(db.query(`select 1 from public.${t}`)).rejects.toThrow(/permission denied/);
        }
      });
    }
  });
  it("the audit log cannot be written, changed, or deleted by clinic admins", async () => {
    await asUser(db, ids.adminB, async () => {
      await expect(db.query(`insert into public.audit_log (action) values ('x')`)).rejects.toThrow(
        /permission denied/,
      );
      await expect(db.query(`update public.audit_log set action = 'x'`)).rejects.toThrow(
        /permission denied/,
      );
      await expect(db.query(`delete from public.audit_log`)).rejects.toThrow(/permission denied/);
    });
  });
  it("walk-in queue token generator is not callable by signed-in users", async () => {
    await asUser(db, ids.adminA, async () => {
      await expect(
        db.query(`select app.next_queue_token($1, current_date)`, [ids.clinicA]),
      ).rejects.toThrow(/permission denied/);
    });
  });
});
