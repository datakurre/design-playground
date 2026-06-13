/**
 * The agent planner. It is a Model Context Protocol *client*: it never
 * touches the database directly, only the design server's tools. Given a
 * natural-language request it:
 *   1. interprets intent      -> match_intent
 *   2. retrieves the flow     -> get_flow
 *   3. retrieves step rules   -> get_rules
 *   4. plans a screen per step (buildScreen, honouring rules by construction)
 *   5. checks constraints     -> validate_ast (scoped to the retrieved rules)
 *   6. records every step in an append-only audit log -> log_decision
 * and returns the generated ASTs plus a full decision trace. The planner
 * is deterministic: same request, same database, same plan.
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import type { Screen, ValidationResult } from "@design-playground/ui-ir";
import { buildScreen, type FlowStep, type FlowMeta } from "./build-screen.js";

export interface RetrievedRule {
  id: string;
  tag: string;
  category: string;
  severity: string;
  title: string;
  machine_check: string | null;
}

export interface PlannedStep {
  stepId: string;
  title: string;
  retrievedRules: RetrievedRule[];
  checksApplied: string[];
  notes: string[];
  ast: Screen;
  validation: ValidationResult;
}

export interface TraceEvent {
  step: string;
  action: string;
  tool?: string;
  detail: unknown;
}

export interface PlanResult {
  request: string;
  scenario: string;
  intent: { flowId: string | null; score: number; ranked: unknown };
  flowId: string;
  flowGoal: string;
  steps: PlannedStep[];
  trace: TraceEvent[];
  valid: boolean;
}

function parse<T>(result: unknown): T {
  const content = (result as { content: Array<{ type: string; text: string }> }).content;
  return JSON.parse(content[0].text) as T;
}

export interface PlanOptions {
  scenario?: string;
  serverCommand?: string;
  serverArgs?: string[];
  dbPath?: string;
}

export async function plan(request: string, options: PlanOptions = {}): Promise<PlanResult> {
  const scenario = options.scenario ?? "adhoc";
  const transport = new StdioClientTransport({
    command: options.serverCommand ?? "npx",
    args: options.serverArgs ?? ["tsx", "packages/mcp-server/src/server.ts"],
    env: {
      ...(process.env as Record<string, string>),
      ...(options.dbPath ? { DESIGN_DB_PATH: options.dbPath } : {}),
    },
  });
  const client = new Client({ name: "design-planner", version: "0.1.0" });
  await client.connect(transport);

  const trace: TraceEvent[] = [];
  const call = async <T>(tool: string, args: Record<string, unknown>, step: string, action: string): Promise<T> => {
    const result = parse<T>(await client.callTool({ name: tool, arguments: args }));
    trace.push({ step, action, tool, detail: result });
    return result;
  };
  const log = (event: string, detail: unknown) =>
    client.callTool({
      name: "log_decision",
      arguments: { actor: "planner", event, scenario, detail },
    });

  try {
    // 1. intent
    const intent = await call<{ flowId: string | null; score: number; ranked: unknown }>(
      "match_intent",
      { text: request },
      "intent",
      "interpret request",
    );
    await log("intent", { request, matched: intent.flowId, score: intent.score });
    if (!intent.flowId) {
      throw new Error(`Could not match request to a known flow: "${request}"`);
    }

    // 2. flow
    const flow = await call<{
      id: string;
      goal: string;
      steps: FlowStep[];
    }>("get_flow", { id: intent.flowId }, "retrieval", "load flow");

    const flowMeta: FlowMeta = { id: flow.id, goal: flow.goal };
    const steps: PlannedStep[] = [];

    for (const step of flow.steps) {
      // 3. rules for this step
      const rules = await call<RetrievedRule[]>(
        "get_rules",
        { tags: step.ruleTags },
        step.id,
        "retrieve rules",
      );
      await log("retrieval", { step: step.id, ruleTags: step.ruleTags, ruleIds: rules.map((r) => r.id) });

      // 4. plan a screen (rules honoured by construction)
      const { screen, notes } = buildScreen(flowMeta, step);
      await log("plan", { step: step.id, screenId: screen.id, notes });

      // 5. validate, scoped to the machineChecks implied by the retrieved rules
      const checksApplied = [...new Set(rules.map((r) => r.machine_check).filter((c): c is string => !!c))];
      const validation = await call<ValidationResult>(
        "validate_ast",
        { ast: screen, onlyChecks: checksApplied },
        step.id,
        "validate against retrieved rules",
      );
      await log("validation", {
        step: step.id,
        valid: validation.valid,
        checksApplied,
        errorCount: validation.semantic.errorCount,
        findings: validation.semantic.findings,
      });
      if (!validation.valid) {
        await log("rejection", { step: step.id, reason: "constraint check failed", validation });
      }

      steps.push({
        stepId: step.id,
        title: step.title,
        retrievedRules: rules,
        checksApplied,
        notes,
        ast: screen,
        validation,
      });
    }

    return {
      request,
      scenario,
      intent,
      flowId: flow.id,
      flowGoal: flow.goal,
      steps,
      trace,
      valid: steps.every((s) => s.validation.valid),
    };
  } finally {
    await client.close();
  }
}
