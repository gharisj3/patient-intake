-- Patient Intake: initial schema (multi-tenant, one tenant = one clinic).
-- Rules: every tenant table has clinic_id, RLS enabled, default deny.
-- v1 scope: scheduling + intake only. NO clinical notes / prescriptions.

create extension if not exists btree_gist;

create schema if not exists app;

-- ---------------------------------------------------------------- enums
create type public.user_role as enum
  ('super_admin', 'clinic_admin', 'receptionist', 'doctor', 'patient');
create type public.appointment_type as enum
  ('in_person', 'video', 'phone', 'walk_in');
create type public.appointment_status as enum
  ('scheduled', 'confirmed', 'checked_in', 'completed', 'cancelled', 'no_show');
create type public.appointment_kind as enum
  ('new', 'follow_up', 'transfer');
create type public.booked_via as enum
  ('form', 'agent', 'staff', 'walk_in');
create type public.invoice_status as enum
  ('draft', 'sent', 'paid', 'void');
create type public.payment_method as enum
  ('cash', 'bank_transfer', 'card', 'online', 'other');

-- ---------------------------------------------------------------- helpers
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------- tables
create table public.clinics (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  slug         text not null unique check (slug ~ '^[a-z0-9-]+$'),
  timezone     text not null default 'UTC',
  currency     char(3) not null default 'USD',
  jurisdiction text not null default 'GLOBAL',
  phone        text,
  email        text,
  address      text,
  brand        jsonb not null default '{}'::jsonb,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  clinic_id  uuid references public.clinics (id) on delete cascade,
  role       public.user_role not null,
  full_name  text not null,
  email      text,
  created_at timestamptz not null default now(),
  -- super_admin and patient accounts are not tied to one clinic; staff always are
  constraint profiles_clinic_by_role check (
    (role in ('super_admin', 'patient') and clinic_id is null)
    or (role not in ('super_admin', 'patient') and clinic_id is not null)
  )
);
create index profiles_clinic_idx on public.profiles (clinic_id);

create table public.doctors (
  id         uuid primary key default gen_random_uuid(),
  clinic_id  uuid not null references public.clinics (id) on delete cascade,
  profile_id uuid unique references public.profiles (id) on delete set null,
  full_name  text not null,
  specialty  text,
  bio        text,
  photo_url  text,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, clinic_id)
);
create index doctors_clinic_idx on public.doctors (clinic_id);

create table public.patients (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references public.clinics (id) on delete cascade,
  user_id       uuid references public.profiles (id) on delete set null,
  full_name     text not null,
  email         text not null,
  phone         text,
  date_of_birth date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (id, clinic_id)
);
create unique index patients_clinic_email_uq on public.patients (clinic_id, lower(email));
create index patients_user_idx on public.patients (user_id);
create trigger patients_updated before update on public.patients
  for each row execute function public.set_updated_at();

create table public.services (
  id               uuid primary key default gen_random_uuid(),
  clinic_id        uuid not null references public.clinics (id) on delete cascade,
  name             text not null,
  description      text,
  appointment_type public.appointment_type not null default 'in_person',
  duration_minutes integer not null default 30 check (duration_minutes between 5 and 480),
  price_cents      integer not null default 0 check (price_cents >= 0),
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  unique (id, clinic_id)
);
create index services_clinic_idx on public.services (clinic_id);

create table public.doctor_services (
  clinic_id  uuid not null references public.clinics (id) on delete cascade,
  doctor_id  uuid not null,
  service_id uuid not null,
  primary key (doctor_id, service_id),
  foreign key (doctor_id, clinic_id) references public.doctors (id, clinic_id) on delete cascade,
  foreign key (service_id, clinic_id) references public.services (id, clinic_id) on delete cascade
);

create table public.doctor_schedules (
  id         uuid primary key default gen_random_uuid(),
  clinic_id  uuid not null references public.clinics (id) on delete cascade,
  doctor_id  uuid not null,
  weekday    smallint not null check (weekday between 0 and 6), -- 0 = Sunday, clinic-local
  start_time time not null,
  end_time   time not null,
  check (end_time > start_time),
  foreign key (doctor_id, clinic_id) references public.doctors (id, clinic_id) on delete cascade
);
create index doctor_schedules_doctor_idx on public.doctor_schedules (doctor_id);

create table public.time_off (
  id        uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics (id) on delete cascade,
  doctor_id uuid not null,
  during    tstzrange not null check (not isempty(during)),
  reason    text,
  foreign key (doctor_id, clinic_id) references public.doctors (id, clinic_id) on delete cascade
);
create index time_off_doctor_idx on public.time_off (doctor_id);

