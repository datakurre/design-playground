import React from "react";
import { MarkdownDoc } from "./MarkdownDoc.js";
import standards from "../../../../docs/standards.md?raw";
import architecture from "../../../../docs/architecture.md?raw";

/**
 * Documentation pages, rendered from the project's committed markdown so
 * Storybook is the single published site (docs + components + screens)
 * with no duplicated prose. Generated governance reports are pulled in via
 * a glob so the page works whether or not `pnpm governance` has run.
 */
const govMods = import.meta.glob("../../../../governance/*.md", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

const GH = "https://github.com/datakurre/design-playground/blob/main";

export function IntroductionDoc() {
  return <MarkdownDoc source={standards} />;
}

export function ArchitectureDoc() {
  return <MarkdownDoc source={architecture} />;
}

export function GovernanceDoc() {
  const order = ["explainability-report.md", "compliance-report.md"];
  const parts = order.map((n) => govMods[`../../../../governance/${n}`]).filter(Boolean);
  const source = parts.length
    ? parts.join("\n\n---\n\n")
    : "Run `pnpm governance` to generate the explainability and compliance reports.";
  return <MarkdownDoc source={source} />;
}

const SCHEMAS = `# Schemas & tokens

The system is defined by human- and machine-readable schemas. Everything is
open and standards-based — see the **Introduction** for the relation to
W3C DTCG, JSON Schema 2020-12, the Model Context Protocol, and WCAG/ARIA.

## Sources of truth

| File | What it defines |
| --- | --- |
| [\`tokens/design-tokens.json\`](${GH}/tokens/design-tokens.json) | Design tokens (W3C DTCG \`$type\`/\`$value\`) |
| [\`tokens/design-tokens.schema.json\`](${GH}/tokens/design-tokens.schema.json) | Token file — JSON Schema |
| [\`tokens/css/variables.css\`](${GH}/tokens/css/variables.css) | Generated CSS custom properties (see **Design Tokens**) |
| [\`ui-ir/ui-ast.schema.json\`](${GH}/ui-ir/ui-ast.schema.json) | UI AST — JSON Schema 2020-12 (closed vocabulary) |
| [\`components/component.schema.json\`](${GH}/components/component.schema.json) | Component metadata — JSON Schema |
| [\`flows/flow.schema.json\`](${GH}/flows/flow.schema.json) | Flow definition — JSON Schema |
| [\`rules/design-rules.schema.json\`](${GH}/rules/design-rules.schema.json) | Design rules — JSON Schema |
| [\`rules/design-rules.json\`](${GH}/rules/design-rules.json) | Design rules catalogue |

## Example ASTs

- [\`valid-login.json\`](${GH}/ui-ir/examples/valid-login.json)
- [\`valid-delete-account.json\`](${GH}/ui-ir/examples/valid-delete-account.json)
- [\`invalid-structure.json\`](${GH}/ui-ir/examples/invalid-structure.json) — rejected by the schema
- [\`invalid-semantics.json\`](${GH}/ui-ir/examples/invalid-semantics.json) — rejected by the lints (rendered live under **Screens → Rejected plan**)
`;

export function SchemasDoc() {
  return <MarkdownDoc source={SCHEMAS} />;
}
