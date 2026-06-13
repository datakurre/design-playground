/**
 * Semantic lints: the executable form of the design rules whose
 * `machineCheck` field names a check here. The JSON Schema guarantees an
 * AST is structurally safe; these lints guarantee it is well-DESIGNED -
 * one primary action, guarded destructive actions, labelled fields, and
 * so on. Each finding carries the machineCheck id so it can be traced
 * back to its rule in the SQLite store.
 */
import type { Screen, Node, Dialog, Button, Field, Card } from "./types.js";

export type Severity = "error" | "warn" | "info";

export interface LintFinding {
  check: string;
  severity: Severity;
  message: string;
  path: string;
}

interface Visit {
  node: Node;
  path: string;
}

/** Depth-first walk over every node in the screen body and its dialogs. */
function walk(screen: Screen): Visit[] {
  const out: Visit[] = [];
  const recurse = (node: Node, path: string) => {
    out.push({ node, path });
    const kids = "children" in node ? (node.children as Node[]) : [];
    kids.forEach((child, i) => recurse(child, `${path}.children[${i}]`));
  };
  screen.children.forEach((child, i) => recurse(child, `children[${i}]`));
  (screen.dialogs ?? []).forEach((d, i) => recurse(d, `dialogs[${i}]`));
  return out;
}

function allOfType<T extends Node>(visits: Visit[], type: T["type"]): Array<{ node: T; path: string }> {
  return visits
    .filter((v) => v.node.type === type)
    .map((v) => ({ node: v.node as T, path: v.path }));
}

/** Generic labels that fail to state what an action does. */
const VAGUE_LABELS = new Set([
  "ok", "submit", "continue", "next", "yes", "no", "click here", "go", "done", "confirm",
]);

const COMMIT_LABELS = [
  "pay", "buy", "purchase", "subscribe", "upgrade", "place order", "complete purchase", "checkout",
];

type Check = (screen: Screen, visits: Visit[]) => LintFinding[];

