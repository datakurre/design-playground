/**
 * Seeds db/design.db from the JSON sources of truth:
 *   tokens/design-tokens.json, components/*.json, flows/*.json,
 *   rules/design-rules.json
 *
 * The seed is intentionally thin: it does NOT re-validate the data in
 * application code. The SQLite schema (CHECK constraints, foreign
 * keys, triggers) is what accepts or rejects the design knowledge -
 * run `pnpm db:verify` to see it reject invalid data.
 */
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { DesignDb, repoRoot, defaultDbPath } from "@design-playground/design-db";
import { flattenTokens } from "@design-playground/tokens-build";

const dbPath = process.env.DESIGN_DB_PATH ?? defaultDbPath;
rmSync(dbPath, { force: true });
const { db } = new DesignDb(dbPath, { create: true });

function loadJson(path: string): any {
  const data = JSON.parse(readFileSync(join(repoRoot, path), "utf8"));
  delete data.$schema;
  return data;
}

const seed = db.transaction(() => {
  // tokens
  const insertToken = db.prepare(
    "INSERT INTO tokens (path, type, value, description) VALUES (?, ?, ?, ?)",
  );
  const tokens = flattenTokens(loadJson("tokens/design-tokens.json"));
  for (const t of tokens) {
    insertToken.run(t.path, t.type, JSON.stringify(t.value), t.description ?? null);
  }

  // rules (before flow step tags: the step_tag_resolves_to_rule trigger
  // requires rules to exist first)
  const insertRule = db.prepare(
    `INSERT INTO rules (id, tag, category, severity, applies, title, description,
                        machine_check, requires_confirmation, wcag)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  );
  for (const r of loadJson("rules/design-rules.json").rules) {
    insertRule.run(
      r.id, r.tag, r.category, r.severity, r.applies, r.title, r.description,
      r.machineCheck ?? null, r.requiresConfirmation ? 1 : 0, r.wcag ?? null,
    );
  }

  // components
  const insertComponent = db.prepare(
    "INSERT INTO components (id, purpose, metadata) VALUES (?, ?, ?)",
  );
  const insertVariant = db.prepare(
    "INSERT INTO component_variants (component_id, name, usage) VALUES (?, ?, ?)",
  );
  const insertA11y = db.prepare(
    "INSERT INTO component_a11y (id, component_id, requirement, wcag) VALUES (?, ?, ?, ?)",
  );
  const insertConstraint = db.prepare(
    "INSERT INTO component_constraints (id, component_id, rule, machine_check) VALUES (?, ?, ?, ?)",
  );
  const componentFiles = readdirSync(join(repoRoot, "components"))
    .filter((f) => f.endsWith(".json") && !f.endsWith(".schema.json"))
    .sort();
  for (const file of componentFiles) {
    const c = loadJson(join("components", file));
    insertComponent.run(c.id, c.purpose, JSON.stringify(c));
    for (const v of c.variants) insertVariant.run(c.id, v.name, v.usage);
    for (const a of c.accessibility) insertA11y.run(a.id, c.id, a.requirement, a.wcag ?? null);
    for (const k of c.constraints) insertConstraint.run(k.id, c.id, k.rule, k.machineCheck ?? null);
  }

  // flows
  const insertFlow = db.prepare(
    "INSERT INTO flows (id, goal, success_title, success_message) VALUES (?, ?, ?, ?)",
  );
  const insertIntent = db.prepare(
    "INSERT INTO flow_intents (flow_id, phrase) VALUES (?, ?)",
  );
  const insertStep = db.prepare(
    "INSERT INTO flow_steps (flow_id, step_id, position, title, definition) VALUES (?, ?, ?, ?, ?)",
  );
  const insertStepComponent = db.prepare(
    "INSERT INTO flow_step_components (flow_id, step_id, component_id) VALUES (?, ?, ?)",
  );
  const insertStepTag = db.prepare(
    "INSERT INTO flow_step_rule_tags (flow_id, step_id, tag) VALUES (?, ?, ?)",
  );
  const insertError = db.prepare(
    "INSERT INTO flow_errors (flow_id, code, message, recovery) VALUES (?, ?, ?, ?)",
  );
  const flowFiles = readdirSync(join(repoRoot, "flows"))
    .filter((f) => f.endsWith(".json") && !f.endsWith(".schema.json"))
    .sort();
  for (const file of flowFiles) {
    const f = loadJson(join("flows", file));
    insertFlow.run(f.id, f.goal, f.success.title, f.success.message);
    for (const phrase of f.intents) insertIntent.run(f.id, phrase);
    f.steps.forEach((s: any, index: number) => {
      insertStep.run(f.id, s.id, index, s.title, JSON.stringify(s));
      for (const c of s.components) insertStepComponent.run(f.id, s.id, c);
      for (const tag of s.ruleTags) insertStepTag.run(f.id, s.id, tag);
    });
    for (const e of f.errors) insertError.run(f.id, e.code, e.message, e.recovery);
  }
});

seed();

const count = (table: string) =>
  (db.prepare(`SELECT count(*) AS n FROM ${table}`).get() as { n: number }).n;
console.log(
  `Seeded ${dbPath}:`,
  `${count("tokens")} tokens,`,
  `${count("components")} components,`,
  `${count("flows")} flows (${count("flow_steps")} steps),`,
  `${count("rules")} rules`,
);
db.close();
