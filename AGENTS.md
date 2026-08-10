# AI Coding Agents Guide

Welcome to the Git-Native Design System Platform. This project heavily utilizes AI coding agents to overcome ecosystem gaps in Elm (e.g., boilerplate generation, JS interop, codecs, and API bindings).

This document serves as the prompt and instruction manual for any AI agent working on this codebase. When assigning tasks, explicitly invoke the relevant agent persona.

For what the app *is* and what it's for, see [README.md](./README.md). This file
is everything about changing it.

## Prerequisites

[Nix](https://nixos.org/) with [devenv](https://devenv.sh/). The dev shell pins
the whole toolchain (Node 22, Elm 0.19.1, elm-format, elm-test, elm-review,
elm-json, treefmt, chromium, and the npm tooling packaged in `pkgs/`); nothing is
installed globally.

```sh
devenv shell   # or let direnv load it automatically
make dev       # generates .elm-tailwind/, then starts the Vite dev server
```

Inside the dev container the shell is already active, so `make check` works
directly and the `devenv shell --` prefix is only needed on a host or in CI.

Everything you need should be obtainable by editing `devenv.nix`. If a tool is
missing, add it to `packages` there rather than installing it — and never run
`npm install` in the project root, where `node_modules` is a symlink into the nix
store. See `.claude/skills/devenv-tools/SKILL.md` for the npm and Elm package
procedures.

**The container has no direct DNS.** All egress goes through the proxy in
`HTTP_PROXY`/`HTTPS_PROXY`. curl, git and nix honour it; Node does not unless
told, which is why `devenv.nix` sets `NODE_USE_ENV_PROXY = "1"`. Without that,
`elm-review` cannot reach `package.elm-lang.org` to solve the dependencies of the
elm-tailwind-classes extractor, and the consequence is silent: `vite build`
prints `CLASS EXTRACTION FAILED`, **exits 0**, and emits a stylesheet with every
dynamically composed class missing — every colour in the app. `make smoke` fails
on that deliberately.

Elm packages are cached in `~/.elm` (outside the repo, empty in a fresh
container) and `elm-stuff/` (gitignored). Between them the project builds
offline. `make clean` leaves `elm-stuff/` alone for that reason; `make distclean`
removes it and needs the network to recover.

## Build Toolchain

The app is built with **Vite 7** and **Tailwind CSS v4**. `elm-tailwind-classes`
generates a type-safe Tailwind API into `.elm-tailwind/`, which `elm.json`
lists as a required source directory — **`make gen` must run before `elm-test`,
`elm-review`, or any other Elm tooling will even compile.** Do not invoke
`elm-test` or `elm-review` directly without having run `make gen` first; use
`make check`, which handles this ordering.

| Command        | What it does                                                                          |
| -------------- | ------------------------------------------------------------------------------------- |
| `make gen`     | Generate the typed Tailwind Elm API into `.elm-tailwind/` (required before any Elm tooling runs) |
| `make dev`     | `gen` + start the Vite dev server                                                      |
| `make build`   | `gen` + production Vite build                                                          |
| `make dist-ci` | `gen` + Vite build for CI/deploy, output in `dist/`                                    |
| `make check`   | the full verify loop — the gate; see below                                             |
| `make test`    | both test suites; `make test T=Contracts` runs `tests/ContractsTest.elm` alone         |
| `make fmt`     | `elm-format --yes` + `treefmt` — the fixer for what `check` reports                    |
| `make review`  | `gen` + `elm-review` on its own                                                        |
| `make watch`   | re-run `make test` on every Elm change                                                 |
| `make smoke`   | `build` + render the app in headless chromium — see "Verifying your work"              |
| `make clean`   | remove generated output, but **not** `elm-stuff/`                                      |
| `make distclean` | `clean` + `elm-stuff/`; needs the network to recover                                 |

The narrow targets are the working loop. `make check` is the gate, and passing a
narrow target is not the same as passing it.

### What `make check` actually runs

In order: `make gen` → `elm-format --validate src/ tests/` → `elm make
src/Main.elm --output=/dev/null` → `elm-test` → `node --test
tests/schemas.test.js` → `elm-review`.

The middle steps are not incidental:

- **`elm-format --validate`** reports rather than rewrites. Neither elm-test nor
  elm-review has an opinion about layout, so unformatted code used to reach main
  unnoticed. Fix what it finds with `make fmt`.
- **`elm make src/Main.elm`** compiles the app entry point explicitly. elm-test
  only compiles the test modules and their dependencies, and elm-review parses
  rather than type-checks — neither reaches `src/Main.elm`, so without this a
  broken `Model` or view would pass `make check`.
- **`node --test tests/schemas.test.js`** checks the JSON Schemas in `schemas/`
  against sample payloads. They are the same schemas `src/main.js` feeds to ajv
  through the `validateSchema` port, so they are not documentation.

Tests live in `tests/`; the elm-review configuration lives in `review/`.

### Verifying your work

`make check` proves the code type-checks and that the pure logic behaves. It
cannot tell you the app still *starts* — a bad flag decoder, broken port wiring
in `src/main.js`, or a failed asset path all compile fine and produce a blank
page.

`make smoke` covers that gap: it builds, serves the result, loads it in headless
chromium, asserts the app root rendered on both the home route and a deep link,
and writes screenshots to `.smoke/`. **Look at the screenshots** — the exit code
only tells you something rendered, the picture tells you whether it rendered
right. It also fails when Tailwind class extraction has silently degraded the
stylesheet (see Prerequisites).

Run `make smoke` for any change touching views, routing, `src/main.js`, ports, or
the build. It is not a substitute for tests: it cannot reach anything behind
GitLab sign-in, which is impossible locally because `clientId`/`redirectUri` in
`src/Auth.elm` are hardcoded to the deployed instance.

### Git hooks

`devenv.nix` installs two pre-commit hooks: `treefmt` and `make check`. A commit
that fails either is rejected, so run `make check` before you get there.

### Deployment & CI

Two workflows, and both run the same `make check` the pre-commit hook runs:

- `.github/workflows/ci.yml` — every pull request and every push to `main`. Runs
  `make check`, then `make smoke`, and uploads the smoke screenshots as an
  artifact so a failure can be looked at rather than guessed at.
- `.github/workflows/deploy.yml` — pushes to `main`. Runs `make check`, builds
  with `make dist-ci`, publishes `dist/` to GitHub Pages. The site is served
  under the `/design-playground/` base path, set via `base` in `vite.config.js`.

Keep both on `make check` rather than unrolling it into individual steps. That
unrolling is what CI used to do, and it meant nothing checked formatting, nothing
compiled `src/Main.elm`, and nothing ran the schema tests. If CI and local
diverge, one of them is lying about whether the branch is good.

There is no nix caching configured, so a cold CI run rebuilds the whole
environment. Worth adding a cachix cache if runs get slow enough to matter.

## Module map

Where things live, so you don't have to guess:

**Shell and plumbing**

- `src/Main.elm` — entry point, app bar, tab chrome, project picker. Also holds
  the `Nav.Key` in its `AppModel` wrapper and runs effects via `Effect.perform`
- `src/Update.elm` — the single `update` loop (~2000 lines; the Refactor Agent's
  standing assignment)
- `src/Effect.elm` — what `update` asks the runtime to do, as inspectable data
- `src/Guard.elm` — whether the current branch may be written to, and which
  `Msg`es count as writing. The default branch and any GitLab-protected branch
  are read-only; `update` refuses every mutating message on one, and the pages
  render their controls disabled to match
- `src/Types.elm` — `Model`, `Msg`, `Tab`
- `src/Route.elm` — fragment-based URL routing
  (`#/namespace/project/tab/item?branch=feature%2Fx`); fragments, not paths,
  because GitHub Pages has no history fallback. The branch is a query parameter
  inside the fragment, split off before the segments are, because branch names
  contain slashes
- `src/Ui.elm` — shared chrome: buttons, panels, inputs, pills, context-help widgets
- `src/Help.elm` — the text of every in-app context-help topic

**Domain**

- `src/Tokens.elm`, `src/Themes.elm`, `src/Components.elm`, `src/Screens.elm`
- `src/Components.elm` also owns per-variant/per-state styling: a layout node
  carries base `styles` plus `overrides` (style layers keyed by variant and/or
  state), and `resolveStyles` is the one place that decides which layer wins.
  Anything asking "what does this node look like as X?" — the renderer, the
  editor, the contract validator — goes through it.
- `src/Contracts.elm` — usage-contract schema, codecs, and `validate`
- `src/Export.elm` — CSS variables and Tailwind config generators
- `src/Templates.elm` — component, screen, and theme starter templates
- `src/TokenScale.elm` — starter token ramps; `src/TokenBrowse.elm` — grouping,
  search, filtering; `src/Naming.elm` — the one place that decides whether a typed
  name is usable; `src/Colors.elm` — hex parsing and contrast ratio;
  `src/Renderer.elm` — screen/component preview rendering

**Boundaries**

- `src/GitLab/` — REST bindings: `Branches`, `Commits`, `Files`,
  `MergeRequests`, `Projects`. They return a `GitLab.Request.Request` — method,
  url, headers and body as data — and `GitLab.Request.toCmd` is the only place
  `Http.request` is called
- `src/Auth.elm` + `src/Ports.elm` — OAuth PKCE and the `localStorage` token cache
- `src/Ports.elm` also carries `validateSchema`/`schemaValidationResult`, the ajv
  bridge wired up in `src/main.js` against the JSON Schemas in `schemas/`.
  Note the incoming half is currently dead: `Main.subscriptions` is `Sub.none`,
  so validation results are sent from JS and nothing in Elm listens. Wire the
  subscription before building anything on top of it.

**Views**

- `src/Pages/` — one module per tab: `TokenStudio`, `ComponentRegistry`,
  `ScreenComposer`, `GitWorkflows`, `ExportPipeline`

## Testability rules

Read this before deciding where new code goes. It is the difference between work
a test can hold onto and work only the compiler ever sees.

**All of it is reachable.** The domain layer is pure. View helpers that take
plain data go through `Test.Html.Query`. And `update` runs directly in a test —
see `tests/UpdateTest.elm` — because effects are data and the `Nav.Key` lives in
`Main`, not the `Model`.

The rules that keep it that way:

1. **`update` returns an `Effect`, never a `Cmd`.** `Nav.Key`, `Ports` and
   `Http.request` appear only in `src/Main.elm`, `src/Effect.elm` and
   `src/GitLab/Request.elm`. Adding a new kind of side effect means adding an
   `Effect` constructor, not reaching for `Cmd` in `Update`.
2. **`GitLab/*` functions return a `Request`, never a `Cmd`.** The body travels
   as a `Json.Encode.Value` so a test can decode it. This is what makes "did that
   save become a create or an update, on which branch" answerable at all.
3. **Never `Expect.equal` a whole `Effect`.** `SendRequest` carries an
   `Http.Expect`, which contains a function, and Elm's `==` throws at runtime on
   functions. It works fine for `PushUrl` and `ClearToken`, which makes the trap
   worse rather than better. Use `Effect.requests` and `Effect.toList`.
4. **Do not put `Nav.Key` back in the `Model`.** It is the one thing that would
   undo all of this. `Main.AppModel` holds it; its docstring explains why that is
   the only place it can go.
5. **Give view helpers data, not `Model`,** where they can take it. Not a
   testability constraint any more, just the better shape — the assertions end up
   about the thing being rendered rather than about how a model got that way.
6. **Every new `Msg` branch ships a test** asserting both the model change and
   the resulting `Effect`.
7. **Every new `Msg` is classified in `Guard.isMutating`,** which the compiler
   enforces: it is an exhaustive case with no catch-all, and adding `_ -> False`
   would silently exempt every future message from the read-only rule. A message
   is mutating if running it can change the bytes a later save would write, or
   commits itself. The write paths take their branch from
   `Guard.writableBranch`, never from `model.currentBranch` directly.

## Skills

Repo-local skills in `.claude/skills/` cover the recipes that are easy to get
wrong. Prefer them over rediscovering the procedure:

- `verify` — which check to run and how to read its failure
- `run` — launching, rendering and screenshotting the app
- `elm-tdd` — where tests go, the house style, working around the `Nav.Key` barrier
- `add-contract-rule` — the seven places a new usage-contract rule touches
- `devenv-tools` — getting a tool through nix/devenv, and the proxy trap

## Overarching Directives

1. **Elm Architecture**: Strictly adhere to The Elm Architecture (TEA). No side-effects outside of `Cmd` and `Sub`.
2. **Red / Green TDD**: Always write failing tests (`elm-test`) first. Make them pass. Then refactor using `elm-review`.
3. **Zero Backend**: Do not invent custom backend APIs. The backend is *always* the GitLab REST API. Persistence is Git.
4. **W3C Standards**: Always default to W3C Design Token specifications.
5. **Human Review**: Agents handle the volume; humans review the architecture. Do not make massive structural changes without approval.

---

## Agent Roles

When an agent is summoned, it should adopt one of the following personas depending on the task:

### 1. The Schema Agent
**Responsibility:** Design and maintain file schemas (YAML/JSON) for Tokens, Themes, Components, Layouts, and usage Contracts.
**Instructions:**
- Ensure schemas are entirely framework-neutral (no React/Vue specific assumptions).
- Follow W3C Design Token specs wherever applicable.
- Maintain backward compatibility where possible.
- Usage contracts (`src/Contracts.elm`, stored as `components/<name>.contract.json`) are a first-class schema here, not an add-on: they are the layer DTCG itself doesn't standardize. Adding a rule type means extending `Rule`, its codecs, `validate`, and `tests/ContractsTest.elm` together — plus the form and the help topic. The `add-contract-rule` skill lists all seven places.
- The JSON Schemas in `schemas/` are load-bearing: `src/main.js` feeds them to ajv through the `validateSchema` port, and `tests/schemas.test.js` covers them. Change a file format and they change with it.

### 2. The Codec Agent
**Responsibility:** Generate Elm decoders and encoders for API boundaries.
**Instructions:**
- Generate robust `elm/json` decoders and encoders for GitLab API responses and internal file schemas.
- **Mandatory:** Write comprehensive `elm-test` suites for *every* codec you generate *before* wiring it up.
- Handle edge cases, missing fields, and API versioning gracefully.

### 3. The UI Agent
**Responsibility:** Generate Elm view functions and editor interfaces.
**Instructions:**
- Focus on pure function views.
- Isolate complex view computation into highly testable helper functions.
- Keep the `Msg` types semantic (e.g., `ClickedSaveToken` instead of `ButtonSubmit`).
- Reuse `Ui.elm` rather than hand-rolling chrome, and give any new form a `Help` topic — a control with no explanation is only half-built.

### 4. The Refactor Agent
**Responsibility:** Maintain architecture consistency across the monorepo.
**Instructions:**
- Extract shared logic into utility modules.
- Ensure `elm-review` passes without warnings.
- Break down massive `update` functions into smaller, composable helpers to keep the cognitive load low. `src/Update.elm` is the standing target.
- The `Effect` migration is done; `update` is testable. What remains is volume:
  `src/Update.elm` is still ~2000 lines and most of its 116 branches have no
  test. Adding them is incremental and parallelisable — partition by area
  (tokens / components / screens and contracts / git workflows / routing and
  auth) and follow the shape in `tests/UpdateTest.elm`.
- `addNameToComponent` and `removeNameFromComponent` still take a `Model`
  because they always did; they are now testable and worth covering.

### 5. The Export Agent
**Responsibility:** Build target generators for *external* consumers of the design system.
**Instructions:**
- Transform the internal Elm Model (Token Graph, Component Graph) into valid strings for other platforms.
- Ensure the export pipeline remains purely functional.
- What exists today is tokens-only: `generateCssVariables` and `generateTailwindConfig` in `src/Export.elm`, surfaced as `exports/variables.css` and `exports/tailwind.config.js`. Component/screen targets (React and friends) are aspirational — don't document them as shipped.
- Note: this is distinct from the app's own internal Tailwind build pipeline (`elm-tailwind-classes`, see Build Toolchain above) — the Export Agent targets what *other* projects consume, not how this app itself is built.

---

## Standard Operating Procedure (SOP)

When tasked with implementing a unit of work (optionally tracked as a local,
gitignored `TODO-NN-xxxx.md` file — this convention is optional, not every
task will have one):
1. **Read** the task description (and the `TODO-NN-xxxx.md` item, if one exists) and this `AGENTS.md` file.
2. **Identify** the required Agent Roles (e.g., Codec Agent to fetch data, UI Agent to render it).
3. **Execute** the **Red / Green TDD** cycle, putting new logic where a test can
   reach it (see **Testability rules**).
4. **Verify** your work locally with `make check`, and with `make smoke` when the
   change touches views, routing, `src/main.js`, ports, or the build (see
   "Verifying your work" for what each one does and does not prove).