create table public.appointments (
  id                      uuid primary key default gen_random_uuid(),
  clinic_id               uuid not null references public.clinics (id) on delete cascade,
  patient_id              uuid not null,
  doctor_id               uuid,
  service_id              uuid,
  appointment_type        public.appointment_type not null,
  status                  public.appointment_status not null default 'scheduled',
  kind                    public.appointment_kind not null default 'new',
  booked_via              public.booked_via not null,
  starts_at               timestamptz,
  ends_at                 timestamptz,
  during                  tstzrange generated always as (tstzrange(starts_at, ends_at, '[)')) stored,
  queue_date              date,
  queue_token             integer,
  previous_appointment_id uuid references public.appointments (id) on delete set null,
  reason_for_visit        text check (char_length(reason_for_visit) <= 200),
  meeting_url             text,
  cancel_token_hash       text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (id, clinic_id),
  foreign key (patient_id, clinic_id) references public.patients (id, clinic_id) on delete cascade,
  foreign key (doctor_id, clinic_id) references public.doctors (id, clinic_id) on delete set null (doctor_id),
  foreign key (service_id, clinic_id) references public.services (id, clinic_id) on delete set null (service_id),
  -- timed visits need a doctor and a time range; walk-ins need a queue token
  constraint appointments_shape check (
    (appointment_type <> 'walk_in'
       and doctor_id is not null and starts_at is not null and ends_at is not null and ends_at > starts_at)
    or
    (appointment_type = 'walk_in'
       and queue_date is not null and queue_token is not null)
  )
);
create index appointments_clinic_start_idx on public.appointments (clinic_id, starts_at);
create index appointments_patient_idx on public.appointments (patient_id);
create index appointments_doctor_idx on public.appointments (doctor_id);
create trigger appointments_updated before update on public.appointments
  for each row execute function public.set_updated_at();

-- No double booking: one doctor cannot have overlapping active timed appointments.
alter table public.appointments add constraint appointments_no_overlap
  exclude using gist (doctor_id with =, during with &&)
  where (appointment_type <> 'walk_in' and status not in ('cancelled', 'no_show'));

-- One queue token per clinic per day.
create unique index appointments_queue_uq
  on public.appointments (clinic_id, queue_date, queue_token)
  where appointment_type = 'walk_in';

create table public.queue_counters (
  clinic_id  uuid not null references public.clinics (id) on delete cascade,
  queue_date date not null,
  last_token integer not null default 0,
  primary key (clinic_id, queue_date)
);

create or replace function app.next_queue_token(p_clinic uuid, p_date date) returns integer
language sql security definer set search_path = public as $$
  insert into public.queue_counters as q (clinic_id, queue_date, last_token)
  values (p_clinic, p_date, 1)
  on conflict (clinic_id, queue_date) do update set last_token = q.last_token + 1
  returning last_token
$$;

create table public.invoices (
  id             uuid primary key default gen_random_uuid(),
  clinic_id      uuid not null references public.clinics (id) on delete cascade,
  patient_id     uuid not null,
  appointment_id uuid,
  invoice_number text not null,
  status         public.invoice_status not null default 'draft',
  currency       char(3) not null,
  subtotal_cents integer not null default 0 check (subtotal_cents >= 0),
  tax_cents      integer not null default 0 check (tax_cents >= 0),
  total_cents    integer not null default 0 check (total_cents >= 0),
  payment_method public.payment_method,
  paid_at        timestamptz,
  due_date       date,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (id, clinic_id),
  unique (clinic_id, invoice_number),
  foreign key (patient_id, clinic_id) references public.patients (id, clinic_id) on delete cascade,
  foreign key (appointment_id, clinic_id) references public.appointments (id, clinic_id) on delete set null (appointment_id),
  check (status <> 'paid' or (paid_at is not null and payment_method is not null))
);
create index invoices_patient_idx on public.invoices (patient_id);
create trigger invoices_updated before update on public.invoices
  for each row execute function public.set_updated_at();

create table public.invoice_items (
  id               uuid primary key default gen_random_uuid(),
  clinic_id        uuid not null references public.clinics (id) on delete cascade,
  invoice_id       uuid not null,
  description      text not null,
  quantity         integer not null default 1 check (quantity > 0),
  unit_price_cents integer not null check (unit_price_cents >= 0),
  tax_rate_bps     integer not null default 0 check (tax_rate_bps between 0 and 10000),
  foreign key (invoice_id, clinic_id) references public.invoices (id, clinic_id) on delete cascade
);
create index invoice_items_invoice_idx on public.invoice_items (invoice_id);

