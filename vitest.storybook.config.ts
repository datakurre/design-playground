import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

/**
 * Runs Storybook stories as tests with no browser, using the official
 * "portable stories" API: each story is rendered in jsdom and its `play`
 * function (interaction + structural assertions) is executed. This is the
 * browserless counterpart to the Storybook test-runner, so component
 * behaviour is verified in CI as part of `pnpm test`.
 */
export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    include: ["packages/renderer/src/**/*.story-test.tsx"],
    testTimeout: 20000,
  },
});
