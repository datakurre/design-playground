import type { Meta, StoryObj } from "@storybook/react";
import { expect, within } from "@storybook/test";
import { ScreenRenderer } from "../ScreenRenderer.js";
import type { Screen } from "@design-playground/ui-ir";
import invalidSemantics from "../../../../ui-ir/examples/invalid-semantics.json";

/**
 * Screens — the agent-generated, end-to-end results. Each story renders a
 * committed scenario AST through the SAME validating `ScreenRenderer` the
 * app ships: every AST is structurally + semantically validated before it
 * is drawn, and an invalid plan renders a rejection panel instead of UI.
 * This is where design and product teams browse and visually approve the
 * real generated screens.
 *
 * Scenario ASTs are produced by `pnpm pipeline`; run it (or `pnpm
 * scenarios`) before `pnpm storybook` so the latest screens appear.
 */
const scenarioModules = import.meta.glob("../../../../scenarios/*/ast.json", { eager: true }) as Record<
  string,
  { default: Screen[] }
>;

function screensFor(id: string): Screen[] {
  return scenarioModules[`../../../../scenarios/${id}/ast.json`]?.default ?? [];
}

function ScenarioView({ id }: { id: string }) {
  const screens = screensFor(id);
  if (screens.length === 0) {
    return (
      <div className="sb-stage">
        <p>
          No generated AST for <code>{id}</code> yet — run <code>pnpm pipeline</code> first.
        </p>
      </div>
    );
  }
  return (
    <div className="dp-stage" style={{ display: "grid", gap: "var(--spacing-xl, 32px)" }}>
      {screens.map((screen, i) => (
        <ScreenRenderer key={i} ast={screen} />
      ))}
    </div>
  );
}

const meta: Meta<{ id: string }> = {
  title: "Screens/Generated",
  parameters: { layout: "fullscreen" },
  render: (a) => <ScenarioView id={a.id} />,
};
export default meta;
type Story = StoryObj<{ id: string }>;

export const Onboarding: Story = { args: { id: "onboarding" } };
export const Checkout: Story = { args: { id: "checkout" } };
export const SubscriptionUpgrade: Story = { args: { id: "subscription-upgrade" } };
export const AccountSettings: Story = {
  args: { id: "account-settings" },
  play: async ({ canvasElement }) => {
    // The destructive flow renders its danger zone and confirmation dialog.
    const canvas = within(canvasElement);
    await expect(canvas.getAllByRole("dialog").length).toBeGreaterThan(0);
  },
};
export const PasswordReset: Story = { args: { id: "password-reset" } };

/**
 * A deliberately rule-violating AST. The renderer refuses to draw it and
 * shows the rejection panel listing the violations — invalid plans never
 * reach the user.
 */
export const RejectedPlan: StoryObj = {
  parameters: { layout: "fullscreen" },
  render: () => (
    <div className="dp-stage">
      <ScreenRenderer ast={invalidSemantics} />
    </div>
  ),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByText(/AST rejected/i)).toBeInTheDocument();
  },
};
