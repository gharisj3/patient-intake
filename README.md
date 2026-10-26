# Patient Intake Foundation

Foundation-stage multi-clinic intake project using Next.js, TypeScript and Supabase-style PostgreSQL policies. Synthetic/demo data only.

## Current status

- Implemented: database schema and migration, tenant/role RLS policies, appointment-overlap constraint, synthetic seed data, environment validation, brand tokens and a placeholder homepage.
- Not implemented: public clinic website, availability engine, booking form, staff dashboard, patient authentication flow, chat booking agent and voice agent. These are planned in [ROADMAP.md](ROADMAP.md).
- Tests: `tests/db/schema.test.ts` exercises the schema and policies with PGlite. These tests do not demonstrate a complete booking product or a deployed Supabase environment.
- External services: no live LLM booking integration is implemented. Vercel/Supabase project setup and real operational verification remain deployment work.

## Local development

Requires Node.js 24 and npm.

```sh
npm ci
cp .env.example .env.local
npm run dev
```

Set the environment values for your own development project. Open http://localhost:3000 for the foundation placeholder page.

## Local verification

```sh
npm run lint
npm run typecheck
npm test
npm run build
```

GitHub Actions is disabled for this maintenance work. Run checks locally; do not infer that old workflow files or badges establish current verification.

Use synthetic data only. Production readiness, privacy/compliance review, real infrastructure, operational controls and agent evaluations remain future work. See the roadmap for scope and gates.
