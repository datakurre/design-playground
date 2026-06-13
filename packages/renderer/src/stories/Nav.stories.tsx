import type { Meta, StoryObj } from "@storybook/react";
import { RenderNode } from "../RenderNode.js";

/**
 * Nav — top-level navigation between sections of a flow. The current item
 * is marked with `aria-current="page"`.
 */
const meta: Meta = {
  title: "Components/Nav",
  tags: ["autodocs"],
  render: () => (
    <RenderNode
      node={{
        type: "Nav",
        items: [
          { label: "Profile", action: { kind: "navigate", target: "profile" }, current: true },
          { label: "Security", action: { kind: "navigate", target: "security" } },
          { label: "Billing", action: { kind: "navigate", target: "billing" } },
        ],
      }}
    />
  ),
};
export default meta;
type Story = StoryObj;

export const Default: Story = {};