const checks: Record<string, Check> = {
  // rule-single-primary-action
  "single-primary-action": (_screen, visits) => {
    // Primary buttons inside dialogs are scoped to that dialog, so only
    // count primaries in the screen body.
    const bodyPrimaries = allOfType<Button>(visits, "Button").filter(
      (b) => b.node.variant === "primary" && !b.path.startsWith("dialogs["),
    );
    if (bodyPrimaries.length > 1) {
      return [
        {
          check: "single-primary-action",
          severity: "error",
          message: `A screen may have at most one primary action; found ${bodyPrimaries.length} (${bodyPrimaries
            .map((b) => `"${b.node.label}"`)
            .join(", ")}).`,
          path: bodyPrimaries[1].path,
        },
      ];
    }
    return [];
  },

  // rule-action-label-states-action
  "label-states-action": (_screen, visits) => {
    return allOfType<Button>(visits, "Button")
      .filter((b) => b.node.variant !== "secondary")
      .filter((b) => VAGUE_LABELS.has(b.node.label.trim().toLowerCase()))
      .map((b) => ({
        check: "label-states-action",
        severity: "error" as const,
        message: `Action label "${b.node.label}" does not state the action; name the outcome (e.g. "Create account", "Delete project").`,
        path: b.path,
      }));
  },

  // rule-destructive-needs-confirmation
  "destructive-needs-confirmation": (screen, visits) => {
    const dialogs = allOfType<Dialog>(visits, "Dialog");
    return allOfType<Button>(visits, "Button")
      .filter((b) => b.node.variant === "danger" && !b.path.startsWith("dialogs["))
      .flatMap((b) => {
        const a = b.node.action;
        const target = dialogs.find((d) => d.node.id === a.target);
        if (a.kind !== "open-dialog" || !target || !target.node.destructive) {
          return [
            {
              check: "destructive-needs-confirmation",
              severity: "error" as const,
              message: `Destructive action "${b.node.label}" must open a confirmation dialog (action.kind "open-dialog" targeting a destructive Dialog).`,
              path: b.path,
            },
          ];
        }
        return [];
      });
  },

  // rule-destructive-dialog-shape
  "destructive-dialog-shape": (_screen, visits) => {
    return allOfType<Dialog>(visits, "Dialog")
      .filter((d) => d.node.destructive)
      .flatMap((d) => {
        const findings: LintFinding[] = [];
        if (d.node.confirmVariant !== "danger") {
          findings.push({
            check: "destructive-dialog-shape",
            severity: "error",
            message: `Destructive dialog "${d.node.id}" must use confirmVariant "danger" so the irreversible choice is clearly marked.`,
            path: d.path,
          });
        }
        if (d.node.cancelLabel.trim().toLowerCase() === d.node.confirmLabel.trim().toLowerCase()) {
          findings.push({
            check: "destructive-dialog-shape",
            severity: "error",
            message: `Destructive dialog "${d.node.id}" must offer a distinct, safe cancel affordance.`,
            path: d.path,
          });
        }
        return findings;
      });
  },

  // rule-danger-zone-separation
  "danger-zone-separated": (_screen, visits) => {
    // A danger button in the screen body must live inside a danger-zone
    // Card or Stack so it cannot be hit casually.
    const dangerCardPaths = [
      ...allOfType<Card>(visits, "Card").filter((c) => c.node.role === "danger-zone"),
      ...visits.filter((v) => v.node.type === "Stack" && (v.node as { role?: string }).role === "danger-zone"),
    ].map((v) => ("path" in v ? v.path : ""));
    return allOfType<Button>(visits, "Button")
      .filter((b) => b.node.variant === "danger" && !b.path.startsWith("dialogs["))
      .filter((b) => !dangerCardPaths.some((p) => b.path.startsWith(p)))
      .map((b) => ({
        check: "danger-zone-separated",
        severity: "error" as const,
        message: `Destructive action "${b.node.label}" must sit inside a danger-zone region, separated from routine controls.`,
        path: b.path,
      }));
  },

  // rule-field-has-label
  "field-has-label": (_screen, visits) => {
    return allOfType<Field>(visits, "Field")
      .filter((f) => !f.node.label || f.node.label.trim().length === 0)
      .map((f) => ({
        check: "field-has-label",
        severity: "error" as const,
        message: `Field "${f.node.name}" must have a visible, non-empty label.`,
        path: f.path,
      }));
  },

  // rule-field-autocomplete
  "field-has-autocomplete": (_screen, visits) => {
    const wants = new Set(["email", "password", "tel"]);
    return allOfType<Field>(visits, "Field")
      .filter((f) => wants.has(f.node.inputType) && !f.node.autocomplete)
      .map((f) => ({
        check: "field-has-autocomplete",
        severity: "warn" as const,
        message: `Field "${f.node.name}" (${f.node.inputType}) should set an autocomplete token to help password managers and assistive tech.`,
        path: f.path,
      }));
  },

  // rule-responsive-single-column
  "forms-single-column": (_screen, visits) => {
    const findings: LintFinding[] = [];
    for (const { node, path } of visits) {
      if (node.type === "Form" && (node.columns ?? 1) > 1) {
        findings.push({
          check: "forms-single-column",
          severity: "error",
          message: `Form "${node.id}" must be single-column so it reflows on narrow viewports.`,
          path,
        });
      }
      if (node.type === "Grid" && node.columns > 1) {
        const hasFields = (node.children as Node[]).some((c) => c.type === "Field" || c.type === "Form");
        if (hasFields) {
          findings.push({
            check: "forms-single-column",
            severity: "error",
            message: `Inputs must not be laid out in a ${node.columns}-column Grid; forms stay single-column.`,
            path,
          });
        }
      }
    }
    return findings;
  },

  // rule-minimal-input
  "minimal-fields": (_screen, visits) => {
    return allOfType<Form>(visits, "Form")
      .map((f) => ({ f, count: (f.node.children as Node[]).filter((c) => c.type === "Field").length }))
      .filter(({ count }) => count > 5)
      .map(({ f, count }) => ({
        check: "minimal-fields",
        severity: "warn" as const,
        message: `Form "${f.node.id}" asks for ${count} fields; defer anything not needed to proceed.`,
        path: f.path,
      }));
  },

  // rule-cost-transparency
  "commit-shows-summary": (_screen, visits) => {
    const commitButtons = allOfType<Button>(visits, "Button").filter(
      (b) =>
        b.node.variant === "primary" &&
        COMMIT_LABELS.some((k) => b.node.label.toLowerCase().includes(k)),
    );
    if (commitButtons.length === 0) return [];
    const hasSummary = allOfType<Card>(visits, "Card").some((c) => c.node.role === "summary");
    if (!hasSummary) {
      return [
        {
          check: "commit-shows-summary",
          severity: "error",
          message: `A commit action ("${commitButtons[0].node.label}") must be accompanied by a summary Card disclosing what the user agrees to.`,
          path: commitButtons[0].path,
        },
      ];
    }
    return [];
  },

  // rule-recurring-disclosure
  "summary-mentions-renewal": (_screen, visits) => {
    const summaries = allOfType<Card>(visits, "Card").filter((c) => c.node.role === "summary");
    const recurringWords = ["renew", "recurring", "per month", "per year", "/mo", "/yr", "monthly", "annually", "auto"];
    return summaries
      .filter((c) => {
        const text = collectText(c.node).toLowerCase();
        return !recurringWords.some((w) => text.includes(w));
      })
      .map((c) => ({
        check: "summary-mentions-renewal",
        severity: "error" as const,
        message: `A summary for a recurring charge must state the renewal cadence (e.g. "renews monthly").`,
        path: c.path,
      }));
  },
};

function collectText(node: Node): string {
  let acc = node.type === "Text" ? node.value + " " : "";
  const kids = "children" in node ? (node.children as Node[]) : [];
  for (const k of kids) acc += collectText(k);
  return acc;
}

/**
 * Run lints. If `only` is given (a set of machineCheck ids, typically the
 * checks implied by the rules retrieved for a step), restrict to those;
 * otherwise run every check.
 */
export function runLints(screen: Screen, only?: Iterable<string>): LintFinding[] {
  const visits = walk(screen);
  const wanted = only ? new Set(only) : null;
  const findings: LintFinding[] = [];
  for (const [name, check] of Object.entries(checks)) {
    if (wanted && !wanted.has(name)) continue;
    findings.push(...check(screen, visits));
  }
  return findings;
}

export const availableChecks = Object.keys(checks);
