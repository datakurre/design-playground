/**
 * Builds the GitHub Pages site into `site/`.
 *
 * The site IS Storybook: it is the published design system + documentation
 * (Foundations: Introduction, Architecture, Governance, Schemas, Design
 * Tokens), the browsable component workbench (Components/*), and the live,
 * validated generated screens (Screens/*). Stories render through the same
 * bindings and design-token CSS as the production renderer, so the
 * published site is faithful to what ships.
 *
 * Storybook emits relative asset URLs, so the output works unchanged under
 * the project sub-path (https://datakurre.github.io/design-playground/).
 *
 * The committed JSON/markdown artifacts are also copied alongside Storybook
 * so they remain directly fetchable (e.g. /governance/audit-log.json).
 *
 *   pnpm site        # after `pnpm pipeline` (so Screens have data)
 */
import { execSync } from "node:child_process";
import { mkdirSync, writeFileSync, cpSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";
import { repoRoot } from "@design-playground/design-db";

const site = join(repoRoot, "site");

function buildStorybook() {
  console.log("Building Storybook into site/ ...");
  execSync(`pnpm --filter @design-playground/renderer build-storybook -o ${site}`, {
    cwd: repoRoot,
    stdio: "inherit",
    env: { ...process.env, STORYBOOK_DISABLE_TELEMETRY: "1" },
  });
}

function copyArtifacts() {
  // Keep the committed, browsable artifacts directly fetchable from the
  // published site for anyone who wants the raw JSON/markdown.
  for (const dir of ["scenarios", "governance", "tokens", "components", "flows", "rules", "ui-ir"]) {
    const from = join(repoRoot, dir);
    if (existsSync(from)) cpSync(from, join(site, dir), { recursive: true });
  }
}

function main() {
  rmSync(site, { recursive: true, force: true });
  mkdirSync(site, { recursive: true });
  buildStorybook();
  // Disable Jekyll so files/dirs starting with _ (e.g. scenarios/_rejected)
  // are served verbatim.
  writeFileSync(join(site, ".nojekyll"), "");
  copyArtifacts();
  console.log(`Site (Storybook) built into ${site}/`);
}

main();
