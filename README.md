# design-playground

A browser-only editor for a design system that lives entirely as files in a Git
repository. There is no backend of its own: you sign in with GitLab, and the
GitLab REST API *is* the backend while Git *is* the database. Every change you
make — a token value, a component variant, a screen layout — is a commit you can
review, diff, and revert like any other.

## Why this exists

The W3C Design Tokens (DTCG) standard is good at describing *values*: colors,
spacing, typography primitives, and how they alias to one another. It has no
vocabulary for *usage rules* — the constraints that turn a pile of token values
into an enforceable design guide:

- "This component may only reference tokens from the `interactive` group."
- "No hardcoded hex values in component styles."
- "Spacing must resolve to a value on the token scale."
- "This color pairing must pass a contrast threshold."

That policy layer sits *above* tokens, scoped to components and screens. Today
it mostly exists as manual design review or ad hoc lint scripts. Existing
tooling doesn't treat "design guide as enforceable schema + gate" as a
first-class concept the way OpenAPI plus a linter does for APIs — editors
bolted onto a proprietary design tool sync tokens out to code as an
afterthought, CLI transform engines own no editing surface and no standing
constraints, and documentation platforms capture guides as prose that nothing
machine-checks.

This project is an attempt to close that gap by putting the editing surface
itself inside the Git-native world. Tokens, themes, components, screens, *and*
their usage contracts are authored through a UI that reads and writes a Git host
directly, collapsing "design tool → export → sync → repo" into a single loop —
and leaving every design decision as a Git object that CI and agents can act on.

## What you can do with it

- **Tokens and themes** — create and edit W3C DTCG tokens, including composite
  tokens, starting from a generated starter scale (grays, brand ramp, spacing,
  font sizes). Large token sets are grouped, searchable, and filterable. Themes
  are built from tokens and edited in the same tab.
- **Components** — scaffold from templates (Button, Card, Alert, Badge, Input,
  or empty), then edit layout, variants, states, and slots.
- **Screens** — compose screens from nested components and other screens, with
  loop detection so a screen can't end up containing itself. Templates for
  landing, login, dashboard, or empty.
- **Usage contracts** — attach machine-checkable rules to a component. Four rule
  types are supported: allowed token groups, no hardcoded values, spacing on a
  named scale, and a minimum contrast ratio between two properties.
- **Git workflows** — create branches, commit your work, and open merge requests
  without leaving the app. A "Contract check" panel validates every component
  against its contracts and lists the violations before you open the request.
- **Export** — write your tokens out for other projects to consume as CSS custom
  properties and a Tailwind config, committed to the branch you're on. Tokens
  only; components and screens are not exported.
- **Shareable links** — every view has its own URL
  (`#/namespace/project/components/Button`), so a link to a specific component
  or screen survives a reload and can be pasted into a review.
- **In-app help** — every tab and every major form carries a short explanation of
  what it does, and what it doesn't.

## Using it

The app is hosted at
<https://datakurre.github.io/design-playground>.

1. Sign in with GitLab. Authentication is OAuth PKCE against `gitlab.com` with
   the `api` scope — there is no server in between, and the access token is
   cached in your browser's `localStorage`.
2. Pick a project. This is the repository your design system lives in.
3. Edit tokens, themes, components, screens, and contracts.
4. Switch to Git Workflows to pick a branch, review the contract check, commit,
   and open a merge request.

If you run your own copy, note that the OAuth client ID and redirect URI are
compiled into `src/Auth.elm` and point at the hosted deployment above. You will
need to register your own GitLab OAuth application (PKCE, no client secret,
`api` scope) and edit those two values before sign-in will work anywhere else.

## How your design system is stored

Everything is plain JSON in the repository you picked, so the files stay
readable and diffable whether or not you ever open this app again:

| Path                               | Contents                                    |
| ---------------------------------- | ------------------------------------------- |
| `tokens/tokens.json`               | all design tokens                           |
| `themes/<name>.json`               | one file per theme                          |
| `components/<name>.json`           | one file per component                      |
| `components/<name>.contract.json`  | that component's usage contract             |
| `layouts/<name>.json`              | one file per screen                         |
| `exports/variables.css`            | generated CSS custom properties             |
| `exports/tailwind.config.js`       | generated Tailwind config                   |

A `contracts.json` at the repository root is also read at startup, if present.

## Where this is headed

Two things the exploration has surfaced but not yet answered:

- **Contract enforcement is advisory, not a gate.** Violations are reported
  inside the app; nothing fails a pipeline. Making the validator runnable outside
  the browser, so violations surface as merge request failures, is the obvious
  next step.
- **Tokens carry no machine-checkable intent.** DTCG's `$description` is free
  text. There may be room for a more structured "why this token exists"
  annotation that contracts could reason about.

Treat both as current thinking, not a commitment to a schema, an implementation,
or a timeline.

## Contributing

Building, testing, and the AI-agent workflow this project uses are documented in
[AGENTS.md](./AGENTS.md).
