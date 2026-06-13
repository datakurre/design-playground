import { describe, it, expect, afterAll } from "vitest";
import { execSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { rmSync } from "node:fs";
import { DesignDb, defaultDbPath } from "@design-playground/design-db";

const db = new DesignDb(defaultDbPath);
afterAll(() => db.close());

describe("deterministic retrieval", () => {
  it("matches free text to the right flow", () => {
    expect(db.matchIntent("I forgot my password and I'm locked out").flowId).toBe("password-reset");
    expect(db.matchIntent("I want to upgrade my plan to pro").flowId).toBe("subscription-upgrade");
  });

  it("is deterministic for the same input", () => {
    const a = db.matchIntent("delete my account");
    const b = db.matchIntent("delete my account");
    expect(a).toEqual(b);
  });

  it("always includes global rules with step rules", () => {
    const rules = db.getRulesForTags(["destructive-action"]);
    const ids = rules.map((r) => r.id);
    expect(ids).toContain("rule-destructive-needs-confirmation"); // step rule
    expect(ids).toContain("rule-single-primary-action"); // global rule
  });
});

describe("schema-enforced invariants", () => {
  const scratch = join(tmpdir(), `design-test-${process.pid}.db`);
  execSync(`DESIGN_DB_PATH='${scratch}' pnpm db:seed`, { stdio: "ignore" });
  const t = new DesignDb(scratch);
  afterAll(() => {
    t.close();
    rmSync(scratch, { force: true });
  });

  it("rejects a destructive rule without confirmation (trigger)", () => {
    expect(() =>
      t.db
        .prepare(
          `INSERT INTO rules (id, tag, category, severity, applies, title, description, requires_confirmation)
           VALUES ('rule-x','destructive-action','destructive-action','error','step','X','A destructive rule with no confirmation requirement.',0)`,
        )
        .run(),
    ).toThrow();
  });

  it("rejects a flow step referencing a missing component (foreign key)", () => {
    expect(() =>
      t.db.prepare(`INSERT INTO flow_step_components (flow_id, step_id, component_id) VALUES ('onboarding','account','nope')`).run(),
    ).toThrow();
  });

  it("rejects tampering with the append-only audit log", () => {
    t.logAudit("test", "intent", "t", { ok: true });
    expect(() => t.db.prepare("UPDATE audit_log SET actor='hacker'").run()).toThrow(/append-only/);
  });
});
