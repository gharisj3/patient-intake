-- DEMO DATA ONLY. All names, emails and phone numbers are fake.
-- Auth users/profiles are created separately (see scripts/ in a later step).

insert into public.clinics (id, name, slug, timezone, currency, jurisdiction, phone, email, address, brand) values
  ('00000000-0000-4000-8000-0000000000c1', 'Northside Family Clinic', 'northside', 'America/New_York', 'USD', 'GLOBAL',
   '+1 555 010 0100', 'hello@northside.example', '100 Demo Street, Springfield', '{"primary":"#0f766e"}'),
  ('00000000-0000-4000-8000-0000000000c2', 'Karachi Care Clinic', 'karachi-care', 'Asia/Karachi', 'PKR', 'GLOBAL',
   '+92 300 0000000', 'hello@karachicare.example', '12 Demo Road, Karachi', '{"primary":"#1d4ed8"}');

insert into public.doctors (id, clinic_id, full_name, specialty, bio) values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000c1', 'Dr. Amelia Hart',  'Family Medicine', 'Demo profile.'),
  ('00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-0000000000c1', 'Dr. Ben Okafor',   'Pediatrics',      'Demo profile.'),
  ('00000000-0000-4000-8000-0000000000d3', '00000000-0000-4000-8000-0000000000c2', 'Dr. Sana Malik',   'General Physician','Demo profile.'),
  ('00000000-0000-4000-8000-0000000000d4', '00000000-0000-4000-8000-0000000000c2', 'Dr. Imran Qureshi','Dermatology',     'Demo profile.');

insert into public.services (id, clinic_id, name, appointment_type, duration_minutes, price_cents) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000c1', 'General Checkup',      'in_person', 30, 8000),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000c1', 'Video Consultation',   'video',     20, 5000),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000c1', 'Walk-in Visit',        'walk_in',   15, 4000),
  ('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000c2', 'Consultation',         'in_person', 30, 200000),
  ('00000000-0000-4000-8000-0000000000e5', '00000000-0000-4000-8000-0000000000c2', 'Phone Consultation',   'phone',     15, 100000);

insert into public.doctor_services (clinic_id, doctor_id, service_id) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000e1'),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000e2'),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-0000000000e1'),
  ('00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-0000000000d3', '00000000-0000-4000-8000-0000000000e4'),
  ('00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-0000000000d3', '00000000-0000-4000-8000-0000000000e5'),
  ('00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-0000000000d4', '00000000-0000-4000-8000-0000000000e4');

-- Monday to Friday, 09:00-17:00 (clinic-local) for every doctor
insert into public.doctor_schedules (clinic_id, doctor_id, weekday, start_time, end_time)
select d.clinic_id, d.id, w, time '09:00', time '17:00'
from public.doctors d, generate_series(1, 5) as w;

insert into public.patients (id, clinic_id, full_name, email, phone) values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000c1', 'Pat Example',   'pat@example.test',   '+1 555 010 0101'),
  ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000c1', 'Jordan Sample', 'jordan@example.test','+1 555 010 0102'),
  ('00000000-0000-4000-8000-0000000000f3', '00000000-0000-4000-8000-0000000000c2', 'Ayesha Demo',   'ayesha@example.test','+92 300 0000001');

-- A couple of future appointments (tomorrow, UTC)
insert into public.appointments
  (clinic_id, patient_id, doctor_id, service_id, appointment_type, status, kind, booked_via, starts_at, ends_at)
values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000d1',
   '00000000-0000-4000-8000-0000000000e1', 'in_person', 'confirmed', 'new', 'form',
   date_trunc('day', now()) + interval '1 day 14 hours', date_trunc('day', now()) + interval '1 day 14 hours 30 minutes'),
  ('00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-0000000000f3', '00000000-0000-4000-8000-0000000000d3',
   '00000000-0000-4000-8000-0000000000e4', 'in_person', 'scheduled', 'new', 'agent',
   date_trunc('day', now()) + interval '1 day 10 hours', date_trunc('day', now()) + interval '1 day 10 hours 30 minutes');
