/** Default brand for the demo. Each clinic can override via `clinics.brand` (jsonb). */
export const brand = {
  name: "CareDesk",
  tagline: "Book care in minutes, not phone calls.",
  demoNotice: "Demo environment. Do not enter real health information.",
  colors: {
    primary: "#0f766e",
    accent: "#f0654f",
    ink: "#0f1f1d",
    surface: "#f4f9f8",
  },
} as const;

export type Brand = typeof brand;
