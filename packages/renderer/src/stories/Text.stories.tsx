import type { Meta, StoryObj } from "@storybook/react";
import { RenderNode } from "../RenderNode.js";
import type { Text } from "@design-playground/ui-ir";

/**
 * Text — typographic content. The `role` chooses the semantic element and
 * styling (headings, body, caption, error), keeping the vocabulary closed
 * and consistent with the design tokens.
 */
interface TextArgs {
  value: string;
  role: NonNullable<Text["role"]>;
  level: number;
}

const meta: Meta<TextArgs> = {
  title: "Components/Text",
  tags: ["autodocs"],
  argTypes: {
    role: { control: "inline-radio", options: ["heading", "subheading", "body", "caption", "error"] },
    level: { control: { type: "range", min: 1, max: 6, step: 1 } },
  },
  args: { value: "Create your account", role: "heading", level: 1 },
  render: (a) => (
    <RenderNode node={{ type: "Text", value: a.value, role: a.role, level: a.level }} />
  ),
};
export default meta;
type Story = StoryObj<TextArgs>;

export const Heading: Story = {};
export const Subheading: Story = { args: { value: "Tell us about yourself", role: "subheading" } };
export const Body: Story = {
  args: { value: "We use this information only to personalise your experience.", role: "body" },
};
export const Caption: Story = { args: { value: "Step 1 of 3", role: "caption" } };
export const Error: Story = { args: { value: "Enter a valid email address.", role: "error" } };
