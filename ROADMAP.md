# Roadmap — Patient Intake Platform

Goal: production-ready patient intake + booking platform, built and demoed on free hosting first, hardened for real patient data afterwards.

## Open decisions
- [x] Clinical notes/prescriptions: DECIDED out of v1 (scheduling + intake only). Revisit after v1 (needs relationship-based RLS, break-glass, consent, per-view audit).
- [x] Target countries: DECIDED USA, Canada, Pakistan. Build to strictest standard; per-clinic `jurisdiction` setting; consent records; multi-currency invoices.
- [x] First clinic country: DECIDED universal platform, testing phase; compliance deferred. Revisit the region/BAA/payment gateway choice before any real launch.
- [x] Discovery decisions: multi-clinic from day one; roles super_admin/clinic_admin/receptionist/doctor + optional patient account; visit types in_person/video/phone/walk_in; invoices manual + online later; English only; email + web push; Claude designs branding; browser voice now, phone number later. Details in CLAUDE.md "Discovery answers".
- [x] Tenancy: DECIDED separate customers (full multi-tenant SaaS), isolated per clinic.

## 0. Key decisions up front

| Topic | Decision |
|---|---|
| Stack | Next.js + TypeScript, Supabase (Postgres/Auth/RLS), Claude API for agent |
| Free hosting | Vercel Hobby (app) + Supabase Free (db/auth) + Upstash/Resend/Sentry free tiers |
| Agent | One backend booking service shared by form and agent; agent uses tool calling |
| Voice | Phase A: chat. Phase B: browser speech (Web Speech API, free) + optional Groq Whisper STT / in-browser Kokoro or Piper TTS. No paid voice tools (user decision). Revisit only if production quality demands it |
| LLM | Provider-agnostic adapter: Gemini Flash free (dev) with Groq fallback; BAA-covered provider for production |
| Agent memory | 3 layers: conversation, booking state machine, patient memory via tools after OTP. See CLAUDE.md "Agent design" |
| Data rule | **Synthetic data only** until Phase 7 compliance gate |

### Important caveat: free hosting vs. real patient data
Free tiers are fine to **build, demo and test**. They are **not** fine for real patient records:
- Vercel Hobby is for non-commercial use; HIPAA BAA needs Enterprise.
- Supabase free has no BAA (HIPAA add-on requires Team plan+).
- Claude API: use a zero-data-retention / BAA arrangement before sending any PHI to it.
- If you're outside the US the equivalent applies (GDPR, local health-data laws). Confirm which regulation applies to your clinic's country before launch.

Until Phase 7 is passed: seed/fake patients only, banner on the site "Demo — do not enter real health information."

---

## Phase 1 — Foundation (week 1)
- [x] Define scope, user roles: `super_admin`, `clinic_admin`, `receptionist`, `doctor`, optional `patient`
- [x] Next.js 16 + TS strict + Tailwind v4, ESLint, Prettier (shadcn/ui: add when UI work starts)
- [x] GitHub Actions CI workflow written (lint, typecheck, test, audit, build)
- [x] `git init`, push to GitHub (public: github.com/gharisj3/patient-intake), CI passes remotely
- [ ] Vercel project (preview deploy per PR) + Supabase project (separate dev/prod projects); apply migrations
- [x] `.env.example`, env validation with zod
- [x] DB schema v1 + migration `0001_init.sql` (multi-tenant): clinics, profiles, doctors, patients, services, doctor_services, doctor_schedules, time_off, appointments (4 types, queue tokens), invoices, invoice_items, agent_sessions, agent_messages, consents, queue_counters, audit_log
- [x] RLS policies on every table + 24 passing tests (PGlite)
- [x] DB constraint preventing overlapping appointments per doctor
- [x] Seed script with fake data; brand tokens; baseline security headers
- [ ] Create demo auth users/profiles script (needs a real Supabase project)
- [x] CI hardening: gitleaks, CodeQL, Dependabot, branch protection on `main`, GitHub secret scanning + push protection
- [ ] Review/merge the 2 open Dependabot PRs (actions/checkout 4->7, gitleaks-action 2->3)

