import type { Meta, StoryObj } from "@storybook/react";
import { RenderNode } from "../RenderNode.js";
import type { Card } from "@design-playground/ui-ir";

/**
 * Card — a grouping surface. The `summary` role is used for cost/order
 * recaps before a commit; the `danger-zone` role visually isolates
 * destructive actions, which the design rules require.
 */
interface CardArgs {
  title: string;
  role: NonNullable<Card["role"]>;
  body: string;
}

const meta: Meta<CardArgs> = {
  title: "Components/Card",
  tags: ["autodocs"],
  argTypes: {
    role: { control: "inline-radio", options: ["plain", "summary", "danger-zone"] },
  },
  args: { title: "Order summary", role: "summary", body: "Pro plan — $12.00 / month" },
  render: (a) => (
    <RenderNode
      node={{
        type: "Card",
        title: a.title || undefined,
        role: a.role,
        children: [{ type: "Text", value: a.body, role: "body" }],
      }}
    />
  ),
};
export default meta;
type Story = StoryObj<CardArgs>;

export const Plain: Story = {
  args: { title: "Profile", role: "plain", body: "Manage your personal details." },
};
export const Summary: Story = {};
export const DangerZone: Story = {
  args: {
    title: "Danger zone",
    role: "danger-zone",
    body: "Deleting your account is permanent and cannot be undone.",
  },
};
