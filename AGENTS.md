# AI Coding Agents Guide

Welcome to the Git-Native Design System Platform. This project heavily utilizes AI coding agents to overcome ecosystem gaps in Elm (e.g., boilerplate generation, JS interop, codecs, and API bindings).

This document serves as the prompt and instruction manual for any AI agent working on this codebase. When assigning tasks, explicitly invoke the relevant agent persona.

For what the app *is* and what it's for, see [README.md](./README.md). This file
is everything about changing it.

## Prerequisites

[Nix](https://nixos.org/) with [devenv](https://devenv.sh/). The dev shell pins
the whole toolchain (Node 22, Elm 0.19.1, elm-format, elm-test, elm-review,
elm-json, treefmt, and the npm tooling packaged in `pkgs/`); nothing is installed
globally.

```sh
devenv shell   # or let direnv load it automatically
make dev       # generates .elm-tailwind/, then starts the Vite dev server
```

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
| `make check`   | the full verify loop — see below                                                       |

### What `make check` actually runs

In order: `make gen` → `elm-format --validate src/ tests/` → `elm make
src/Main.elm --output=/dev/null` → `elm-test` → `elm-review`.

The two middle steps are not incidental:

- **`elm-format --validate`** reports rather than rewrites. Neither elm-test nor
  elm-review has an opinion about layout, so unformatted code used to reach main
  unnoticed. Fix what it finds with `elm-format --yes src/ tests/`.
- **`elm make src/Main.elm`** compiles the app entry point explicitly. elm-test
  only compiles the test modules and their dependencies, and elm-review parses
  rather than type-checks — neither reaches `src/Main.elm`, so without this a
  broken `Model` or view would pass `make check`.

Tests live in `tests/`; the elm-review configuration lives in `review/`.

### Git hooks

`devenv.nix` installs two pre-commit hooks: `treefmt` and `make check`. A commit
that fails either is rejected, so run `devenv shell -- make check` before you get
there.

### Deployment & CI

Pushes to `main` trigger `.github/workflows/deploy.yml`, which runs `make gen`,
`elm-test`, and `elm-review`, builds with `make dist-ci`, and publishes `dist/`
to GitHub Pages. The site is served under the `/design-playground/` base path,
set via `base` in `vite.config.js`.

Note that CI runs those steps individually rather than invoking `make check`, so
it does **not** run `elm-format --validate` or the explicit `elm make` of the
entry point. Local `make check` is the stricter gate — don't rely on CI to catch
formatting or a broken `Main`.

## Module map

Where things live, so you don't have to guess:

**Shell and plumbing**

- `src/Main.elm` — entry point, app bar, tab chrome, project picker
- `src/Update.elm` — the single `update` loop (~2400 lines; the Refactor Agent's
  standing assignment)
- `src/Types.elm` — `Model`, `Msg`, `Tab`
- `src/Route.elm` — fragment-based URL routing (`#/namespace/project/tab/item`);
  fragments, not paths, because GitHub Pages has no history fallback
- `src/Ui.elm` — shared chrome: buttons, panels, inputs, pills, context-help widgets
- `src/Help.elm` — the text of every in-app context-help topic

**Domain**

- `src/Tokens.elm`, `src/Themes.elm`, `src/Components.elm`, `src/Screens.elm`
- `src/Contracts.elm` — usage-contract schema, codecs, and `validate`
- `src/Export.elm` — CSS variables and Tailwind config generators
- `src/Templates.elm` — component, screen, and theme starter templates
- `src/TokenScale.elm` — starter token ramps; `src/TokenBrowse.elm` — grouping,
  search, filtering; `src/Naming.elm` — the one place that decides whether a typed
  name is usable; `src/Colors.elm` — hex parsing and contrast ratio;
  `src/Renderer.elm` — screen/component preview rendering

**Boundaries**

- `src/GitLab/` — REST bindings: `Branches`, `Commits`, `Files`,
  `MergeRequests`, `Projects`
- `src/Auth.elm` + `src/Ports.elm` — OAuth PKCE and the `localStorage` token cache

**Views**

- `src/Pages/` — one module per tab: `TokenStudio`, `ComponentRegistry`,
  `ScreenComposer`, `GitWorkflows`, `ExportPipeline`

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
- Usage contracts (`src/Contracts.elm`, stored as `components/<name>.contract.json`) are a first-class schema here, not an add-on: they are the layer DTCG itself doesn't standardize. Adding a rule type means extending `Rule`, its codecs, `validate`, and `tests/ContractsTest.elm` together.

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
3. **Execute** the **Red / Green TDD** cycle.
4. **Verify** your work locally using `devenv shell -- make check` (see Build Toolchain above for what that runs and why).
