import { execSync } from "node:child_process";

/** Seed db/design.db once before the suite so db-backed tests have data. */
export default function setup() {
  execSync("pnpm build:tokens && pnpm db:seed", { stdio: "ignore" });
}
