#!/usr/bin/env -S npx tsx
/**
 * MCP Design Server.
 *
 * Exposes the SQLite rule store as a set of Model Context Protocol tools
 * over stdio. Every read is a plain SQL query, so retrieval is
 * deterministic: the same arguments always return the same result. Any
 * MCP client - the deterministic planner in this repo, or Claude Code /
 * Claude Desktop interactively - can drive the same design knowledge.
 *
 * Tools:
 *   get_tokens        design tokens (optionally filtered by path prefix)
 *   list_components   component ids + purposes
 *   get_component     full metadata for one component
 *   list_flows        flows and their trigger phrases
 *   get_flow          a flow with steps, rule tags and error states
 *   match_intent      deterministic free-text -> flow matching
 *   get_rules         rules by tags / category (always incl. global rules)
 *   validate_ast      structural + semantic validation of a UI AST
 *   log_decision      append an entry to the append-only audit log
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { DesignDb, defaultDbPath, type AuditEvent } from "@design-playground/design-db";
import { validateAst } from "@design-playground/ui-ir";

const db = new DesignDb(process.env.DESIGN_DB_PATH ?? defaultDbPath);

const server = new McpServer({ name: "design-mcp", version: "0.1.0" });

/** Standard MCP text result carrying a JSON payload. */
function json(payload: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(payload, null, 2) }] };
}

server.registerTool(
  "get_tokens",
  {
    title: "Get design tokens",
    description: "Return W3C design tokens, optionally filtered by a dotted path prefix (e.g. 'color.brand').",
    inputSchema: { prefix: z.string().optional().describe("Dotted token path prefix filter") },
  },
  async ({ prefix }) => json(db.getTokens(prefix)),
);

server.registerTool(
  "list_components",
  {
    title: "List components",
    description: "List available UI component primitives with their purpose.",
    inputSchema: {},
  },
  async () => json(db.listComponents()),
);

server.registerTool(
  "get_component",
  {
    title: "Get component metadata",
    description: "Return full metadata (variants, props, accessibility, constraints, examples) for one component.",
    inputSchema: { id: z.string().describe("Component id, e.g. 'button'") },
  },
  async ({ id }) => {
    const c = db.getComponent(id);
    return c ? json(c) : json({ error: `unknown component '${id}'` });
  },
);

server.registerTool(
  "list_flows",
  {
    title: "List flows",
    description: "List the supported user flows and their trigger phrases.",
    inputSchema: {},
  },
  async () => json(db.listFlows()),
);

server.registerTool(
  "get_flow",
  {
    title: "Get flow definition",
    description: "Return a flow with its ordered steps, per-step rule tags, success state and error states.",
    inputSchema: { id: z.string().describe("Flow id, e.g. 'checkout'") },
  },
  async ({ id }) => {
    const f = db.getFlow(id);
    return f ? json(f) : json({ error: `unknown flow '${id}'` });
  },
);

server.registerTool(
  "match_intent",
  {
    title: "Match intent to flow",
    description: "Deterministically match a free-text user request to the most relevant flow, with a ranked score breakdown.",
    inputSchema: { text: z.string().describe("The user's request in natural language") },
  },
  async ({ text }) => json(db.matchIntent(text)),
);

server.registerTool(
  "get_rules",
  {
    title: "Get design rules",
    description: "Return design rules. Filter by rule tags and/or category; global rules are always included.",
    inputSchema: {
      tags: z.array(z.string()).optional().describe("Rule tags (typically a step's ruleTags)"),
      category: z.string().optional().describe("Rule category filter"),
    },
  },
  async ({ tags, category }) => {
    let rules = tags ? db.getRulesForTags(tags) : db.getAllRules();
    if (category) rules = rules.filter((r) => r.category === category);
    return json(rules);
  },
);

server.registerTool(
  "validate_ast",
  {
    title: "Validate a UI AST",
    description:
      "Validate a UI AST structurally (JSON Schema) and semantically (design lints). Each semantic finding is linked back to the rule id(s) that declare its machineCheck.",
    inputSchema: {
      ast: z.unknown().describe("The UI AST to validate"),
      onlyChecks: z.array(z.string()).optional().describe("Restrict semantic lints to these machineCheck ids"),
    },
  },
  async ({ ast, onlyChecks }) => {
    const result = validateAst(ast, onlyChecks);
    const findings = result.semantic.findings.map((f) => ({
      ...f,
      rules: db.getRulesByMachineCheck(f.check).map((r) => ({ id: r.id, title: r.title, severity: r.severity })),
    }));
    return json({ ...result, semantic: { ...result.semantic, findings } });
  },
);

server.registerTool(
  "log_decision",
  {
    title: "Log a decision",
    description: "Append an entry to the append-only audit log (cannot be updated or deleted).",
    inputSchema: {
      actor: z.string().describe("Who/what is acting, e.g. 'planner'"),
      event: z.enum(["intent", "retrieval", "plan", "validation", "render", "rejection"]),
      scenario: z.string().optional().describe("Scenario id this entry belongs to"),
      detail: z.unknown().describe("Structured detail payload"),
    },
  },
  async ({ actor, event, scenario, detail }) => {
    const id = db.logAudit(actor, event as AuditEvent, scenario ?? null, detail);
    return json({ logged: true, id });
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
// Stderr is safe for logs; stdout is the MCP channel.
console.error("design-mcp server ready on stdio");
