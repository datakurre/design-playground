/**
 * Demonstrates that the DATABASE enforces design rules: each attempt
 * below violates an invariant and must be rejected by SQLite itself
 * (CHECK constraint, foreign key, or trigger). Exits non-zero if any
 * violation is accepted.
 */
import { copyFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DesignDb, defaultDbPath } from "@design-playground/design-db";

// Work on a throwaway copy so the committed design.db artifact stays
// deterministic - these attempts intentionally write to the database.
const source = process.env.DESIGN_DB_PATH ?? defaultDbPath;
const scratch = join(tmpdir(), `design-verify-${process.pid}.db`);
copyFileSync(source, scratch);
const { db } = new DesignDb(scratch);

// Ensure the audit log has at least one row, so the append-only
// UPDATE/DELETE triggers below actually have a row to fire on. (A
// trigger on zero matched rows would silently no-op, masking the test.)
db.prepare(
  "INSERT INTO audit_log (actor, event, scenario, detail) VALUES ('verify', 'intent', 'enforcement-check', '{}')",
).run();

interface Attempt {
  name: string;
  sql: string;
  params?: unknown[];
}

const attempts: Attempt[] = [
  {
    name: "destructive-action rule without confirmation requirement (trigger)",
    sql: `INSERT INTO rules (id, tag, category, severity, applies, title, description, requires_confirmation)
          VALUES ('rule-evil-delete', 'destructive-action', 'destructive-action', 'error', 'step',
                  'Delete without asking', 'Destructive action that skips confirmation entirely.', 0)`,
  },
  {
    name: "flow step referencing a non-existent component (foreign key)",
    sql: `INSERT INTO flow_step_components (flow_id, step_id, component_id)
          VALUES ('onboarding', 'account', 'hologram')`,
  },
  {
    name: "step rule-tag that matches no rule (trigger)",
    sql: `INSERT INTO flow_step_rule_tags (flow_id, step_id, tag)
          VALUES ('onboarding', 'account', 'made-up-tag')`,
  },
  {
    name: "error state without recovery guidance (CHECK)",
    sql: `INSERT INTO flow_errors (flow_id, code, message, recovery)
          VALUES ('checkout', 'oops', 'Something went wrong.', '')`,
  },
  {
    name: "rule with unknown severity (CHECK)",
    sql: `INSERT INTO rules (id, tag, category, severity, applies, title, description)
          VALUES ('rule-vague', 'misc', 'flow', 'meh', 'step', 'Vague', 'A rule with a severity outside the closed vocabulary.')`,
  },
  {
    name: "tampering with the audit log (append-only trigger)",
    sql: `UPDATE audit_log SET detail = '{}' WHERE id >= 0`,
  },
];

let accepted = 0;
for (const attempt of attempts) {
  try {
    db.prepare(attempt.sql).run(...(attempt.params ?? []));
    console.error(`ACCEPTED (BUG!)  ${attempt.name}`);
    accepted++;
  } catch (error) {
    console.log(`rejected ✓  ${attempt.name}`);
    console.log(`            ${(error as Error).message}`);
  }
}

db.close();
rmSync(scratch, { force: true });
if (accepted > 0) {
  console.error(`\n${accepted} violation(s) were accepted - schema enforcement is broken.`);
  process.exit(1);
}
console.log("\nAll violations rejected by SQLite - the rule store enforces its invariants.");
