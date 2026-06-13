import type { Meta, StoryObj } from "@storybook/react";
import { expect, within } from "@storybook/test";
import { DialogView } from "../RenderNode.js";
import type { Dialog } from "@design-playground/ui-ir";

/**
 * Dialog — a modal confirmation. Destructive dialogs must use a `danger`
 * confirm variant (machine-checked: `destructive-dialog-shape`) and are
 * what guards every danger button on a screen.
 */
interface DialogArgs {
  title: string;
  body: string;
  confirmLabel: string;
  cancelLabel: string;
  destructive: boolean;
}

const meta: Meta<DialogArgs> = {
  title: "Components/Dialog",
  tags: ["autodocs"],
  args: {
    title: "Delete account?",
    body: "This permanently removes your account and all associated data.",
    confirmLabel: "Delete my account",
    cancelLabel: "Keep my account",
    destructive: true,
  },
  render: (a) => {
    const node: Dialog = {
      type: "Dialog",
      id: "confirm",
      title: a.title,
      destructive: a.destructive,
      confirmLabel: a.confirmLabel,
      cancelLabel: a.cancelLabel,
      confirmVariant: a.destructive ? "danger" : "primary",
      children: [{ type: "Text", value: a.body, role: "body" }],
    };
    return <DialogView node={node} />;
  },
};
export default meta;
type Story = StoryObj<DialogArgs>;

export const DestructiveConfirm: Story = {};

export const NeutralConfirm: Story = {
  args: {
    title: "Discard changes?",
    body: "Your unsaved edits will be lost.",
    confirmLabel: "Discard",
    cancelLabel: "Keep editing",
    destructive: false,
  },
};

/** Interaction test: destructive dialog exposes a danger-styled confirm action. */
export const DangerShape: Story = {
  name: "Test · destructive shape",
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const dialog = canvas.getByRole("dialog");
    await expect(dialog).toHaveAttribute("aria-modal", "true");
    const confirm = canvas.getByRole("button", { name: "Delete my account" });
    await expect(confirm).toHaveAttribute("data-variant", "danger");
    await expect(canvas.getByRole("button", { name: "Keep my account" })).toBeInTheDocument();
  },
};
