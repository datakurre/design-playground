{ pkgs, ... }:

{
  # Declarative development environment for the design-playground demo.
  # Everything needed to reproduce the pipeline locally comes from here;
  # do not install tools imperatively.

  packages = [
    pkgs.nodejs_22
    pkgs.pnpm
    pkgs.sqlite
    pkgs.jq
  ];

  # Single source of truth for the demo pipeline. Each script mirrors a
  # pnpm script so the pipeline also runs without devenv (plain pnpm).
  scripts = {
    setup.exec = "pnpm install";
    build-tokens.exec = "pnpm build:tokens";
    db-seed.exec = "pnpm db:seed";
    scenarios.exec = "pnpm scenarios";
    governance.exec = "pnpm governance";
    demo.exec = "pnpm --filter @design-playground/renderer dev";
    pipeline.exec = "pnpm pipeline";
  };

  enterShell = ''
    echo "design-playground dev shell"
    echo "  setup        install workspace dependencies"
    echo "  pipeline     run the full artifact pipeline (tokens -> db -> scenarios -> governance)"
    echo "  demo         start the React renderer demo app"
  '';

  enterTest = ''
    pnpm install
    pnpm pipeline
    pnpm test
  '';
}
