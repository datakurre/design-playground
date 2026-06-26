{ pkgs, ... }:
let
  npmTools = pkgs.callPackage ./pkgs/npm-tools.nix { };

in
{

  packages = [
    pkgs.entr
    pkgs.git
    pkgs.nodejs_22
    pkgs.treefmt
    pkgs.elmPackages.elm-review
    pkgs.elmPackages.elm-json
    npmTools
  ];

  languages.elm.enable = true;

  dotenv.disableHint = true;

  env.NODE_PATH = "${npmTools}/lib/node_modules";

  enterShell = ''
    ln -sfn "${npmTools}/lib/node_modules" node_modules
    ln -sfn "${npmTools}/lib/node_modules" elm-app/node_modules

    echo ""
    echo "── template dev environment ─────────────────────────"
    echo "  GHC:    $(ghc --version)"
    echo "  Elm:    $(elm --version)"
    echo "  Node:   $(node --version)"
    echo "  Vite:   $(vite --version)"
    echo ""
    echo "  make dev      — generate data + start Vite dev server"
    echo "  make build    — generate data + production build"
    echo "  make dist-ci  — build CI/deploy output in build/"
    echo ""
  '';

  treefmt = {
    enable = true;
    config.programs = {
      nixpkgs-fmt.enable = true;
    };
  };

  git-hooks.hooks = {
    treefmt.enable = true;
    make-check = {
      enable = true;
      name = "make check";
      entry = "make check";
      language = "system";
      pass_filenames = false;
    };
  };
}
