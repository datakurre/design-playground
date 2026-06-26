# Devenv and Nix Skills

This document defines standard operating procedures (skills) for using `devenv` and `nix run` within a repository.

## Pre-requisite Check
If the repository contains a `devenv.nix` file in its root, you can assume that both `devenv` and `nix` are available and configured.

## 1. Ad Hoc Execution with Nix
If you need to run a tool or command just once (e.g., executing a script, running a linter one-off, or inspecting a specific output) without permanently adding it to the environment:

Use `nix run` from the `nixpkgs` registry:
```bash
nix run nixpkgs#<package-name> -- <arguments>
```

Example:
```bash
nix run nixpkgs#cowsay -- "Hello world!"
nix run nixpkgs#jq -- '.' data.json
```

## 2. Adding Tools to the Dev Environment
If a tool should be available to all developers working on the repository, you should permanently add it to the `devenv.nix` configuration.

**Step 1: Search for the package**
You can search for available packages using:
```bash
devenv search <query>
```
Alternatively, search for packages on the web via search tools if necessary. Typically, package names match their Nixpkgs attribute (e.g., `pkgs.ripgrep`, `pkgs.jq`).

**Step 2: Modify devenv.nix**
Edit the `devenv.nix` file in the root of the repository. Locate the `packages = [ ... ];` list and add the desired package attribute to it.

```nix
{ pkgs, ... }:
{
  packages = [
    pkgs.git
    # Add your new package here:
    pkgs.jq
  ];
}
```

**Step 3: Test the environment**
After modifying `devenv.nix`, the changes will typically apply automatically for users using `direnv`, or when they run `devenv shell`. To test the change on your end, simply run the tool in the shell to ensure it works.

## Summary of Commands
- `nix run nixpkgs#<pkg> -- <args>`: Run a package once.
- `devenv search <query>`: Find a package in `devenv`.
- `devenv up`: Start processes defined in `devenv.nix`.
- `devenv test`: Run tests defined in `devenv.nix`.
