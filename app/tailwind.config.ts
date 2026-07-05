import type { Config } from "tailwindcss";
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "var(--ink)",
        "ink-soft": "var(--ink-soft)",
        "ink-faint": "var(--ink-faint)",
        bg: "var(--bg)",
        surface: "var(--surface)",
        "surface-2": "var(--surface-2)",
        line: "var(--line)",
        brass: "var(--brass)",
        "brass-dark": "var(--brass-dark)",
        "brass-2": "var(--brass-2)",
        "hero-bg": "var(--hero-bg)",
        "hero-bg-2": "var(--hero-bg-2)",
        clay: "var(--clay)",
        "sb-bg": "var(--sb-bg)",
        "sb-bg-2": "var(--sb-bg-2)",
        "sb-text": "var(--sb-text)",
        mint: "var(--mint)",
        alert: "var(--alert)",
        amber: "var(--amber)",
      },
      borderRadius: {
        DEFAULT: "8px",
        lg: "14px",
        xl: "20px",
        hero: "22px",
      },
      fontFamily: {
        sans: ["Segoe UI", "system-ui", "sans-serif"],
      },
    },
  },
  plugins: [],
} satisfies Config;
