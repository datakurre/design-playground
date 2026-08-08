# design-playground

A Git-native design system platform: a browser-only Elm application for
editing design tokens, themes, components, and screen layouts, with **no
backend of its own**. All persistence goes straight through the GitLab REST
API — the backend is Git.

## What it is

The app is an editor and workbench for a design system that lives entirely
as files in a Git repository, authenticated and read/written via GitLab's
API (OAuth PKCE, no server in between). It covers:

- **Token Studio** (`src/Pages/TokenStudio.elm`) — create and edit W3C
  Design Token spec tokens, including composite tokens.
- **Theme Management** (`src/Themes.elm`) — manage themes built from tokens.
- **Component Registry** (`src/Pages/ComponentRegistry.elm`) — scaffold and
  register components (e.g. Button, Card).
- **Screen Composer** (`src/Pages/ScreenComposer.elm`) — compose screens
  from nested layouts.
- **Export Pipeline** (`src/Pages/ExportPipeline.elm`) — transform tokens
  and components into external targets (CSS variables, Tailwind, React).
- **Git Workflows** (`src/Pages/GitWorkflows.elm`) — branch, commit, and
  open merge requests against GitLab directly from the UI.

## Tech stack

- **Elm 0.19.1** — the application itself (`elm.json`)
- **Vite 7** — build tool, via `vite-plugin-elm`
- **Tailwind CSS v4** with `elm-tailwind-classes`, which generates a
  type-safe Tailwind API into `.elm-tailwind/` — a required `elm.json`
  source directory, so this generation step must run before Elm, elm-test,
  or elm-review can compile anything
- **elm-test** / **elm-review** — tests and linting (lint config in
  `review/`)
- **devenv / Nix** — reproducible dev shell (Node 22, Elm toolchain,
  Chromium for headless test runs, git-hooks running `make check` and
  `treefmt` before each commit)

## Prerequisites

[Nix](https://nixos.org/) with [devenv](https://devenv.sh/) installed.

## Getting started

```sh
devenv shell   # or let direnv load it automatically
make dev       # generates .elm-tailwind/, then starts the Vite dev server
```

## Available commands

All defined in the `Makefile`:

| Command         | What it does                                              |
| --------------- | ---------------------------------------------------------- |
| `make gen`      | Generate the typed Tailwind Elm API into `.elm-tailwind/` (required before any Elm tooling runs) |
| `make dev`      | `gen` + start the Vite dev server                          |
| `make build`    | `gen` + production Vite build                               |
| `make dist-ci`  | `gen` + Vite build for CI/deploy, output in `dist/`         |
| `make check`    | `gen` + `elm-test` + `elm-review`                           |

## Testing & linting

`make check` runs the full verify loop (generate → test → lint). Tests live
in `tests/`; the elm-review configuration lives in `review/`.

## Deployment

Pushes to `main` trigger `.github/workflows/deploy.yml`, which runs tests
and lint, builds the app with `make dist-ci`, and publishes it to GitHub
Pages. The site is served under the `/design-playground/` base path,
configured in `vite.config.js`.

## Project structure

```
src/
├── Main.elm            # entry point, wires pages together
├── Auth.elm, Auth/      # GitLab OAuth PKCE
├── GitLab/              # GitLab REST API bindings (branches, commits, files, MRs, projects)
├── Pages/                # TokenStudio, ComponentRegistry, ScreenComposer, ExportPipeline, GitWorkflows
├── Tokens.elm, Themes.elm, Components.elm, Screens.elm, Export.elm
└── main.js, style.css
tests/                   # elm-test suites
review/                  # elm-review configuration
pkgs/                    # Nix-packaged npm toolchain used by devenv
```

## AI coding agents

This project makes heavy use of AI coding agents. See [AGENTS.md](./AGENTS.md)
for agent personas, conventions, and the standard operating procedure.

## Where this is headed

This project is also an exploration of the W3C Design Tokens standard and
what's missing between design tokens and fully machine-readable,
agent-enforceable design guides. See [ROADMAP.md](./ROADMAP.md) for that
thinking.
