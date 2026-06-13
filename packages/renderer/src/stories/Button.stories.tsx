import type { Meta, StoryObj } from "@storybook/react";
import { expect, within } from "@storybook/test";
import { RenderNode } from "../RenderNode.js";
import type { ActionKind, ButtonVariant } from "@design-playground/ui-ir";

/**
 * Button — the single mechanism for users to commit, cancel, or navigate
 * via an explicit, declarative action. Rendered through the production
 * `RenderNode` binding, so every variant here is pixel-identical to what
 * ships. Constraints (one primary per screen, danger guarded by a dialog)
 * are enforced at the screen level — see the Screens section.
 */
const ACTION_KINDS: ActionKind[] = [
  "submit",
  "navigate",
  "open-dialog",
  "close-dialog",
  "confirm",
  "cancel",
  "skip",
];

interface ButtonArgs {
  label: string;
  variant: ButtonVariant;
  disabled: boolean;
  actionKind: ActionKind;
  actionTarget: string;
}

const meta: Meta<ButtonArgs> = {
  title: "Components/Button",
  tags: ["autodocs"],
  argTypes: {
    label: { control: "text", description: "Visible text; also the accessible name." },
    variant: { control: "inline-radio", options: ["primary", "secondary", "danger"] },
    disabled: { control: "boolean" },
    actionKind: { control: "select", options: ACTION_KINDS },
    actionTarget: { control: "text", description: "Id the action refers to (form, dialog, route)." },
  },
  args: {
    label: "Create account",
    variant: "primary",
    disabled: false,
    actionKind: "submit",
    actionTarget: "signup-form",
  },
  render: (a) => (
    <RenderNode
      node={{
        type: "Button",
        label: a.label,
        variant: a.variant,
        disabled: a.disabled,
        action: { kind: a.actionKind, target: a.actionTarget || undefined },
      }}
    />
  ),
};
export default meta;
type Story = StoryObj<ButtonArgs>;

export const Primary: Story = {};

export const Secondary: Story = {
  args: { label: "Cancel", variant: "secondary", actionKind: "cancel", actionTarget: "" },
};

export const Danger: Story = {
  args: {
    label: "Delete account",
    variant: "danger",
    actionKind: "open-dialog",
    actionTarget: "confirm-delete",
  },
};

export const Disabled: Story = { args: { disabled: true } };

/** Interaction test: the visible label IS the accessible name (WCAG 4.1.2). */
export const AccessibleName: Story = {
  name: "Test · accessible name",
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const button = canvas.getByRole("button", { name: "Create account" });
    await expect(button).toBeInTheDocument();
    await expect(button).toHaveTextContent("Create account");
  },
};
