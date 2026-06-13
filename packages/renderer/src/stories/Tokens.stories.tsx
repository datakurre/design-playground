import type { Meta, StoryObj } from "@storybook/react";
import tokensCss from "../../../../tokens/css/variables.css?raw";

/**
 * Design tokens — the W3C DTCG source of truth, generated into CSS custom
 * properties (`pnpm build:tokens`). Every component in this Storybook is
 * styled exclusively from these variables, so this page is the canonical
 * palette teams approve against.
 */
interface Tok {
  name: string;
  value: string;
}

function parseTokens(): Tok[] {
  const out: Tok[] = [];
  for (const line of tokensCss.split("\n")) {
    const m = line.match(/^\s*(--[\w-]+):\s*([^;]+);/);
    if (m) out.push({ name: m[1], value: m[2].trim() });
  }
  return out;
}

const ALL = parseTokens();
const byPrefix = (p: string) => ALL.filter((t) => t.name.startsWith(p));

function Swatches({ tokens, kind }: { tokens: Tok[]; kind: "color" | "value" | "space" | "radius" }) {
  return (
    <div className="sb-tokens">
      {tokens.map((t) => (
        <div className="sb-swatch" key={t.name}>
          {kind === "color" ? (
            <span className="chip" style={{ background: `var(${t.name})` }} />
          ) : kind === "space" ? (
            <span className="sb-spacing-bar" style={{ width: `var(${t.name})` }} />
          ) : kind === "radius" ? (
            <span
              className="chip"
              style={{ borderRadius: `var(${t.name})`, background: "var(--color-brand-primary)" }}
            />
          ) : (
            <span style={{ fontFamily: t.name.includes("font-family") ? `var(${t.name})` : undefined }}>Aa</span>
          )}
          <code>{t.name}</code>
          <span className="val">{t.value}</span>
        </div>
      ))}
    </div>
  );
}

const meta: Meta = {
  title: "Foundations/Design Tokens",
  parameters: { layout: "padded", options: { showPanel: false } },
};
export default meta;
type Story = StoryObj;

export const Colors: Story = { render: () => <Swatches kind="color" tokens={byPrefix("--color-")} /> };
export const Spacing: Story = { render: () => <Swatches kind="space" tokens={byPrefix("--space-")} /> };
export const Radius: Story = { render: () => <Swatches kind="radius" tokens={byPrefix("--radius-")} /> };
export const Typography: Story = {
  render: () => (
    <Swatches
      kind="value"
      tokens={[...byPrefix("--font-"), ...byPrefix("--shadow-")]}
    />
  ),
};
