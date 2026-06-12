---
name: nix-cmd
description: Run ad hoc, one-off commands with nix without polluting the environment. Use when a tool is needed once (format a file, inspect an archive, convert an image) and does not belong in devenv.nix.
---

# Ad hoc commands with nix

For one-off needs, run tools straight from nixpkgs instead of installing
them. Nothing is added to the project environment or the system; the
tool is fetched into the nix store and garbage-collected later.

## Patterns

Run a package's default executable:

```sh
nix run nixpkgs#jq -- '.version' package.json
nix run nixpkgs#nodePackages.prettier -- --write README.md
```

Open a transient shell with one or more tools available:

```sh
nix shell nixpkgs#sqlite -c sqlite3 db/design.db '.tables'
nix shell nixpkgs#imagemagick nixpkgs#optipng -c sh -c 'convert a.png b.gif'
```

Find the right attribute name:

```sh
nix search nixpkgs <keyword>
```

(or https://search.nixos.org/packages)

## Choosing between nix-cmd and devenv

- Needed **once** (inspection, conversion, formatting an odd file):
  use `nix run` / `nix shell` as above.
- Needed **repeatedly** or by CI/other contributors: promote it to
  `devenv.nix` (`packages` or `scripts`) — see the `devenv` skill.

## Notes

- Prefer `nix run nixpkgs#pkg -- args` over `nix-env -i` (never use
  `nix-env -i`; it mutates the user profile).
- If flakes are disabled, the legacy equivalent is
  `nix-shell -p <pkg> --run '<cmd>'`.
- If `nix` is unavailable in the current sandbox, fall back to tools
  already present, and do not install substitutes globally.
