/**
 * Phase 9: end-to-end demonstration scenarios.
 *
 * For each representative user request this runs the full pipeline
 * (planner -> MCP design server -> SQLite rule store -> validator) and
 * commits, per scenario:
 *   request.json          the user request and matched intent
 *   retrieved-rules.json  the rules retrieved per step
 *   planning-trace.json   the full decision trace (tool calls + results)
 *   ast.json              the generated screens (one per step)
 *   validation.json       structural + semantic validation output
 *   render.html           a static, token-styled render of every screen
 * The decision trace is also persisted into the SQLite store, and the
 * audit log is written by the planner via the log_decision tool.
 *
 * A final negative scenario feeds a deliberately broken AST through the
 * validator to demonstrate rejection.
 */
import { mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { plan } from "@design-playground/planner";
import { DesignDb, repoRoot, defaultDbPath } from "@design-playground/design-db";
import { validateAst, astToHtmlDocument, type Screen } from "@design-playground/ui-ir";

interface ScenarioSpec {
  id: string;
  title: string;
  request: string;
}

const SCENARIOS: ScenarioSpec[] = [
  { id: "onboarding", title: "User onboarding", request: "I want to sign up and create a new account" },
  { id: "checkout", title: "Checkout", request: "I want to buy the items in my cart and pay" },
  { id: "subscription-upgrade", title: "Subscription upgrade", request: "upgrade my plan to pro" },
  { id: "account-settings", title: "Account settings", request: "change my account settings and maybe delete my account" },
  { id: "password-reset", title: "Password reset", request: "I forgot my password and I'm locked out" },
];

const tokensCss = readFileSync(join(repoRoot, "tokens/css/variables.css"), "utf8");
const scenariosRoot = join(repoRoot, "scenarios");

function renderDocument(title: string, screens: Screen[]): string {
  // Compose one document showing each step screen as a section.
  const sections = screens
    .map((s) => {
      const doc = astToHtmlDocument(s, "");
      const body = doc.slice(doc.indexOf("<main"), doc.indexOf("</body>"));
      return `<section class="dp-step"><div class="dp-step-label">Step: ${s.step}</div>${body}</section>`;
    })
    .join("\n");
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${title}</title>
<style>${tokensCss}
body{margin:0;background:var(--color-surface-muted,#f5f6f8);font-family:var(--typography-font-family-sans,system-ui,sans-serif)}
.dp-doc-head{padding:24px 32px;background:var(--color-surface-default,#fff);border-bottom:1px solid var(--color-border-default,#e2e4e8)}
.dp-step{border-bottom:1px dashed var(--color-border-default,#e2e4e8)}
.dp-step-label{padding:8px 32px;color:var(--color-text-secondary,#6b7280);font-size:13px;text-transform:uppercase;letter-spacing:.04em}
</style></head><body>
<div class="dp-doc-head"><h1>${title}</h1></div>
${sections}
</body></html>`;
}

async function main() {
  // Re-seed each run so audit log / traces start clean and deterministic.
  if (!existsSync(defaultDbPath)) {
    throw new Error("db/design.db missing - run `pnpm db:seed` first");
  }

  const index: Array<Record<string, unknown>> = [];

  for (const spec of SCENARIOS) {
    const dir = join(scenariosRoot, spec.id);
    mkdirSync(dir, { recursive: true });
    process.stdout.write(`\n# ${spec.title}: "${spec.request}"\n`);

    const result = await plan(spec.request, { scenario: spec.id, dbPath: defaultDbPath });

    const screens = result.steps.map((s) => s.ast);
    const allValid = result.valid;

    writeFileSync(
      join(dir, "request.json"),
      JSON.stringify({ id: spec.id, title: spec.title, request: spec.request, intent: result.intent, flowId: result.flowId, flowGoal: result.flowGoal }, null, 2),
    );
    writeFileSync(
      join(dir, "retrieved-rules.json"),
      JSON.stringify(
        result.steps.map((s) => ({ step: s.stepId, checksApplied: s.checksApplied, rules: s.retrievedRules })),
        null,
        2,
      ),
    );
    writeFileSync(join(dir, "planning-trace.json"), JSON.stringify(result.trace, null, 2));
    writeFileSync(join(dir, "ast.json"), JSON.stringify(screens, null, 2));
    writeFileSync(
      join(dir, "validation.json"),
      JSON.stringify(
        result.steps.map((s) => ({ step: s.stepId, valid: s.validation.valid, structural: s.validation.structural, semantic: s.validation.semantic })),
        null,
        2,
      ),
    );
    writeFileSync(join(dir, "render.html"), renderDocument(spec.title, screens));

    // Persist the decision trace into SQLite for governance/audit.
    const db = new DesignDb(defaultDbPath);
    db.saveDecisionTrace(spec.id, { request: spec.request, flowId: result.flowId, steps: result.steps.map((s) => ({ step: s.stepId, notes: s.notes, checksApplied: s.checksApplied, valid: s.validation.valid })) });
    db.close();

    const stepSummary = result.steps
      .map((s) => `${s.stepId}(${s.validation.valid ? "ok" : "FAIL"}, ${s.validation.semantic.warnCount}w)`)
      .join(", ");
    process.stdout.write(`  flow=${result.flowId} valid=${allValid} steps: ${stepSummary}\n`);

    index.push({ id: spec.id, title: spec.title, request: spec.request, flowId: result.flowId, steps: result.steps.length, valid: allValid });
  }

  // Negative scenario: a deliberately invalid AST must be rejected.
  const badDir = join(scenariosRoot, "_rejected");
  mkdirSync(badDir, { recursive: true });
  const badAst = JSON.parse(readFileSync(join(repoRoot, "ui-ir/examples/invalid-semantics.json"), "utf8"));
  const badResult = validateAst(badAst);
  writeFileSync(join(badDir, "ast.json"), JSON.stringify(badAst, null, 2));
  writeFileSync(join(badDir, "validation.json"), JSON.stringify(badResult, null, 2));
  writeFileSync(
    join(badDir, "request.json"),
    JSON.stringify({ id: "_rejected", title: "Rejected: malformed plan", note: "Demonstrates that an AST violating the design rules is rejected, never rendered.", valid: badResult.valid, errorCount: badResult.semantic.errorCount }, null, 2),
  );
  process.stdout.write(`\n# Negative scenario: invalid AST rejected = ${!badResult.valid} (${badResult.semantic.errorCount} errors)\n`);
  index.push({ id: "_rejected", title: "Rejected: malformed plan", valid: badResult.valid, errorCount: badResult.semantic.errorCount });

  writeFileSync(join(scenariosRoot, "index.json"), JSON.stringify(index, null, 2));
  process.stdout.write(`\nWrote ${SCENARIOS.length} scenarios + 1 rejection demo to scenarios/\n`);

  const anyFailed = index.some((s) => s.id !== "_rejected" && s.valid === false);
  if (anyFailed) {
    process.stderr.write("\nA positive scenario produced an invalid AST - failing.\n");
    process.exit(1);
  }
}

main();
