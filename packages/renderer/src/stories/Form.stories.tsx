import type { Meta, StoryObj } from "@storybook/react";
import { RenderNode } from "../RenderNode.js";
import type { Field, Node } from "@design-playground/ui-ir";

/**
 * Form — a single-column collection of fields plus a primary action.
 * Forms are single-column by rule (`forms-single-column`) and should stay
 * minimal (`minimal-fields`). Validated end-to-end in the Screens section.
 */
const FIELDS: Field[] = [
  { type: "Field", name: "name", label: "Full name", inputType: "text", required: true, autocomplete: "name" },
  { type: "Field", name: "email", label: "Email address", inputType: "email", required: true, autocomplete: "email" },
  {
    type: "Field",
    name: "password",
    label: "Password",
    inputType: "password",
    required: true,
    autocomplete: "new-password",
    help: "At least 12 characters.",
  },
];

interface FormArgs {
  fieldCount: number;
  submitLabel: string;
}

const meta: Meta<FormArgs> = {
  title: "Components/Form",
  tags: ["autodocs"],
  argTypes: {
    fieldCount: { control: { type: "range", min: 1, max: 3, step: 1 } },
  },
  args: { fieldCount: 3, submitLabel: "Create account" },
  render: (a) => {
    const children: Node[] = [
      { type: "Form", id: "signup-form", columns: 1, children: FIELDS.slice(0, a.fieldCount) },
      {
        type: "Stack",
        direction: "horizontal",
        role: "actions",
        gap: "sm",
        children: [
          { type: "Button", label: a.submitLabel, variant: "primary", action: { kind: "submit", target: "signup-form" } },
        ],
      },
    ];
    return (
      <RenderNode node={{ type: "Card", role: "plain", children }} />
    );
  },
};
export default meta;
type Story = StoryObj<FormArgs>;

export const SignUp: Story = {};
export const Minimal: Story = { args: { fieldCount: 1, submitLabel: "Continue" } };
