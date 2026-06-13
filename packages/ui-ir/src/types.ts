/**
 * TypeScript mirror of ui-ir/ui-ast.schema.json. The JSON Schema is the
 * source of truth for validation; these types give planner/renderer
 * code editor support and exhaustiveness checking.
 */
export type ActionKind =
  | "submit"
  | "navigate"
  | "open-dialog"
  | "close-dialog"
  | "confirm"
  | "cancel"
  | "skip";

export interface ActionRef {
  kind: ActionKind;
  target?: string;
}

export type Gap = "xs" | "sm" | "md" | "lg" | "xl";
export type ButtonVariant = "primary" | "secondary" | "danger";

export interface Screen {
  type: "Screen";
  id: string;
  title: string;
  flow?: string;
  step?: string;
  children: Node[];
  dialogs?: Dialog[];
}

export interface Stack {
  type: "Stack";
  direction?: "vertical" | "horizontal";
  gap?: Gap;
  role?: "plain" | "danger-zone" | "actions";
  children: Node[];
}

export interface Grid {
  type: "Grid";
  columns: number;
  gap?: Gap;
  children: Node[];
}

export interface Card {
  type: "Card";
  title?: string;
  role?: "plain" | "summary" | "danger-zone";
  children: Node[];
}

export interface Text {
  type: "Text";
  value: string;
  role?: "heading" | "subheading" | "body" | "caption" | "error";
  level?: number;
}

export interface Form {
  type: "Form";
  id: string;
  columns?: number;
  children: Node[];
}

export interface Field {
  type: "Field";
  name: string;
  label: string;
  inputType: "text" | "email" | "password" | "number" | "tel" | "checkbox" | "select" | "textarea";
  required?: boolean;
  autocomplete?: string;
  help?: string;
  options?: Array<{ value: string; label: string }>;
}

export interface Button {
  type: "Button";
  label: string;
  variant: ButtonVariant;
  action: ActionRef;
  disabled?: boolean;
}

export interface Dialog {
  type: "Dialog";
  id: string;
  title: string;
  destructive?: boolean;
  children: Node[];
  confirmLabel: string;
  cancelLabel: string;
  confirmVariant?: "primary" | "danger";
}

export interface NavItem {
  label: string;
  action: ActionRef;
  current?: boolean;
}

export interface Nav {
  type: "Nav";
  items: NavItem[];
}

export type Node = Stack | Grid | Card | Text | Form | Field | Button | Dialog | Nav;

export type AnyNode = Screen | Node;
