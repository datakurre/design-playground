import type { Meta, StoryObj } from "@storybook/react";
import { expect, userEvent, within } from "@storybook/test";
import { TokenPlayground } from "./TokenPlayground.js";
import { ALL_TOKENS, CATEGORY_ORDER, TOKEN_GROUPS, cssVarName, cssValue } from "./token-index.js";

/**
 * Foundations/Design Tokens — the interactive playground plus a static
 * catalogue. The playground replaces the old swatch-only viewer: it folds
 * the catalogue in (see the "Catalogue" story) and adds live, cross-phase
 * editing.
 */
const meta: Meta<typeof TokenPlayground> = {
  title: "Foundations/Design Tokens",
  component: TokenPlayground,
  // In-canvas controls (works on the static site without the Controls panel)
  // and opt out of the global token-theme toolbar so the playground manages
  // its own original-vs-edited overrides.
  parameters: { layout: "fullscreen", options: { showPanel: false }, tokenThemeable: false },
};
export default meta;
type Story = StoryObj<typeof TokenPlayground>;

export const Playground: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);

    // Picker is present and seeded at the brand primary color.
    const select = canvas.getByLabelText("Token") as HTMLSelectElement;
    await expect(select.value).toBe("color.brand.primary");

    // Phase 2 bindings table lists the button/primary binding.
    await expect(canvas.getByText("button")).toBeInTheDocument();

    // Editing the value cascades a CSS-variable override into the edited frame.
    const text = canvas.getByLabelText("Token value") as HTMLInputElement;
    await userEvent.clear(text);
    await userEvent.type(text, "#10b981");

    const editedFrame = canvasElement.querySelector('[data-tpg="edited"] .tpg-frame') as HTMLElement;
    await expect(editedFrame.style.getPropertyValue("--color-brand-primary")).toBe("#10b981");
  },
};

export const Radius: Story = { args: { initialPath: "radius.md" } };
export const Shadow: Story = { args: { initialPath: "shadow.overlay" } };

/** The folded-in static catalogue: every token, grouped, with a preview. */
function Catalogue() {
  return (
    <div style={{ padding: "var(--spacing-lg, 24px)", display: "grid", gap: "var(--spacing-lg, 24px)" }}>
      {CATEGORY_ORDER.filter((c) => TOKEN_GROUPS[c]).map((cat) => (
        <section key={cat}>
          <h2 style={{ textTransform: "capitalize", margin: "0 0 8px" }}>{cat}</h2>
          <div className="sb-tokens">
            {TOKEN_GROUPS[cat].map((t) => {
              const name = cssVarName(t.path);
              return (
                <div className="sb-swatch" key={t.path}>
                  {cat === "color" ? (
                    <span className="chip" style={{ background: `var(${name})` }} />
                  ) : cat === "space" ? (
                    <span className="sb-spacing-bar" style={{ width: `var(${name})` }} />
                  ) : cat === "radius" ? (
                    <span className="chip" style={{ borderRadius: `var(${name})`, background: "var(--color-brand-primary)" }} />
                  ) : (
                    <span style={{ fontFamily: name.includes("font-family") ? `var(${name})` : undefined }}>Aa</span>
                  )}
                  <code>{name}</code>
                  <span className="val">{cssValue(t)}</span>
                </div>
              );
            })}
          </div>
        </section>
      ))}
    </div>
  );
}

export const Catalogue_: Story = {
  name: "Catalogue",
  render: () => <Catalogue />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    // Every token is listed by its generated CSS variable name.
    await expect(canvas.getByText(cssVarName(ALL_TOKENS[0].path))).toBeInTheDocument();
  },
};