-- Agent sessions/messages: server-only (service role). No policies => denied to everyone else.
create table public.agent_sessions (
  id          uuid primary key default gen_random_uuid(),
  clinic_id   uuid not null references public.clinics (id) on delete cascade,
  patient_id  uuid,
  state       jsonb not null default '{}'::jsonb,
  verified_at timestamptz,
  expires_at  timestamptz not null default now() + interval '30 days',
  created_at  timestamptz not null default now(),
  unique (id, clinic_id),
  foreign key (patient_id, clinic_id) references public.patients (id, clinic_id) on delete set null (patient_id)
);

create table public.agent_messages (
  id         uuid primary key default gen_random_uuid(),
  clinic_id  uuid not null references public.clinics (id) on delete cascade,
  session_id uuid not null,
  role       text not null check (role in ('user', 'assistant', 'tool')),
  content    text not null,
  created_at timestamptz not null default now(),
  foreign key (session_id, clinic_id) references public.agent_sessions (id, clinic_id) on delete cascade
);
create index agent_messages_session_idx on public.agent_messages (session_id, created_at);

create table public.consents (
  id           uuid primary key default gen_random_uuid(),
  clinic_id    uuid not null references public.clinics (id) on delete cascade,
  patient_id   uuid,
  consent_type text not null, -- e.g. privacy_notice, agent_chat, voice_recording
  version      text not null,
  granted      boolean not null,
  ip_hash      text,
  created_at   timestamptz not null default now(),
  foreign key (patient_id, clinic_id) references public.patients (id, clinic_id) on delete set null (patient_id)
);

-- Append-only. Metadata must never contain PHI.
create table public.audit_log (
  id          bigint generated always as identity primary key,
  clinic_id   uuid references public.clinics (id) on delete set null,
  actor_id    uuid,
  action      text not null,
  entity_type text,
  entity_id   uuid,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index audit_log_clinic_idx on public.audit_log (clinic_id, created_at desc);

-- ---------------------------------------------------------------- RLS helpers
-- SECURITY DEFINER so policies can read profiles without recursing into profiles' own RLS.
create or replace function app.my_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function app.my_clinic() returns uuid
language sql stable security definer set search_path = public as $$
  select clinic_id from public.profiles where id = auth.uid()
$$;

create or replace function app.my_doctor_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.doctors where profile_id = auth.uid()
$$;

create or replace function app.my_patient_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  select id from public.patients where user_id = auth.uid()
$$;

create or replace function app.is_super() returns boolean
language sql stable as $$ select coalesce(app.my_role() = 'super_admin', false) $$;

create or replace function app.is_admin_of(c uuid) returns boolean
language sql stable as $$
  select app.is_super() or (app.my_role() = 'clinic_admin' and app.my_clinic() = c)
$$;

create or replace function app.is_front_desk_of(c uuid) returns boolean
language sql stable as $$
  select app.is_super()
      or (app.my_role() in ('clinic_admin', 'receptionist') and app.my_clinic() = c)
$$;

create or replace function app.is_staff_of(c uuid) returns boolean
language sql stable as $$
  select app.is_super()
      or (app.my_role() in ('clinic_admin', 'receptionist', 'doctor') and app.my_clinic() = c)
$$;

-- ---------------------------------------------------------------- privileges
revoke all on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on function app.next_queue_token(uuid, date) from public, anon, authenticated;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema app to anon, authenticated, service_role;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on function app.next_queue_token(uuid, date) to service_role;

-- Public website data (read-only). Row filtering is done by RLS below.
grant select on public.clinics, public.doctors, public.services, public.doctor_services to anon;

grant select, insert, update, delete on
  public.clinics, public.profiles, public.doctors, public.patients, public.services,
  public.doctor_services, public.doctor_schedules, public.time_off, public.appointments,
  public.invoices, public.invoice_items
  to authenticated;
-- audit log: staff can read; only the server (service role) writes. Never updatable.
grant select on public.audit_log to authenticated;
-- agent_sessions, agent_messages, consents, queue_counters: service role only.

-- ---------------------------------------------------------------- RLS
alter table public.clinics          enable row level security;
alter table public.profiles         enable row level security;
alter table public.doctors          enable row level security;
alter table public.patients         enable row level security;
alter table public.services         enable row level security;
alter table public.doctor_services  enable row level security;
alter table public.doctor_schedules enable row level security;
alter table public.time_off         enable row level security;
alter table public.appointments     enable row level security;
alter table public.invoices         enable row level security;
alter table public.invoice_items    enable row level security;
alter table public.agent_sessions   enable row level security;
alter table public.agent_messages   enable row level security;
alter table public.consents         enable row level security;
alter table public.queue_counters   enable row level security;
alter table public.audit_log        enable row level security;

-- clinics
create policy clinics_public_read on public.clinics for select to anon, authenticated
  using (is_active);
create policy clinics_member_read on public.clinics for select to authenticated
  using (app.is_super() or id = app.my_clinic());
create policy clinics_super_write on public.clinics for all to authenticated
  using (app.is_super()) with check (app.is_super());

-- profiles
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or (clinic_id is not null and app.is_admin_of(clinic_id)) or app.is_super());
create policy profiles_admin_write on public.profiles for all to authenticated
  using (role <> 'super_admin' and clinic_id is not null and app.is_admin_of(clinic_id))
  with check (role not in ('super_admin', 'patient') and clinic_id is not null and app.is_admin_of(clinic_id));
