# design-playground

A browser-only editor for a design system that lives entirely as files in a Git
repository. There is no backend of its own: you sign in with GitLab, and the
GitLab REST API *is* the backend while Git *is* the database. Every change you
make — a token value, a component variant, a screen layout — is a commit you can
review, diff, and revert like any other.

## Why this exists

The W3C Design Tokens (DTCG) standard is good at describing *values*: colors,
spacing, typography primitives, and how they alias to one another. It reached
[its first stable version, 2025.10][dtcg-stable], in October 2025, backed by two
dozen organizations including Adobe, Google, Meta and Figma, and it now covers
modern color spaces, groups and aliases, and token resolvers.

That settles the values layer — and makes the gap above it the interesting one.
DTCG has no vocabulary for *usage rules*: the constraints that turn a pile of
token values into an enforceable design guide.

- "This component may only reference tokens from the `interactive` group."
- "No hardcoded hex values in component styles."
- "Spacing must resolve to a value on the token scale."
- "This color pairing must pass a contrast threshold."

That policy layer sits *above* tokens, scoped to components and screens. Today
it mostly exists as manual design review or ad hoc lint scripts. Existing
tooling doesn't treat "design guide as enforceable schema + gate" as a
first-class concept the way OpenAPI plus a linter does for APIs. Penpot has
native DTCG tokens and is open source and self-hostable, but no usage-rule layer
— and, as of [an open issue on the repo][penpot-tokens-api], no plugin API for
the tokens tab at all. Tokens Studio and Supernova sync token values to Git
without owning a constraint vocabulary. And Figma's Variables REST API is
[Enterprise-plan-only][figma-variables] for both read and write, which is the
hardest constraint on any "author in the design tool, enforce in CI" story.

This project is an attempt to close that gap by putting the editing surface
itself inside the Git-native world. Tokens, themes, components, screens, *and*
their usage contracts are authored through a UI that reads and writes a Git host
directly, collapsing "design tool → export → sync → repo" into a single loop —
and leaving every design decision as a Git object that CI and agents can act on.

[dtcg-stable]: https://www.w3.org/community/design-tokens/2025/10/28/design-tokens-specification-reaches-first-stable-version/
[penpot-tokens-api]: https://github.com/penpot/penpot/issues/7916
[figma-variables]: https://developers.figma.com/docs/rest-api/plan-access-tokens/

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
  named scale, and a minimum contrast ratio between two properties. **Contracts
  are advisory**: violations are reported in the app, but a component that
  breaks its contract still saves and still commits. Nothing gates.
- **Branch-first editing** — the repository's default branch is read-only in the
  app, and so is any branch GitLab reports as protected. Open a repository and
  you can read all of it; create a branch and the editors come alive. There is no
  draft state to lose, because every save is a commit on the branch you made.
- **Git workflows** — create branches, commit your work, and open merge requests
  without leaving the app. A "Contract check" panel validates every component
  against its contracts and lists the violations before you open the request.
- **Export** — write your tokens out for other projects to consume as CSS custom
  properties and a Tailwind config, committed to the branch you're on. Tokens
  only, and narrower than it sounds — see [Known limitations](#known-limitations).
- **Shareable links** — every view has its own URL
  (`#/namespace/project/components/Button?branch=feature/new-colors`), so a link
  to a specific component or screen on a specific branch survives a reload and
  can be pasted into a review.
- **In-app help** — every tab and every major form carries a short explanation of
  what it does, and what it doesn't.

## Using it

The app is hosted at
<https://datakurre.github.io/design-playground>.

1. Sign in with GitLab. Authentication is OAuth PKCE against `gitlab.com`, asking
   for the `read_api` and `write_repository` scopes. There is no server in
   between, and the access token is cached in your browser's `localStorage`.
2. Pick a project. This is the repository your design system lives in. You land
   on its default branch, which is read-only — you can look at everything.
3. Create a branch, from the banner across the top of any tab or from Branches &
   Reviews. The editors are inert until you do.
4. Edit tokens, themes, components, screens, and contracts. Each Save is a commit
   on your branch.
5. Switch to Branches & Reviews to review the contract check and open a merge
   request.

Saves carry the commit each file was read at, so if someone else changed a file
on the same branch, the save is refused rather than silently overwriting them.
"Reload" in the top bar re-reads the branch.

### Running your own copy

The OAuth client is configured through Vite environment variables rather than
compiled in. Copy `.env.example` to `.env` and set `VITE_GITLAB_CLIENT_ID` to a
GitLab OAuth application of your own, registered as a **public** client (PKCE,
no client secret) with the `read_api` and `write_repository` scopes and a
redirect URI matching where you serve the app. `VITE_GITLAB_REDIRECT_URI`
defaults to your origin plus Vite's `base` path, which is right for both
`make dev` and a Pages deployment.

Only `gitlab.com` is supported. The API host is hardcoded in `src/GitLab/*` and
`src/Auth.elm`; self-hosted GitLab would need those changed.

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

The JSON Schemas in `schemas/` describe these formats and are checked against
every save.

## Known limitations

Things that are true today and worth knowing before you rely on them:

- **Contracts don't gate anything.** `Contracts.validate` runs in the views, not
  on the save path. See "Where this is headed".
- **The CSS export flattens aliases.** `exports/variables.css` resolves every
  token reference before writing, so the output contains no `var()` at all — the
  indirection that is the point of CSS custom properties is lost. Themes are not
  exported; only the base token set is.
- **The Tailwind export is colors-only.** `exports/tailwind.config.js` emits
  `theme.extend.colors` and nothing else. Spacing, typography, radii and shadows
  are dropped, as are all composite tokens.
- **`AllowedTokenGroups` doesn't follow aliases**, where the other three rules
  do. This is deliberate — it governs the vocabulary a component may *reference*,
  so a permitted path stays permitted no matter what it is later re-pointed at —
  but it does mean it can't see through an alias into a group you forbade.
- **`ContrastThreshold` can only read hex.** A color resolving to `rgb(…)`,
  `hsl(…)` or `currentColor` is reported as "couldn't check" rather than as
  passing or failing.
- **Contracts are per-node.** There is no way to express a cross-node rule, a
  cardinality constraint, "this component must have a slot named X", or a rule
  scoped to part of a layout. Every rule applies to every styled node.
- **The access token is kept in `localStorage`**, so it survives a reload and is
  readable by any script on the origin. The alternative is signing in again on
  every refresh.
- **Opening a repository reads every file in it.** One request per component,
  screen, theme and contract, in parallel. Fine for a design system, not for a
  monorepo that happens to contain one.

## Where this is headed

Two things the exploration has surfaced but not yet answered:

- **Contract enforcement is advisory, not a gate.** Violations are reported
  inside the app; nothing fails a pipeline. Making the validator runnable outside
  the browser, so violations surface as merge request failures, is the obvious
  next step — and it is the position no license or plan tier can lock you out of,
  since it acts on DTCG files in Git rather than on anyone's API.
- **Tokens carry no machine-checkable intent.** DTCG's `$description` is free
  text. There may be room for a more structured "why this token exists"
  annotation that contracts could reason about.

Treat both as current thinking, not a commitment to a schema, an implementation,
or a timeline.

## Contributing

Building, testing, and the AI-agent workflow this project uses are documented in
[AGENTS.md](./AGENTS.md).
