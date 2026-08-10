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
    pkgs.elmPackages.elm
    pkgs.elmPackages.elm-format
    pkgs.elmPackages.elm-test
    pkgs.elmPackages.elm-review
    pkgs.elmPackages.elm-json
    pkgs.chromium
    # scripts/smoke.sh screenshots the app in headless chromium. Without a font
    # on the system every glyph renders as a blank box, which makes the
    # screenshots useless for judging whether anything actually rendered.
    # Liberation covers the sans-serif stack Tailwind's preflight asks for, so
    # the screenshots look like the deployed site rather than falling back to
    # serif for everything.
    pkgs.dejavu_fonts
    pkgs.liberation_ttf
    npmTools
  ];

  languages.elm.enable = true;

  dotenv.disableHint = true;

  env.NODE_PATH = "${npmTools}/lib/node_modules";

  env.FONTCONFIG_FILE = pkgs.makeFontsConf {
    fontDirectories = [ pkgs.dejavu_fonts pkgs.liberation_ttf ];
  };

  # The dev container has no direct DNS — everything egresses through an HTTP
  # proxy advertised in HTTP_PROXY/HTTPS_PROXY. curl and nix honour those; Node
  # does not, unless asked. Without this, `elm-review` cannot reach
  # package.elm-lang.org to solve the dependencies of the elm-tailwind-classes
  # extractor config, so class extraction fails, `vite build` prints a warning
  # and still exits 0, and you get a stylesheet with every dynamically composed
  # class missing — every colour in the app. `make smoke` now fails loudly on
  # that, but this is what prevents it in the first place.
  env.NODE_USE_ENV_PROXY = "1";

  enterShell = ''
    ln -sfn "${npmTools}/lib/node_modules" node_modules

    echo ""
    echo "── template dev environment ─────────────────────────"
    echo "  Elm:    $(elm --version)"
    echo "  Node:   $(node --version)"
    echo "  Vite:   $(vite --version)"
    echo ""
    echo "  make dev      — start the Vite dev server"
    echo "  make check    — the full gate: format, compile, test, review"
    echo "  make test     — tests only (make test T=Contracts for one file)"
    echo "  make fmt      — fix what check reports"
    echo "  make smoke    — build and render the app in headless chromium"
    echo "  make watch    — re-run tests on every Elm change"
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
