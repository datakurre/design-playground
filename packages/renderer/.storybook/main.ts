import type { StorybookConfig } from "@storybook/react-vite";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../../..");

/**
 * Storybook is the published design system + documentation site and the
 * component workbench for design and engineering teams: browse every
 * primitive and variant, read the docs, visually approve screens, and run
 * interaction + accessibility tests. Stories render through the SAME
 * `RenderNode` bindings and the SAME generated design-token CSS as the
 * production renderer, so what a team approves here is exactly what ships.
 *
 * The static build is the GitHub Pages site. Storybook emits relative
 * asset URLs, so it works unchanged under the project sub-path
 * (https://datakurre.github.io/design-playground/).
 */
const config: StorybookConfig = {
  stories: ["../src/**/*.mdx", "../src/**/*.stories.@(ts|tsx)"],
  addons: ["@storybook/addon-essentials", "@storybook/addon-a11y"],
  framework: {
    name: "@storybook/react-vite",
    options: {},
  },
  core: {
    disableTelemetry: true,
  },
  // Allow stories/docs to import committed sources from outside the
  // renderer package (design tokens, docs markdown, generated artifacts).
  viteFinal: (cfg) => {
    cfg.server = cfg.server ?? {};
    cfg.server.fs = { ...(cfg.server.fs ?? {}), allow: [repoRoot] };
    return cfg;
  },
};

export default config;