create policy profiles_super_write on public.profiles for all to authenticated
  using (app.is_super()) with check (app.is_super());

-- doctors
create policy doctors_public_read on public.doctors for select to anon, authenticated
  using (is_active);
create policy doctors_staff_read on public.doctors for select to authenticated
  using (app.is_staff_of(clinic_id));
create policy doctors_admin_write on public.doctors for all to authenticated
  using (app.is_admin_of(clinic_id)) with check (app.is_admin_of(clinic_id));

-- patients (doctor access is relationship-based: only patients they have an appointment with)
create policy patients_read on public.patients for select to authenticated
  using (
    app.is_front_desk_of(clinic_id)
    or user_id = auth.uid()
    or (
      app.my_role() = 'doctor' and app.my_clinic() = clinic_id
      and exists (
        select 1 from public.appointments a
        where a.patient_id = patients.id and a.doctor_id = app.my_doctor_id()
      )
    )
  );
create policy patients_front_desk_write on public.patients for all to authenticated
  using (app.is_front_desk_of(clinic_id)) with check (app.is_front_desk_of(clinic_id));

-- services
create policy services_public_read on public.services for select to anon, authenticated
  using (is_active);
create policy services_staff_read on public.services for select to authenticated
  using (app.is_staff_of(clinic_id));
create policy services_admin_write on public.services for all to authenticated
  using (app.is_admin_of(clinic_id)) with check (app.is_admin_of(clinic_id));

-- doctor_services
create policy doctor_services_public_read on public.doctor_services for select to anon, authenticated
  using (true);
create policy doctor_services_admin_write on public.doctor_services for all to authenticated
  using (app.is_admin_of(clinic_id)) with check (app.is_admin_of(clinic_id));

-- doctor_schedules / time_off (availability is computed server-side for the public)
create policy doctor_schedules_staff_read on public.doctor_schedules for select to authenticated
  using (app.is_staff_of(clinic_id));
create policy doctor_schedules_admin_write on public.doctor_schedules for all to authenticated
  using (app.is_admin_of(clinic_id)) with check (app.is_admin_of(clinic_id));
create policy time_off_staff_read on public.time_off for select to authenticated
  using (app.is_staff_of(clinic_id));
create policy time_off_admin_write on public.time_off for all to authenticated
  using (app.is_admin_of(clinic_id)) with check (app.is_admin_of(clinic_id));

-- appointments
create policy appointments_read on public.appointments for select to authenticated
  using (
    app.is_front_desk_of(clinic_id)
    or (doctor_id is not null and doctor_id = app.my_doctor_id())
    or patient_id in (select app.my_patient_ids())
  );
create policy appointments_front_desk_write on public.appointments for all to authenticated
  using (app.is_front_desk_of(clinic_id)) with check (app.is_front_desk_of(clinic_id));
create policy appointments_doctor_update on public.appointments for update to authenticated
  using (doctor_id is not null and doctor_id = app.my_doctor_id())
  with check (doctor_id is not null and doctor_id = app.my_doctor_id());

-- invoices (doctors get no billing access)
create policy invoices_read on public.invoices for select to authenticated
  using (app.is_front_desk_of(clinic_id) or patient_id in (select app.my_patient_ids()));
create policy invoices_front_desk_write on public.invoices for all to authenticated
  using (app.is_front_desk_of(clinic_id)) with check (app.is_front_desk_of(clinic_id));
create policy invoice_items_read on public.invoice_items for select to authenticated
  using (
    app.is_front_desk_of(clinic_id)
    or exists (
      select 1 from public.invoices i
      where i.id = invoice_items.invoice_id and i.patient_id in (select app.my_patient_ids())
    )
  );
create policy invoice_items_front_desk_write on public.invoice_items for all to authenticated
  using (app.is_front_desk_of(clinic_id)) with check (app.is_front_desk_of(clinic_id));

-- audit_log: clinic admins read their clinic's log; nobody but the service role writes.
create policy audit_log_admin_read on public.audit_log for select to authenticated
  using (app.is_super() or (clinic_id is not null and app.is_admin_of(clinic_id)));

-- agent_sessions, agent_messages, consents, queue_counters: RLS on, no policies => deny all.
