import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../..");

export default defineConfig({
  root: here,
  plugins: [react()],
  server: { fs: { allow: [repoRoot] } },
  build: { outDir: "dist", emptyOutDir: true },
});
