/**
 * Pure planning logic: turn one flow step (as returned by the design
 * server's get_flow) into a UI AST Screen, honouring the design rules
 * by construction. This function performs no IO - it is deterministic
 * and unit-testable. Rule-driven decisions are recorded in `notes` so
 * the planner can cite them in the decision trace.
 */
import type { Screen, Node, Field, Dialog } from "@design-playground/ui-ir";

export interface FlowField {
  name: string;
  label: string;
  variant: string;
  required?: boolean;
  autocomplete?: string;
  help?: string;
  options?: string[];
}

export interface FlowStep {
  id: string;
  title: string;
  description?: string;
  components: string[];
  fields?: FlowField[];
  summary?: string[];
  submitLabel: string;
  ruleTags: string[];
}

export interface FlowMeta {
  id: string;
  goal: string;
}

const INPUT_TYPES = new Set(["text", "email", "password", "number", "tel", "checkbox", "select", "textarea"]);

function inputType(variant: string): Field["inputType"] {
  return (INPUT_TYPES.has(variant) ? variant : "text") as Field["inputType"];
}

function slug(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "option";
}

function inferAutocomplete(field: FlowField): string | undefined {
  if (field.autocomplete) return field.autocomplete;
  if (field.variant === "email") return "email";
  if (field.variant === "tel") return "tel";
  return undefined;
}

function fieldNode(field: FlowField): Field {
  const node: Field = {
    type: "Field",
    name: field.name,
    label: field.label,
    inputType: inputType(field.variant),
    required: field.required ?? false,
  };
  const ac = inferAutocomplete(field);
  if (ac) node.autocomplete = ac;
  if (field.help) node.help = field.help;
  if (field.options) node.options = field.options.map((o) => ({ value: slug(o), label: o }));
  return node;
}

export interface BuildResult {
  screen: Screen;
  notes: string[];
}

export function buildScreen(flow: FlowMeta, step: FlowStep): BuildResult {
  const tags = new Set(step.ruleTags);
  const notes: string[] = [];
  const children: Node[] = [];
  const dialogs: Dialog[] = [];
  const formId = `${step.id}-form`;

  // Cost/recurring transparency: a summary must precede a commitment.
  if (step.summary && step.summary.length > 0) {
    children.push({
      type: "Card",
      role: "summary",
      title: "Order summary",
      children: step.summary.map((line) => ({ type: "Text", value: line, role: "body" })),
    });
    notes.push("cost-transparency: rendered an order summary before the commit action");
    if (tags.has("recurring-charge")) {
      notes.push("recurring-charge: summary states the renewal cadence");
    }
  }

  // Primary input form.
  const fieldNodes: Node[] = (step.fields ?? []).map(fieldNode);
  const primaryButton: Node = {
    type: "Button",
    label: step.submitLabel,
    variant: "primary",
    action: { kind: "submit", target: formId },
  };
  notes.push("primary-action: exactly one primary action (the step's submit)");

  if (fieldNodes.length > 0) {
    const formChildren: Node[] = [...fieldNodes, primaryButton];
    // Skippable steps must offer a non-destructive way out.
    if (tags.has("skippable-step")) {
      formChildren.push({
        type: "Button",
        label: "Skip for now",
        variant: "secondary",
        action: { kind: "skip", target: flow.id },
      });
      notes.push("skippable-step: added a secondary Skip action");
    }
    children.push({ type: "Form", id: formId, columns: 1, children: formChildren });
    notes.push("responsive: form is single-column so it reflows on small screens");
    if (tags.has("minimal-input")) {
      notes.push(`minimal-input: form asks for only ${fieldNodes.length} field(s)`);
    }
  } else {
    children.push({ type: "Stack", role: "actions", direction: "horizontal", children: [primaryButton] });
  }

  // Destructive zone: separated, guarded by a confirmation dialog.
  if (tags.has("destructive-action") || tags.has("danger-zone")) {
    const dialogId = "confirm-delete";
    children.push({
      type: "Card",
      role: "danger-zone",
      title: "Danger zone",
      children: [
        {
          type: "Text",
          value: "Deleting your account is permanent and removes all of your data.",
          role: "body",
        },
        {
          type: "Button",
          label: "Delete account",
          variant: "danger",
          action: { kind: "open-dialog", target: dialogId },
        },
      ],
    });
    dialogs.push({
      type: "Dialog",
      id: dialogId,
      title: "Delete your account?",
      destructive: true,
      confirmVariant: "danger",
      confirmLabel: "Delete my account",
      cancelLabel: "Keep my account",
      children: [
        {
          type: "Text",
          value: "This permanently deletes your account and all associated data. This cannot be undone.",
          role: "body",
        },
      ],
    });
    notes.push(
      "destructive-action: danger action is isolated in a danger zone and guarded by a destructive confirmation dialog",
    );
  }

  const screen: Screen = {
    type: "Screen",
    id: `${flow.id}-${step.id}`,
    title: step.title,
    flow: flow.id,
    step: step.id,
    children,
    ...(dialogs.length > 0 ? { dialogs } : {}),
  };

  return { screen, notes };
}
