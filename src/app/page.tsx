import { brand } from "@/config/brand";

// Placeholder. The real public website is built in Phase 2.
export default function Home() {
  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col justify-center gap-4 px-4 py-16">
      <p className="w-fit rounded-full border border-border bg-card px-3 py-1 text-sm text-muted">
        {brand.demoNotice}
      </p>
      <h1 className="text-4xl font-semibold tracking-tight text-brand">{brand.name}</h1>
      <p className="text-lg text-muted">{brand.tagline}</p>
      <p className="text-sm text-muted">
        Phase 1 foundation is in place. The website and booking come next.
      </p>
    </main>
  );
}