## Current status (2026-10-14)
Phase 1 done locally and pushed (CI green). Phase 2 is next, awaiting user go-ahead. Remaining Phase 1 items: Vercel/Supabase projects and demo auth users (need user's Supabase project).

## Phase 2 — Public website (week 2)
- [ ] Home, About, Services, Doctors (public profile pages), Contact, Privacy Policy, Terms
- [ ] Responsive, accessible, SEO basics, fast (Lighthouse > 90)
- [ ] Demo-data banner

## Phase 3 — Manual booking (week 3)
- [ ] Availability engine: schedules − time off − existing appointments → open slots (timezone-safe)
- [ ] Booking form: service → doctor → slot → patient details → confirm
- [ ] Zod validation (client + server), Turnstile/hCaptcha, rate limiting
- [ ] Confirmation page + email (Resend) with cancel/reschedule via signed, expiring token link
- [ ] Reminder emails (cron: Supabase pg_cron or Vercel Cron)
- [ ] Unit tests for availability + booking; Playwright e2e for the happy path

## Phase 4 — Admin panel (weeks 4–5)
- [ ] Auth (Supabase Auth), **MFA required for admin/doctor roles**, role-based middleware
- [ ] Dashboard: today's appointments, counts, no-shows
- [ ] Doctors: CRUD, specialties, schedules, time off, active/inactive
- [ ] Patients: list, search, detail, appointment history
- [ ] Appointments: calendar/table, filter, confirm/cancel/reschedule/complete, manual booking by staff
- [ ] Invoices: create from appointment, line items, status (draft/sent/paid/void), PDF export, email send
- [ ] Settings: clinic info, services & prices, working hours, staff users
- [ ] Audit log viewer
- [ ] CSV export (admin only, logged)

## Phase 5 — AI booking agent, chat (weeks 6–7)
- [ ] Chat widget on the site (streaming), server route calls Claude with tool use
- [ ] Tools mapped to existing services: `get_clinic_info`, `check_availability`, `book_appointment`, `reschedule`, `cancel`
- [ ] System prompt: scope-limited receptionist; no medical advice; emergency escalation message; confirm before booking
- [ ] Guardrails: input length limits, per-session/IP rate limit, token/cost budget cap, tool args re-validated with Zod, session-scoped identity (can only touch own appointment, verified via emailed code/OTP)
- [ ] Prompt-injection defenses (see Security); no secrets or other patients' data in context
- [ ] Conversation logging with PHI redaction + retention limit; human handoff ("contact the clinic")
- [ ] Eval set: 30+ scripted conversations (happy path, edge cases, abuse, injection attempts) run in CI against the agent

## Phase 6 — Voice agent (weeks 8–9)
- [ ] Browser mic → speech-to-text → same agent → text-to-speech (Web Speech API first)
- [ ] Barge-in/interrupt, fallback to chat, clear consent notice before recording
- [ ] Decide on production voice stack (Vapi / Deepgram + ElevenLabs / OpenAI-realtime-style) and cost model; optional phone number later (Twilio)
- [ ] Don't store raw audio unless required; if stored, encrypt + retention policy

## Phase 7 — Hardening & compliance gate (weeks 10–11)
Must be done before any real patient data:
- [ ] Move to paid/compliant tiers with signed BAAs (hosting, database, email, LLM, voice, error tracking) or self-host in compliant cloud (AWS/Azure/GCP with BAA)
- [ ] Custom domain + HTTPS/HSTS, production vs staging separation
- [ ] Security review + dependency audit + external pen-test (or at least OWASP ZAP scan)
- [ ] Backups + tested restore; point-in-time recovery
- [ ] Data retention & deletion policy, patient data export/delete requests
- [ ] Privacy policy, terms, consent text reviewed by a lawyer; breach response runbook
- [ ] Load test, uptime monitoring, alerting, status page
- [ ] Staff training + access review

## Phase 8 — Launch & iterate
- [ ] Soft launch with one clinic, real data, close monitoring
- [ ] Payments (Stripe), insurance info, patient portal (view/manage appointments, forms), pre-visit intake questionnaires, SMS reminders (Twilio), calendar sync (Google Calendar), multi-clinic support, analytics

---

## Security & safety plan

### Application security
- **AuthN**: Supabase Auth; admin/doctor accounts require MFA; strong password policy; short session lifetime; lockout/rate limit on login; no shared accounts.
- **AuthZ**: role checks server-side on every route + Postgres RLS as second line of defense. Default deny. Admin panel is a separate route group behind middleware; consider a separate subdomain (`admin.`) later.
- **Input**: Zod validation on all inputs, parameterized queries only (ORM), output encoding (React default), file uploads restricted by type/size and scanned.
- **Web hardening**: CSP, HSTS, `X-Content-Type-Options`, `Referrer-Policy`, `frame-ancestors 'none'`, secure/HttpOnly/SameSite cookies, CSRF protection on mutations, strict CORS.
- **Abuse**: rate limiting (Upstash) on booking, chat, login, OTP; Turnstile/hCaptcha; per-IP and per-session quotas; cost cap on LLM tokens.
- **Secrets**: env vars only, rotated, never in client bundles or git; use secret scanning (GitHub push protection) and pre-commit hook (gitleaks).
- **Supply chain**: lockfile, Dependabot/Renovate, `npm audit` in CI, pin GitHub Actions.
- **Double booking / race conditions**: DB exclusion constraint + transactions.

### Data protection (PHI/PII)
- Encryption in transit (TLS) and at rest (Supabase default); column-level encryption for highly sensitive fields if added later.
- Data minimization: collect only what's needed for scheduling.
- Never log PHI; redact in logs, Sentry (`beforeSend` scrubbing), and agent transcripts.
- Audit log for admin access to patient data; admin read access is justified and reviewable.
- Retention and deletion policy; backups encrypted; restore tested.
- Dev/test uses synthetic data only; prod data never copied to dev.

### AI agent safety
- **Narrow tools, least privilege**: agent calls only whitelisted tools, each re-validated and authorized server-side; it has no direct DB access and no admin tools.
- **Identity binding**: agent can act only on the verified session's patient (email/SMS OTP before viewing/changing existing appointments). Never reveal whether another person has an appointment.
- **Prompt injection**: treat all user and retrieved text as untrusted; system prompt isolated; tool outputs are data not instructions; no secrets in context; confirm before any write.
- **No medical advice**: refuse diagnosis/treatment; show emergency message for red-flag phrases; hand off to human.
- **Hallucination control**: clinic info (hours, services, prices) comes from DB via tools, not model memory.
- **Cost/DoS control**: max message length, max turns per session, token budget, rate limits.
- **Transparency**: disclose it's an AI assistant; voice recording consent notice.
- **Evals** run in CI to catch regressions in refusals, injection resistance, correct booking.

### Operations
- Sentry (scrubbed), uptime monitor, Vercel/Supabase logs, alerts on error spikes and auth anomalies.
- Branch protection, PR review, CI required, separate staging and prod environments.
- Incident/breach response runbook; documented backup & restore.

---

## Free-tier stack cheat sheet
| Need | Service | Free-tier note |
|---|---|---|
| App hosting | Vercel Hobby | non-commercial only; fine for demo |
| DB/Auth/Storage | Supabase Free | pauses after inactivity; no BAA |
| Email | Resend | ~3k/month free |
| Rate limit | Upstash Redis | free tier sufficient |
| Errors | Sentry | free developer plan |
| Bot protection | Cloudflare Turnstile | free |
| LLM | Claude API | pay per use; set a spending cap |
| CI | GitHub Actions | free minutes |

## Definition of "production ready"
Phase 7 gate complete, BAAs signed where PHI flows, monitoring and backups proven, pen-test findings fixed, legal documents reviewed, and the agent eval suite passing.
