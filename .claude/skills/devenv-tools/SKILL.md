---
name: devenv-tools
description: Get a tool, CLI or package into this project's environment, or diagnose one that is missing or behaving oddly. Use before running npm install, adding an Elm package, or concluding that a tool is unavailable — everything here comes from nix and devenv, not from a global install.
---

# Tooling in design-playground

Every tool comes from nix via devenv. Nothing is installed globally, and nothing
should be. `devenv shell` puts the whole toolchain on `PATH`; in the dev
container it is already active, so `make check` works directly and the
`devenv shell --` prefix is only needed on a host or in CI.

**Never run `npm install` in the project root.** `node_modules` is a symlink into
the nix store, created by `enterShell` in `devenv.nix`. Installing over it either
fails or silently desyncs you from what CI builds.

## Adding a tool

### A CLI that exists in nixpkgs

Add it to `packages` in `devenv.nix`. That is the whole procedure.

```nix
packages = [
  pkgs.entr
  pkgs.chromium
  # ...
];
```

Re-enter the shell (or re-run any `devenv shell -- …` command) to pick it up.
Prefer this over every other option.

### An npm CLI

Harder, because the npm tooling is itself a nix derivation, `pkgs/npm-tools.nix`,
built from `pkgs/package.json` and `pkgs/package-lock.json`. The dance:

1. `cd pkgs && npm install` to update `package-lock.json`.
2. Set `hash = pkgs.lib.fakeHash;` in the `fetchNpmDeps` block of
   `pkgs/npm-tools.nix`.
3. Run `devenv shell` — the build fails and prints the real sha256 under `got:`.
4. Paste that hash back in.
5. If the tool needs to be callable by name, add a `makeWrapper` stanza in
   `installPhase` alongside the ones for `vite`, `elm-test` and
   `elm-tailwind-classes`.

This needs network access. The comment at the top of `pkgs/npm-tools.nix` says
the same thing — keep the two in sync if you change the procedure.

### An Elm package

`elm-json install author/package`, which edits `elm.json`. Needs network (see
below). Ask before adding one: the project deliberately runs on a small
dependency set, and `elm-explorations/test` already covers what most testing
tasks need.

## The network, which is the thing that actually bites

The dev container has **no direct DNS**. All egress goes through an HTTP proxy
advertised in `HTTP_PROXY`/`HTTPS_PROXY`.

- `curl`, `git` and `nix` honour those variables.
- **Node does not, unless told.** `devenv.nix` sets `NODE_USE_ENV_PROXY = "1"`
  for this reason. Without it, any Node tool that fetches — most importantly
  `elm-review` solving the dependencies of the elm-tailwind-classes extractor
  config — fails with `getaddrinfo EAI_AGAIN package.elm-lang.org`. The
  consequence is not an error: `vite build` prints `CLASS EXTRACTION FAILED`,
  exits 0, and produces a stylesheet missing every dynamically composed class,
  i.e. every colour in the app. `make smoke` fails on this deliberately.

If you see a tool failing to resolve a hostname, this is why. Check you are in
the devenv shell before concluding the network is down.

## The Elm package cache is fragile

There is no vendored Elm package set. Elm packages live in two places:

- `~/.elm/0.19.1/packages` — the shared cache, outside the repo, empty in a fresh
  container.
- `elm-stuff/` — this project's compiled dependency interfaces (`d.dat`, `i.dat`),
  gitignored.

Between them the project compiles offline. Delete both and you need
`package.elm-lang.org` again. That is why `make clean` leaves `elm-stuff/` alone
and `make distclean` is a separate target with a warning.

If offline builds ever need to be guaranteed, the fix is to vendor the package
set into the nix store with `elm2nix` (already on `PATH`) plus
`elmPackages.fetchElmDeps`. That has not been done — it is a deliberate open
decision, not an oversight.

## Formatting and hooks

`treefmt` is configured in `devenv.nix` and currently formats **Nix files only** —
no formatter is wired up for `.js`, `.json`, `.css`, `.md` or `.yml`. Two
pre-commit hooks are installed from `devenv.nix`: `treefmt`, and `make check`. A
commit failing either is rejected, so run `make check` before you get there.
