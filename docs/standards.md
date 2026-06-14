# Approach, stack, and relation to standards

This project demonstrates a path from **design intent** to an
**agent-managed user interface** that stays safe, accessible, and
on-brand. Rather than have an agent emit code or markup, the design
system is captured as data, exposed to the agent through a standard
protocol, and every generated interface is validated against explicit,
machine-checkable rules before it can be rendered.

## The approach in one paragraph

Design knowledge (tokens, components, flows, rules) lives as plain JSON
and is loaded into a small **SQLite** store whose schema *enforces* the
design system's invariants. A **Model Context Protocol (MCP)** server
exposes that store as deterministic tools. An agent **planner** consumes
those tools to interpret a request, retrieve the governing rules, and
assemble a **UI Abstract Syntax Tree (AST)** from a closed vocabulary.
The AST is validated structurally (JSON Schema) and semantically (design
lints) and only then handed to a **React** renderer that styles it
purely from design-token CSS variables. Every decision is written to an
append-only audit log, so any generated screen is fully explainable.

## Why this shape

- **Data, not code generation.** An agent that writes UI *code* is hard
  to constrain and audit. An agent that fills a fixed, validated AST can
  only ever produce interfaces the design system already permits.
- **Enforcement at the lowest possible layer.** Invariants live in the
  database (constraints/triggers), the schema (closed vocabulary), and
  executable lints — three independent layers, each enforced by code.
- **Determinism by default.** No model is required to run the pipeline;
  retrieval is pure SQL and planning is rule-driven, so results are
  reproducible. The MCP seam is exactly where a model can be added.
- **Minimal infrastructure.** SQLite is embedded and the renderer is
  static — no databases, vector stores, or model services to operate.

## The stack

| Layer | Technology | Role |
| --- | --- | --- |
| Tokens | W3C DTCG JSON → CSS custom properties | single styling source of truth |
| Metadata | JSON + JSON Schema | components, flows, rules |
| Store | SQLite (`better-sqlite3`) | relational rule store that enforces invariants |
| Protocol | Model Context Protocol (`@modelcontextprotocol/sdk`) | deterministic retrieval + validation tools |
| Planner | TypeScript (MCP client) | intent → rules → AST, with a decision trace |
| AST | JSON Schema 2020-12 (Ajv) + semantic lints | safe, closed UI vocabulary |
| Renderer | React + Vite | token-styled runtime that rejects invalid ASTs |
| Workbench | Storybook (CSF) | browse, visually approve & test components; the published site |
| Governance | JSON + Markdown | audit log, traces, explainability, compliance |

Everything is open source and TypeScript-first; the whole pipeline runs
on Node 22 + pnpm, with an optional [devenv.sh](https://devenv.sh)
declarative environment.

## Relation to standards

This demonstration is deliberately built on open standards so the
artifacts are portable and the approach is not tied to any one vendor.

### W3C Design Tokens (DTCG)
`tokens/design-tokens.json` follows the
[Design Tokens Format Module](https://tr.designtokens.org/format/) from
the [W3C Design Tokens Community Group](https://www.w3.org/community/design-tokens/):
tokens use `$type` and `$value`, grouped by category (color, typography,
spacing, radius, shadow, motion, breakpoints). Because the format is
standard, the same source could feed Style Dictionary or any other
DTCG-aware tool; here a small generator emits CSS custom properties.

### JSON Schema (2020-12)
The UI AST (`ui-ir/ui-ast.schema.json`) and the component/flow/rule
metadata are described with [JSON Schema](https://json-schema.org/) using
the 2020-12 dialect, validated with Ajv. `additionalProperties: false`
and closed enumerations make the AST a **safe vocabulary**: there is no
field through which raw HTML, URLs, scripts, or styles could enter.

### Model Context Protocol (MCP)
The design store is exposed via the
[Model Context Protocol](https://modelcontextprotocol.io) — an open
standard for connecting agents to tools and data. The same server drives
the bundled deterministic planner *and* an interactive client such as
Claude Code (see `.mcp.json`), with no code changes. Retrieval tools are
pure SQL reads, which is what makes them deterministic.

### WCAG 2.2 and WAI-ARIA (accessibility)
Component accessibility requirements cite specific
[WCAG 2.2](https://www.w3.org/TR/WCAG22/) success criteria — e.g. **2.4.7
Focus Visible**, **4.1.2 Name, Role, Value**, **2.5.8 Target Size** — and
semantic lints enforce machine-checkable parts (every field labelled,
one unambiguous primary action, destructive actions confirmed). The
renderer emits [WAI-ARIA](https://www.w3.org/TR/wai-aria-1.2/) semantics
(`role="dialog"`, `aria-modal`, `aria-current`) for the nodes that need
them.

### Component Story Format (Storybook)
The component workbench — and this published site — is
[Storybook](https://storybook.js.org/), with stories written in the open
[Component Story Format (CSF)](https://storybook.js.org/docs/api/csf).
Crucially, every story renders through the **same** `RenderNode` bindings
and the **same** generated design-token CSS as the production renderer, so
what a team browses and visually approves is exactly what ships. The same
stories double as tests: each story's `play` function runs as a
browserless interaction test (Storybook portable stories on Vitest, part
of `pnpm test`) and, where a browser is available, under the Storybook
test-runner. Accessibility is checked in-browser by `addon-a11y`.

The **Design Token Playground** (Foundations) makes the token's role
across phases tangible: editing one DTCG value live updates the generated
CSS variable, the list of component variants that bind it (read from
`components/*.json`), and a re-themed screen — all from the same
`flattenTokens`/`cssVarName`/`cssValue` helpers the CSS build uses. A
toolbar theme control applies the same overrides across every story, so
the ripple is visible system-wide.

### WHATWG HTML autofill
Field `autocomplete` values use the
[WHATWG HTML autofill](https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#autofill)
token vocabulary (`email`, `current-password`, `new-password`, …); a lint
warns when a recognisable field omits one, helping password managers and
assistive technology.

### Relational integrity (SQL)
The rule store relies on standard SQL integrity features — foreign keys,
`CHECK` constraints, and triggers — so that design knowledge violating an
invariant cannot be stored at all. This makes the database itself, not
application code, the strongest enforcement layer.

## What a reviewer can verify

Each acceptance criterion maps to a concrete, committed artifact — see
the [compliance report](governance/compliance-report.md) and the
[explainability report](governance/explainability-report.md). For any
generated screen, the request, interpreted intent, retrieved rules,
planning trace, validation verdict, and audit entries are all inspectable
under `scenarios/` and `governance/`.
