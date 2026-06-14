/**
 * Global token "themes" for the Storybook toolbar. Selecting one applies a
 * small set of CSS-variable overrides to EVERY story, demonstrating how a
 * change at the token layer ripples through every component and screen with
 * no per-component edits. Each theme is just a patch over the generated
 * design-token custom properties.
 */
export interface TokenTheme {
  id: string;
  label: string;
  vars: Record<string, string>;
}

export const TOKEN_THEMES: TokenTheme[] = [
  { id: "base", label: "Base (default)", vars: {} },
  {
    id: "emerald",
    label: "Brand · Emerald",
    vars: {
      "--color-brand-primary": "#10b981",
      "--color-brand-primary-hover": "#059669",
      "--color-border-focus": "#10b981",
    },
  },
  {
    id: "crimson",
    label: "Brand · Crimson",
    vars: {
      "--color-brand-primary": "#e11d48",
      "--color-brand-primary-hover": "#be123c",
      "--color-border-focus": "#e11d48",
    },
  },
  {
    id: "rounded",
    label: "Shape · Rounded",
    vars: {
      "--radius-sm": "0.5rem",
      "--radius-md": "0.875rem",
      "--radius-lg": "1.25rem",
    },
  },
  {
    id: "compact",
    label: "Density · Compact",
    vars: {
      "--space-2": "0.375rem",
      "--space-3": "0.5rem",
      "--space-4": "0.625rem",
      "--space-6": "1rem",
      "--space-8": "1.25rem",
    },
  },
  {
    id: "serif",
    label: "Type · Serif",
    vars: { "--font-family-base": "Georgia, 'Times New Roman', serif" },
  },
];

export function themeVars(id: string | undefined): Record<string, string> {
  return TOKEN_THEMES.find((t) => t.id === id)?.vars ?? {};
}
