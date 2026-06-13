/**
 * Typed access layer over the SQLite rule store (db/design.db).
 * All reads are plain SQL over seeded data, so retrieval is
 * deterministic: same database, same query, same result.
 */
import Database from "better-sqlite3";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../..");
export const defaultDbPath = join(repoRoot, "db/design.db");

export interface Rule {
  id: string;
  tag: string;
  category: string;
  severity: "error" | "warn" | "info";
  applies: "step" | "global";
  title: string;
  description: string;
  machine_check: string | null;
  requires_confirmation: 0 | 1;
  wcag: string | null;
}

export interface FlowStepRow {
  flow_id: string;
  step_id: string;
  position: number;
  title: string;
  definition: string;
}

export type AuditEvent =
  | "intent"
  | "retrieval"
  | "plan"
  | "validation"
  | "render"
  | "rejection";

export class DesignDb {
  readonly db: Database.Database;

  constructor(path: string = defaultDbPath, options: { create?: boolean } = {}) {
    this.db = new Database(path, { fileMustExist: !options.create });
    this.db.pragma("foreign_keys = ON");
    if (options.create) {
      this.db.exec(readFileSync(join(repoRoot, "db/schema.sql"), "utf8"));
    }
  }

  close(): void {
    this.db.close();
  }

  getTokens(prefix?: string): Array<{ path: string; type: string; value: unknown; description: string | null }> {
    const rows = prefix
      ? this.db
          .prepare("SELECT * FROM tokens WHERE path LIKE ? || '%' ORDER BY path")
          .all(prefix)
      : this.db.prepare("SELECT * FROM tokens ORDER BY path").all();
    return (rows as Array<{ path: string; type: string; value: string; description: string | null }>).map(
      (r) => ({ ...r, value: JSON.parse(r.value) }),
    );
  }

  listComponents(): Array<{ id: string; purpose: string }> {
    return this.db.prepare("SELECT id, purpose FROM components ORDER BY id").all() as Array<{
      id: string;
      purpose: string;
    }>;
  }

  getComponent(id: string): Record<string, unknown> | undefined {
    const row = this.db.prepare("SELECT metadata FROM components WHERE id = ?").get(id) as
      | { metadata: string }
      | undefined;
    return row ? (JSON.parse(row.metadata) as Record<string, unknown>) : undefined;
  }

  listFlows(): Array<{ id: string; goal: string; intents: string[] }> {
    const flows = this.db.prepare("SELECT id, goal FROM flows ORDER BY id").all() as Array<{
      id: string;
      goal: string;
    }>;
    const intents = this.db
      .prepare("SELECT flow_id, phrase FROM flow_intents ORDER BY flow_id, phrase")
      .all() as Array<{ flow_id: string; phrase: string }>;
    return flows.map((f) => ({
      ...f,
      intents: intents.filter((i) => i.flow_id === f.id).map((i) => i.phrase),
    }));
  }

  getFlow(id: string):
    | {
        id: string;
        goal: string;
        success: { title: string; message: string };
        steps: Array<Record<string, unknown> & { id: string; title: string; ruleTags: string[] }>;
        errors: Array<{ code: string; message: string; recovery: string }>;
      }
    | undefined {
    const flow = this.db.prepare("SELECT * FROM flows WHERE id = ?").get(id) as
      | { id: string; goal: string; success_title: string; success_message: string }
      | undefined;
    if (!flow) return undefined;
    const steps = this.db
      .prepare("SELECT * FROM flow_steps WHERE flow_id = ? ORDER BY position")
      .all(id) as FlowStepRow[];
    const errors = this.db
      .prepare("SELECT code, message, recovery FROM flow_errors WHERE flow_id = ? ORDER BY code")
      .all(id) as Array<{ code: string; message: string; recovery: string }>;
    return {
      id: flow.id,
      goal: flow.goal,
      success: { title: flow.success_title, message: flow.success_message },
      steps: steps.map((s) => JSON.parse(s.definition)),
      errors,
    };
  }

  /** Rules bound to a step via its tags, plus all global rules. */
  getRulesForTags(tags: string[]): Rule[] {
    const placeholders = tags.map(() => "?").join(", ");
    const sql =
      tags.length > 0
        ? `SELECT * FROM rules WHERE applies = 'global' OR tag IN (${placeholders}) ORDER BY severity, id`
        : "SELECT * FROM rules WHERE applies = 'global' ORDER BY severity, id";
    return this.db.prepare(sql).all(...tags) as Rule[];
  }

  getAllRules(): Rule[] {
    return this.db.prepare("SELECT * FROM rules ORDER BY id").all() as Rule[];
  }

  logAudit(actor: string, event: AuditEvent, scenario: string | null, detail: unknown): number {
    const result = this.db
      .prepare("INSERT INTO audit_log (actor, event, scenario, detail) VALUES (?, ?, ?, ?)")
      .run(actor, event, scenario, JSON.stringify(detail));
    return Number(result.lastInsertRowid);
  }

  getAuditLog(scenario?: string): Array<{
    id: number;
    ts: string;
    actor: string;
    event: AuditEvent;
    scenario: string | null;
    detail: unknown;
  }> {
    const rows = scenario
      ? this.db.prepare("SELECT * FROM audit_log WHERE scenario = ? ORDER BY id").all(scenario)
      : this.db.prepare("SELECT * FROM audit_log ORDER BY id").all();
    return (rows as Array<{ id: number; ts: string; actor: string; event: AuditEvent; scenario: string | null; detail: string }>).map(
      (r) => ({ ...r, detail: JSON.parse(r.detail) }),
    );
  }

  saveDecisionTrace(scenario: string, trace: unknown): void {
    this.db
      .prepare("INSERT INTO decision_traces (scenario, trace) VALUES (?, ?)")
      .run(scenario, JSON.stringify(trace));
  }

  getDecisionTraces(): Array<{ id: number; scenario: string; trace: unknown }> {
    const rows = this.db.prepare("SELECT * FROM decision_traces ORDER BY id").all() as Array<{
      id: number;
      scenario: string;
      trace: string;
    }>;
    return rows.map((r) => ({ ...r, trace: JSON.parse(r.trace) }));
  }
}
