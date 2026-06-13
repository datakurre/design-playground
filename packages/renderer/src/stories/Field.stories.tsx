import type { Meta, StoryObj } from "@storybook/react";
import { expect, within } from "@storybook/test";
import { RenderNode } from "../RenderNode.js";
import type { Field } from "@design-playground/ui-ir";

/**
 * Field — a labelled form control. Every field has a visible, programmatically
 * associated label (WCAG 3.3.2); placeholders are never used as labels.
 * Personal-data fields declare an autocomplete purpose (WCAG 1.3.5).
 */
type InputType = Field["inputType"];

interface FieldArgs {
  label: string;
  name: string;
  inputType: InputType;
  required: boolean;
  autocomplete: string;
  help: string;
}

const meta: Meta<FieldArgs> = {
  title: "Components/Field",
  tags: ["autodocs"],
  argTypes: {
    inputType: {
      control: "select",
      options: ["text", "email", "password", "number", "tel", "checkbox", "select", "textarea"],
    },
    required: { control: "boolean" },
    autocomplete: { control: "text", description: "WHATWG autofill token (WCAG 1.3.5)." },
    help: { control: "text" },
  },
  args: {
    label: "Email address",
    name: "email",
    inputType: "email",
    required: true,
    autocomplete: "email",
    help: "",
  },
  render: (a) => {
    const node: Field = {
      type: "Field",
      name: a.name,
      label: a.label,
      inputType: a.inputType,
      required: a.required,
      autocomplete: a.autocomplete || undefined,
      help: a.help || undefined,
      options:
        a.inputType === "select"
          ? [
              { value: "free", label: "Free" },
              { value: "pro", label: "Pro" },
            ]
          : undefined,
    };
    return <RenderNode node={node} />;
  },
};
export default meta;
type Story = StoryObj<FieldArgs>;

export const Text: Story = {
  args: { label: "Full name", name: "name", inputType: "text", autocomplete: "name" },
};
export const Email: Story = {};
export const Password: Story = {
  args: { label: "Password", name: "password", inputType: "password", autocomplete: "new-password" },
};
export const Select: Story = {
  args: { label: "Plan", name: "plan", inputType: "select", required: false, autocomplete: "" },
};
export const Checkbox: Story = {
  args: {
    label: "Email me product updates",
    name: "marketing",
    inputType: "checkbox",
    required: false,
    autocomplete: "",
  },
};
export const WithHelp: Story = {
  args: { help: "We'll send a verification link to this address." },
};

/** Interaction test: the label is programmatically associated with the control. */
export const LabelAssociation: Story = {
  name: "Test · label association",
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const input = canvas.getByLabelText("Email address", { exact: false });
    await expect(input).toBeInTheDocument();
    await expect(input).toBeRequired();
  },
};
