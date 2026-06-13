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
    db-verify.exec = "pnpm db:verify";
    scenarios.exec = "pnpm scenarios";
    governance.exec = "pnpm governance";
    screenshots.exec = "pnpm screenshots";
    demo.exec = "pnpm --filter @design-playground/renderer dev";
    storybook.exec = "pnpm storybook";
    site.exec = "pnpm pipeline && pnpm site";
    pipeline.exec = "pnpm pipeline";
    check.exec = "pnpm typecheck && pnpm test";
  };

  enterShell = ''
    echo "design-playground dev shell"
    echo "  setup        install workspace dependencies"
    echo "  pipeline     run the full artifact pipeline (tokens -> db -> scenarios -> governance)"
    echo "  demo         start the React renderer demo app"
    echo "  storybook    start Storybook (component workbench + docs)"
    echo "  site         build the published Storybook site into site/"
  '';

  enterTest = ''
    pnpm install
    pnpm pipeline
    pnpm test
  '';
}
