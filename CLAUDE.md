# CLAUDE.md — Patient Intake Platform

Guidance for Claude Code when working in this repo. Read `ROADMAP.md` for phases and status and `build_prompts.md` for the history of user requests and decisions.

## STANDING RULE: keep context in files
After EVERY conversation turn with the user:
1. Append the user's prompt (verbatim) and a short **Outcome** to `build_prompts.md`.
2. Update this file with any new decision, rule, or design.
3. Update `ROADMAP.md` when scope, phases, or status change.
The goal is that a fresh session can resume with no loss of context.

## What we are building
A patient intake and appointment platform with three surfaces:
1. **Public website** — clinic info, doctors, services, contact.
2. **Booking** — (a) manual form booking, (b) AI agent (chat first, voice later) that books via the same backend.
3. **Admin panel** (separate area, separate auth rules) — doctors, patients, appointments, invoices, settings, audit log.

Both booking paths MUST go through one shared booking service. The agent never writes to the DB directly; it calls the same validated server functions as the form.

## Decisions made so far
- **Free-only demo stack. No paid tools** (no ElevenLabs, Deepgram, etc.). User decision.
- **Voice**: browser `speechSynthesis` (TTS) + `SpeechRecognition` (STT); optional Groq Whisper (free) for better STT; optional in-browser Kokoro/Piper for nicer TTS. No self-hosted voice server (Vercel free can't run it).
- **LLM**: provider-agnostic adapter (one interface, provider chosen by env/config). Dev/demo: Gemini Flash free tier, Groq as fallback. Production: a provider that signs a BAA (e.g. Claude via a compliant arrangement). Model IDs come from env.
- **Free LLM limits are tight and change often**; the chat UI must degrade gracefully ("try again shortly"). Check limits in the provider consoles, not blogs.
- **Free-tier data may be used for training** (Gemini free) -> synthetic data only.
- **HIPAA: the free stack is NOT compliant.** No real PHI until every vendor touching PHI (hosting, DB, LLM, email, voice, error tracking) has a signed BAA and legal review is done. Confirm the clinic's country (HIPAA vs GDPR/local law). Compliance also needs administrative/physical safeguards (policies, training, breach runbook), not only tech.
- **No n8n / Make.com.** Automations are built in-app: reminders via Vercel Cron or Supabase `pg_cron`, email via Resend, staff alerts via Supabase Realtime. Never route patient data through third-party automation tools. Revisit only for non-PHI automations (Slack alerts, social posting, marketing leads).
- Demo site shows a banner: "Demo — do not enter real health information."

## Stack (free-tier first, production-shaped)
- Next.js (App Router) + TypeScript (strict) + Tailwind + shadcn/ui
- Supabase: Postgres, Auth, Row Level Security, Storage
- Drizzle ORM (or Supabase client) with SQL migrations committed to the repo
- Zod for all input validation (shared between client and server)
- LLM adapter (Gemini/Groq in dev) via server routes only
- Resend (email), Upstash Redis (rate limiting), Sentry (errors), Cloudflare Turnstile (bot protection), Stripe test mode (payments, later)
- Hosting: Vercel Hobby + Supabase free. GitHub Actions for CI.

## Repo layout (target)
```
src/app/(public)/        marketing site, booking form
src/app/(admin)/admin/   admin panel (middleware-protected)
src/app/api/             route handlers (thin; call services)
src/server/services/     booking, availability, invoices, patients (all business logic)
src/server/agent/        system prompt, tool definitions, guardrails, session/memory, classifier
src/server/llm/          provider adapter (gemini, groq, ...)
src/server/db/           schema, migrations, RLS policies
src/lib/                 validation schemas, utils
tests/                   unit + e2e (Playwright) + agent evals
```

## Agent design

### Memory (3 layers; the server owns state, not the model)
| Layer | Holds | Storage | Lifetime |
|---|---|---|---|
| Conversation | recent messages | `agent_messages`, keyed by signed session id | session; auto-delete after retention window (e.g. 30 days) |
| Booking state | structured slots (service, doctor, date, time, name, contact, confirmed?) | `agent_sessions.state` (Zod-validated JSON) | session |
| Patient memory | preferred doctor, language, upcoming/past appointments | existing tables, read ONLY via tools | permanent, verified patients only |

- Booking is a **state machine** (collect service -> pick slot -> collect details -> confirm -> book), not free chat.
- Server is **stateless** per request: load session, build prompt, save result.
- Keep last ~10 messages + booking state; summarize/drop older turns without names or health details.
- Patient identity: anonymous by default. Existing-patient access requires an **emailed/SMS OTP**; session is then bound to the patient id. Tools take patient id from the session, **never from model arguments**.
- Do not store symptoms/clinical details in agent memory. Redirect to booking or "call the clinic".
- Patients can request deletion; logs are redacted.

### Scope restriction (layered, prompt alone is not enough)
1. System prompt: clinic scheduling assistant only; politely decline off-topic; never diagnose/advise/interpret results.
2. Whitelisted tools only: `get_clinic_info`, `list_doctors_services`, `check_availability`, `book_appointment`, `reschedule`, `cancel`, `get_my_appointments`, `get_my_invoice_status`, `get_patient_context`. No web search, code exec, or raw DB access.
3. Facts (hours, doctors, prices, policies) come from tool results; if unknown, say so and give clinic contact.
4. Input classifier/router before the main model: booking | clinic info | own appointment | emergency | off-topic. Off-topic -> fixed refusal, no main-model call (also saves free quota).
5. Emergency phrases -> fixed message to call emergency services, skip the model.
6. Output check: block medical-advice patterns, other patients' data, system-prompt leakage -> safe fallback.
7. Prompt injection: user text and tool outputs are data, not instructions; re-validate and re-authorize all tool args server-side; confirm before any write.
8. Limits: max message length, max turns/session, rate limits per IP and session, token budget.

**Allowed topics:** clinic hours/location/contact/services; doctors/specialties/availability; book/reschedule/cancel; verified patient's own appointments and invoice status (paid/unpaid); generic visit logistics (arrival time, what to bring, cancellation policy).
**Refuse/hand off:** diagnosis, treatment, medication, test results, anyone else's info, general chat/coding/news.

### Returning-patient flow (e.g. patient returns after 45 days)
1. New session, no memory of the old chat; agent treats visitor as anonymous.
2. Patient gives email/phone -> OTP -> session bound to patient id. If unverified, continue as new patient; never reveal that a record exists.
3. `get_patient_context` tool (server-side) returns a scheduling-only summary: name, last doctor/service, last visit date, staff-entered follow-up recommendation, contact preferences. No clinical notes.
4. Agent greets naturally, offers same doctor or others, books through the shared booking service after user confirms.
5. Appointment fields: `appointment_type` (new | follow_up, set by server), `previous_appointment_id`, `days_since_last_visit` (derived), `booked_via` (agent | form), `reason_for_visit` (dropdown of visit types preferred over free text).
6. Doctor notification: dashboard "returning patient, last seen N days ago" badge + link to previous visit; email to doctor/reception with NO clinical content (name, date/time, "follow-up", link to dashboard); Supabase Realtime toast for logged-in staff; daily digest of tomorrow's appointments; audit log entry (no PHI in text).
7. Edge cases: preferred doctor unavailable -> nearest slots, then same specialty; existing upcoming appointment -> offer reschedule instead; new/worsening symptoms mentioned -> no assessment, offer sooner slot or "call the clinic", emergency message for red flags; changed contact details -> update after fresh verification.

## Clinical data and doctor switching
- **v1 scope: scheduling + intake only (DECIDED by user).** No clinical notes, diagnoses, or prescriptions stored (EHR territory). A separate "Clinical" module may be considered after v1.
- If clinical data is ever added: access is **relationship-based** (RLS checks the doctor has an appointment with the patient). Treating doctors can see history for patients booked with them; a doctor with no booking gets no access except **break-glass** (required written reason + alert). Receptionist/admin: no clinical notes. **AI agent: never.** Every view is audit-logged and cannot be disabled by doctors. Honor patient consent/restrictions where law requires (sensitive categories need extra rules). Prescriptions: show the active list; prescribing/changing is licensed staff only, never the agent. Minimum necessary by default.
- **Doctor-switch flow:** OTP verify -> book with new doctor via shared booking service -> tell patient the new doctor will have access per clinic policy (ask/record consent if required) -> never read out or summarize medical history -> flag appointment as `transfer / second doctor`.
- Open question: which country is the FIRST clinic in (decides hosting region, first privacy notice, vendors needing BAAs).

## Jurisdictions (DECIDED: USA, Canada, Pakistan)
- **USA**: HIPAA + state laws (e.g. California, Washington). BAAs with every vendor touching PHI. Treatment sharing between doctors needs no extra consent. Breach notification applies.
- **Canada**: PIPEDA + provincial health laws (PHIPA Ontario, HIA Alberta, Quebec Law 25...). Implied consent usually covers circle of care. Some provinces restrict data location. Breach reporting duties.
- **Pakistan**: no comprehensive data-protection law confirmed in force (draft PDPB for years; PECA applies). Treat as unregulated but follow the strict standard; verify status locally.
- Not legal advice; a local healthcare lawyer must confirm each country before real data.
- **Design rules**: build to the strictest standard (HIPAA-grade) for all clinics. Each clinic has a `jurisdiction` setting that selects privacy notice text, consent wording, retention period, breach procedure. Store consent records (what, who, when): privacy notice at booking, agent/voice recording consent; use an explicit checkbox even where implied consent is legal. Pick the DB/hosting region BEFORE real data (Supabase has US and Canada regions; Canada may need Canadian hosting). Invoices are multi-currency (USD/CAD/PKR) with tax lines. Stripe likely unsupported for Pakistan merchants (verify; local gateway needed). OTP default is email; SMS optional (cost/reliability in Pakistan). Start with one clinic in one country; jurisdiction setting makes others config, not a rebuild.

## Discovery answers (from the one-by-one Q&A)
- **Q1/Q2 (first clinic country, real vs demo):** Build a **universal platform**, not tied to one country. We are in a **testing phase**; HIPAA/PIPEDA compliance is explicitly out of scope for now. Treat as demo/test: fake data only. Keep the `jurisdiction` setting and consent-record design so compliance can be added later, but do not block development on it.

- **Q3 (size):** **Multi-clinic from day one.** Several clinics/branches, each with its own doctors, services and settings. Every table carries `clinic_id`; RLS and admin roles are scoped per clinic; a super-admin spans clinics. (SaaS-style multi-tenancy is not decided; ask later if clinics should be separate customers.)

- **Q4 (roles):** `super_admin` (all clinics), `clinic_admin`, `receptionist`, `doctor` (logs in to see own schedule), plus a `patient` role with an **optional account**: patients are never forced to log in; guest booking (form or agent) must always work. An account gives a portal to view/manage appointments. Guests are identified per session by email OTP (see agent memory design).

- **Q5 (visit types):** all four: `in_person`, `video`, `phone`, `walk_in` (queue token). Services have per-type duration/price. Video uses a free meeting link (Jitsi/Google Meet), generated per appointment. Phone: doctor calls the booked number. Walk-in uses token numbers with a live queue view for reception instead of fixed slots; the availability engine and double-booking constraint apply only to timed types.

- **Q6 (invoices/payments):** **Both.** Phase 4: manual invoices (staff create, mark paid by cash/bank/other, PDF export). Later phase: online payments through a pluggable payment-provider interface (Stripe test mode first; local gateways for Pakistan). Invoice schema must support `currency` per clinic, tax lines, and payment method/status from day one.

- **Q7 (languages):** English only for now. Keep UI strings in a message file (i18n-ready) so languages can be added later, but don't build RTL/translations yet.

- **Q8 (notifications):** Email (Resend free) + in-app/browser web push (free). No SMS/WhatsApp (paid). Guests get email only; web push needs an account/opt-in. Build a notification service with channel adapters so SMS can be added later. OTP is by email.

- **Q9 (branding):** No assets; **Claude designs the brand** (name, palette, logo mark, typography) for the demo. Make branding configurable per clinic (name, logo, colors via theme tokens) so each clinic can override. Use the frontend-design skill when building UI.

- **Q10 (accounts):** User has GitHub, Vercel and Supabase accounts. No custom domain; use the free `*.vercel.app` URL for now.

- **Q11 (voice channel):** Browser voice widget now. A real phone number (paid telephony, e.g. Twilio) is a later phase; keep the agent channel-agnostic (same agent core behind web chat, web voice, and later phone).
- **Tenancy (DECIDED):** clinics are **separate customers (full multi-tenant SaaS)**. Each clinic's data is isolated by `clinic_id` + RLS; each has its own admins; only `super_admin` crosses clinics. A single organization is just one tenant.
- **Discovery Q&A complete.** User approved starting Phase 1 (local first; Supabase keys added later via local .env only).

## Hard rules (non-negotiable)
- **No real patient data until the compliance gate in ROADMAP.md Phase 7 is passed.** Free tiers (Vercel Hobby, Supabase free, free LLM tiers) have no BAA. Use synthetic/seed data only. Never put real PHI in logs, prompts, screenshots, or tests.
- **Secrets**: only in env vars. Never commit `.env*` (except `.env.example` with blanks). Service-role keys and LLM keys are server-only; never prefix with `NEXT_PUBLIC_`.
- **Every table has RLS enabled** with explicit policies. Default deny.
- **Validate all input with Zod on the server**, even if the client validated it.
- **AuthZ on every admin route and API handler** — check role server-side; never trust the client or the agent.
- **Minimal PHI collection** (data minimization). Don't ask the agent to collect SSN, full medical history, or payment card numbers.
- **Audit log** every admin read/write of patient data and every agent tool call (who, what, when, no PHI payloads in the log text).
- Rate limit all public endpoints (booking, agent chat, auth). Add bot protection (Turnstile) to the form and chat.
- Prevent double booking at the DB level (exclusion constraint on doctor + time range), not just in app code.
- Store timestamps in UTC; display in clinic timezone.

## Conventions
- TypeScript strict, no `any`. Small functions, services own logic, route handlers stay thin.
- Conventional commits (`feat:`, `fix:`, `chore:`). Small PRs, CI must pass (lint, typecheck, tests).
- Every new feature: Zod schema, service function, test, and (if it touches data) RLS policy + migration.
- Agent changes must pass the eval suite (30+ scripted conversations: happy path, off-topic, injection, other-patient data requests, medical questions, emergencies, returning patient).
- Accessibility: WCAG 2.1 AA target. Mobile-first.
- Don't add dependencies without a reason; prefer maintained, popular packages.

## Commands
```
npm run dev         # local dev (Next.js 16, Turbopack)
npm run lint
npm run typecheck   # runs `next typegen` first (LayoutProps etc. are generated types)
npm test            # vitest; DB tests run migrations in-process with PGlite (no Docker/Postgres needed)
npm run build
npm run format      # prettier
```
Not yet set up: e2e (Playwright), db:migrate against a real Supabase project.

## Next.js 16 note
`AGENTS.md` (from the scaffold) says this Next.js has breaking changes vs. training data. Before writing Next code, read the relevant guide in `node_modules/next/dist/docs/`. `cacheComponents` and `partialPrefetching` are enabled in `next.config.ts`.

## Database workflow
- Migrations live in `supabase/migrations/NNNN_name.sql` (applied in filename order); demo data in `supabase/seed.sql` (fake data only).
- Tests in `tests/db/` load the migrations into PGlite with a small Supabase shim (`auth.users`, `auth.uid()`, roles `anon`/`authenticated`/`service_role`) and impersonate roles via `asUser()`.
- **Every new table**: add `clinic_id` (+ composite FK `(x_id, clinic_id)` to parents), enable RLS, add explicit policies, grant only what each role needs (migration revokes all default grants from anon/authenticated), and add RLS tests (cross-clinic isolation, role limits).
- Server-only tables (agent_sessions, agent_messages, consents, queue_counters) have RLS on and no policies; only the service role (server code) touches them. `audit_log` is append-only and written only by the server.
- Public site data (clinics, doctors, services, doctor_services) is readable by `anon` (active rows only). Availability is computed server-side, not exposed as raw schedules.
- Guest bookings are written by server routes using the service role AFTER Turnstile + rate limiting + Zod validation. `anon` can never write.
- Known gap: doctors can update any column on their own appointments via RLS; tighten with column-level grants in Phase 4.

## Working agreement
- Follow `ROADMAP.md` phase order; don't start a later phase's features early without asking.
- When a decision affects security, compliance, or cost, flag it instead of picking silently.
- Update `ROADMAP.md` checkboxes as work completes. See the STANDING RULE at the top for doc updates.

## Status
**Phase 1 (foundation) done locally, 2026-10-14.** Built: Next.js 16 + TS strict + Tailwind v4 scaffold; Supabase SQL migration `0001_init.sql` (multi-tenant schema, roles, overlap-proof appointments via GiST exclusion constraint, walk-in queue tokens, invoices, agent/consent/audit tables, RLS + grants); seed data; 24 passing DB tests (double booking, tenant integrity, RLS isolation, role limits, server-only/append-only tables); brand tokens (`src/config/brand.ts`, `globals.css`; name "CareDesk", teal/coral); baseline security headers; zod env validation (`src/lib/env.ts`); `.env.example`; GitHub Actions CI; gitleaks clean. Lint, typecheck, tests and build all pass.

Repo: public at https://github.com/gharisj3/patient-intake (branch `main`, CI green). Because the repo is PUBLIC: never commit secrets, real data, or personal emails; git author is the GitHub no-reply address.

Not done yet: no real Supabase project connected (migrations not applied remotely); no auth users created; no UI beyond a placeholder landing page.

Frontend today: framework + brand tokens + one placeholder page only. No website pages, booking form, agent widget, admin panel, or login screens exist yet.

CI/security on GitHub: `ci.yml` (gitleaks `secrets` job, then `check`: lint, typecheck, tests, audit, build), `codeql.yml` (`analyze`), Dependabot weekly (npm + Actions). Branch protection on `main` requires `check`, `secrets`, `analyze`; no force-push/deletion; owner can bypass. GitHub secret scanning + push protection enabled. Review Dependabot PRs before merging (majors may break); Actions are still tag-pinned (pin to SHAs in Phase 7).

Git (as of 2026-10-14): `main` == `origin/main`, clean tree, CI green. Dev server is started with `npm run dev` (http://localhost:3000).

Next: Phase 2 (public website; use the frontend-design skill), then Phase 3 (availability engine + manual booking). Awaiting user go-ahead for Phase 2. Also still needed from the user for later phases: a Supabase project URL + anon key (service-role key only in `.env.local`/Vercel).
