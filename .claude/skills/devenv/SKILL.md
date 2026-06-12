---
name: devenv
description: Manage this project's declarative development environment with devenv.sh. Use when adding tools, languages, services, environment variables, or repeatable commands to the project — edit devenv.nix instead of installing anything imperatively.
---

# Declarative development environment with devenv.sh

This project defines its development environment declaratively in
`devenv.nix` (with inputs pinned in `devenv.yaml` and `devenv.lock`).
The environment is the contract for reproducibility: if a tool is needed
to build, test, or run the project, it belongs in `devenv.nix`.

## Rules

1. **Never install tools imperatively** (`apt install`, `npm i -g`,
   `pip install --user`, `curl | sh`). Add them to `devenv.nix` instead.
2. **Project-language dependencies stay in their package manager**
   (`package.json`, `pyproject.toml`); `devenv.nix` provides the
   toolchain (node, pnpm, python, sqlite, …), not libraries.
3. **Repeatable commands become `scripts.<name>.exec`** so they are
   discoverable and identical for every contributor and agent.
4. For one-off commands that should NOT become part of the environment,
   use the `nix-cmd` skill instead.

## Common edits to devenv.nix

Add a CLI tool:

```nix
packages = [ pkgs.nodejs_22 pkgs.pnpm pkgs.sqlite ];
```

Enable a language toolchain:

```nix
languages.typescript.enable = true;
languages.python = { enable = true; version = "3.11"; };
```

Define a named script (preferred over documenting shell one-liners):

```nix
scripts.db-seed.exec = "pnpm db:seed";
```

Long-running dev processes (run all with `devenv up`):

```nix
processes.demo.exec = "pnpm --filter renderer dev";
```

Services (databases etc.) when needed:

```nix
services.postgres.enable = true;
```

Environment variables:

```nix
env.DATABASE_PATH = "db/design.db";
```

## Verifying changes

- `devenv shell -- <cmd>` — run a command inside the environment
  (e.g. `devenv shell -- node --version`) to verify a `devenv.nix` edit.
- `devenv test` — runs the `enterTest` block; keep it green.
- `devenv up` — starts declared processes/services.
- Search available packages at https://search.nixos.org/packages or with
  `nix search nixpkgs <name>`.

If `devenv` is not installed in the current sandbox, still keep
`devenv.nix` authoritative and in sync with reality: make the change
declaratively, then mirror it with the tools available (e.g. pnpm
scripts), and note any divergence in the commit message.
