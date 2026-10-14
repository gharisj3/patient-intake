# Build Prompts

A running log of the user's prompts and the key outcome of each, in order. Updated after every conversation turn (standing rule, see CLAUDE.md).

---

## Prompt 1 — Project kickoff (2026-10-14)

> I want to built patient Intake platform the features it will have are:
> - Website
> - Manual Booking by form
> - Agent Booking so the website would have an agent who can talk and can chat and will book the appointment for the patients
> - For the admin we need a seprate panel where we will be able to see the doctors who are with our organization. Patients who booked their appointment. Invoices and other important stuff
>
> this is my idea tell me the proper roadmap as i want to make this production ready product but for now we will deploy it for free on any hosting like vercel or any other platform tell me what we will do for the security and safety and what would be the exact road map also create claude.md
>
> also save the given prompt to build_prompts.md file

**Outcome:** Created `CLAUDE.md`, `ROADMAP.md`, `build_prompts.md`. Stack: Next.js + TS, Supabase, Vercel Hobby. 8-phase roadmap. Key caveat: free tiers are not suitable for real patient data.

## Prompt 2 — Free tiers for voice and chat APIs

> tell me about the free tier for voice api and chat api like groq

**Outcome:** Researched. Groq: free, per-org limits (~30 RPM, ~1,000 req/day on large models; sources disagree, check console). Gemini: free tier for Flash models, limits shown only in AI Studio console, free-tier data may be used by Google. Deepgram: one-time $200 credit. ElevenLabs free: ~10k chars/month. Browser Web Speech API: free.

## Prompt 3 — Gemini

> what if we use gemini api?

**Outcome:** Gemini is good for demo (tool calling, audio), but free limits are opaque/tight and free-tier data may be used for training, so fake data only. Recommended a provider-agnostic LLM adapter (Gemini/Groq in dev, BAA-covered provider in prod).

## Prompt 4 — No paid tools

> i do not want to us eleven labs or any other paid tool

**Outcome:** Decision: fully free demo stack. Voice = browser `speechSynthesis` + `SpeechRecognition`, optionally Groq Whisper for STT, optionally in-browser Kokoro/Piper TTS. No ElevenLabs/Deepgram.

## Prompt 5 — HIPAA

> is this hippa complient

**Outcome:** No. Free tiers have no BAAs, so no real PHI. Compliance also needs administrative and physical safeguards, not just tech. Real launch requires BAA-covered vendors (hosting, DB, LLM, email, voice) and legal review. Confirm the clinic's country (HIPAA vs GDPR/local law).

## Prompt 6 — Agent memory and scope restriction

> ok back to the developement tell me what we need to do for the agent memory and make it restrict to the platform only and provide the relevent information which is relevent with patient

**Outcome:** Designed 3 memory layers (conversation, booking state machine, patient memory via tools after OTP verification), layered scope restriction (prompt, whitelisted tools, DB-sourced facts, input classifier, emergency path, output check, injection handling, limits), and allowed/refused topic lists. Recorded in CLAUDE.md and ROADMAP.md.

## Prompt 7 — Returning patient after 45 days

> what agent will do if the same patient will come after 45 days to book appointment again how it will pull the information and how it will notify it to doctor

**Outcome:** Designed returning-patient flow: new session, OTP verification, server-side `get_patient_context` tool (scheduling-only summary), booking via shared service. Appointment gets `appointment_type`, `previous_appointment_id`, `booked_via`. Doctor notified via dashboard badge, email (no clinical content), realtime toast, daily digest. Recorded in CLAUDE.md.

## Prompt 8 — Keep docs updated

> after every conversation i had with u update build_prompts.md and claude.md so context should not be an issue

**Outcome:** Standing rule added: after every turn, append the prompt + outcome here and update CLAUDE.md (and ROADMAP.md when scope changes). Updated all files with decisions from prompts 1–8.

## Prompt 9 — Patient switches doctor: can the new doctor see history/prescriptions?

