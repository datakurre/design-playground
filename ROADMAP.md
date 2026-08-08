# Roadmap

This document is a discovery log, not a committed feature list. It captures
why this project exists conceptually and where the exploration is headed. It
will be revised as the exploration progresses.

## Why this project exists

`design-playground` is an exploratory vehicle for the W3C Design Tokens
(DTCG) standard — specifically, an attempt to figure out what's still
missing between design tokens and fully machine-readable,
**agent-enforceable** design guides.

Design tokens, as standardized today, are good at describing *values*:
colors, spacing, typography primitives, and how they alias to one another.
They are not designed to describe *usage rules* — the constraints that turn
a pile of token values into an enforceable design guide.

## The landscape today

Existing design-token tooling roughly falls into three camps, and none of
them treat "design guide as enforceable schema + CI gate" as a first-class
concept the way OpenAPI plus a linter does for APIs:

- **Editors bolted onto a proprietary design tool** (e.g. Tokens Studio for
  Figma) — tokens are authored inside the design tool and synced out to
  code as an afterthought. The design tool's data model and API were never
  built to be policy-checked by CI.
- **CLI-only transform engines** (e.g. Style Dictionary, Terrazzo, Cobalt)
  — take token JSON and emit platform-specific output. They own no editing
  surface and no standing constraints; custom transforms are export-time
  conveniences, not rules that are checked on every change.
- **Documentation platforms** (e.g. Zeroheight, Supernova) — capture design
  guides as narrative, human-readable prose. Nothing machine-checks
  adherence to them.

## What's structurally different here

This project puts the editing surface itself inside the git-native world:
tokens, themes, components, and screens are authored through a UI that
reads and writes a Git host directly (GitLab REST API, OAuth PKCE), rather
than living in a design tool and getting exported. That collapses
"design tool → export → sync → repo" into a single loop.

The practical upshot: every design decision is a diffable, reviewable Git
object (a commit or merge request) — a substrate that CI and agents can act
on directly, unlike a design tool's plugin API. See `src/GitLab/*.elm`,
`src/Auth.elm` / `src/Auth/`, and `src/Pages/GitWorkflows.elm`.

## The identified gap: usage contracts

DTCG standardizes token *values* and aliasing (color, spacing, type scale,
composite tokens) but has no vocabulary for *usage rules*, e.g.:

- "This component may only reference tokens from the `interactive` group."
- "No hardcoded hex values in component styles."
- "Spacing must resolve to a value on the token scale."
- "This color pairing must pass a contrast threshold."

That's a policy layer that sits *above* tokens, scoped to components and
screens. Today it exists only as manual design review or ad hoc, untrusted
lint scripts — nothing standardizes it, and nothing enforces it
automatically.

## Where this repo currently sits

Editors and generators for the token/component/screen layer exist:

- Token and theme editing — Token Studio, Themes
- Component and screen scaffolding — Component Registry, Screen Composer
- Export — Export Pipeline

A constraint/contract schema, and an automated validator that checks
components and screens against it, do **not** yet exist in the codebase.

## Proposed direction (exploratory, not committed)

1. **A schema for component-level usage contracts** — allowed token
   groups, required states/variants, accessibility constraints — stored
   alongside component definitions.
2. **A validator** that checks token/component/screen files against that
   schema, runnable both locally (as part of `make check`) and in CI, so
   violations surface as merge request failures the same way `elm-review`
   surfaces code issues today.
3. **Semantic-intent metadata on tokens**, as a possible extension point —
   DTCG's `$description` is free text, not machine-checkable intent, so
   there may be room to explore a more structured "why this token exists"
   annotation.

## Non-goals for now

No commitment to a specific schema format, validator implementation, or
timeline. This is a discovery document; treat it as a snapshot of current
thinking, not a promise.