> what if the same patient asks for another doctor so the new doctor would be able to see the old medical history or the given prescriptions to the patient or not?

**Outcome:** Platform v1 is scheduling/intake only; clinical notes, diagnoses and prescriptions belong to an EHR and are out of scope for v1. If added later: relationship-based access via RLS (doctor must have an appointment with the patient), break-glass with reason + alert, audit log on every view, receptionist/admin no clinical notes, agent never. Agent only handles scheduling for a doctor switch and tells the patient the new doctor will have access per clinic policy. Recorded in CLAUDE.md and ROADMAP.md.

## Prompt 10 — Answers to open decisions

> Will the platform store clinical notes and prescriptions at all, or stay with scheduling and intake only? I recommend scheduling only for v1.
> Agreed
> Which country will the clinic operate in? That decides whether consent is required before sharing records between doctors.
> USA, Canada and pakistan

**Outcome:** DECIDED: v1 is scheduling + intake only (no clinical notes/prescriptions). Target countries: USA, Canada, Pakistan. Design to the strictest standard (HIPAA-grade controls) everywhere; add per-clinic `jurisdiction` setting (privacy notice, consent wording, retention, breach procedure); store consent records; choose hosting region before real data (Canada may need Canadian hosting); multi-currency invoices (USD/CAD/PKR); Stripe likely unavailable for Pakistan (verify, local gateway); email OTP default, SMS optional. Open: which country is the first clinic. Recorded in CLAUDE.md and ROADMAP.md.

## Prompt 11 — Any questions for me?

> any questions for me?

**Outcome:** Asked 11 open questions (priority: 1 first-clinic country, 2 real clinic vs demo, 3 clinic size/doctors/locations/volume; then roles, services/appointment types, invoicing/currency/payments, languages, notification channels, branding, domain/accounts, phone-number voice). Awaiting answers; update CLAUDE.md/ROADMAP.md when received.

## Prompt 12 — Ask questions one by one

> ask me questions one by one in chat

**Outcome:** Switched to asking the 11 open questions one at a time. Answers are recorded in CLAUDE.md/ROADMAP.md as they arrive (see "Discovery answers" in CLAUDE.md).

**Answers given (Q&A complete):**
1. First-clinic country / real vs demo: universal platform, testing phase, no HIPAA/PIPEDA work for now.
2. Size: multi-clinic from day one.
3. Roles: super admin, clinic admin, receptionist, doctor login, plus optional patient account (never forced to log in).
4. Visit types: in-person, phone, walk-in queue tokens, video.
5. Invoices: both manual records and online payments (online later via pluggable provider).
6. Languages: English only (i18n-ready).
7. Notifications: email + in-app/browser push.
8. Branding: Claude designs it.
9. Accounts: GitHub, Vercel, Supabase; no custom domain.
10. Voice: browser now, phone number later.

## Prompt 13 — What will you start building now?

> what you will start building now?

**Outcome:** Proposed starting Phase 1 (foundation): Next.js scaffold + CI, multi-clinic DB schema + migrations, RLS with cross-clinic tests, seed script with fake data, brand/design tokens. Asked user to confirm tenancy default (multi-tenant, isolated per clinic) and whether to wire a real Supabase project (keys in local .env only). Awaiting go-ahead.

## Prompt 14 — Tenancy answer and go-ahead

> ask question here  
> (answers via the question UI: Tenancy = Separate customers (SaaS); Start Phase 1 = Yes, start now)

**Outcome:** Tenancy decided: full multi-tenant SaaS. Built Phase 1 locally: Next.js 16 scaffold, `supabase/migrations/0001_init.sql`, `supabase/seed.sql`, PGlite-based DB tests (24 pass), brand tokens ("CareDesk"), security headers, env validation, CI workflow. Lint/typecheck/test/build/gitleaks all clean. Not yet done: git init/GitHub push, real Supabase project, demo auth users. Docs updated (CLAUDE.md commands/DB workflow/status, ROADMAP Phase 1 checklist).
