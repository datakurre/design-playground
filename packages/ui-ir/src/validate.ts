/**
 * Validates a UI AST in two layers:
 *   1. structural - Ajv against ui-ast.schema.json (closed vocabulary,
 *      required props, no unknown keys). A failure here means the AST is
 *      not even safe to look at; the renderer must reject it.
 *   2. semantic - design lints (see lints.ts) that enforce the design
 *      rules an agent must obey.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020, { type ErrorObject, type ValidateFunction } from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import type { Screen } from "./types.js";
import { runLints, type LintFinding } from "./lints.js";

const here = dirname(fileURLToPath(import.meta.url));
const schemaPath = join(here, "../../../ui-ir/ui-ast.schema.json");

let validator: ValidateFunction | null = null;
function getValidator(): ValidateFunction {
  if (!validator) {
    const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
    const ajv = new Ajv2020({ allErrors: true, strict: false, discriminator: true });
    addFormats(ajv);
    validator = ajv.compile(schema);
  }
  return validator;
}

export interface SchemaError {
  path: string;
  message: string;
}

export interface ValidationResult {
  valid: boolean;
  structural: { valid: boolean; errors: SchemaError[] };
  semantic: { findings: LintFinding[]; errorCount: number; warnCount: number };
}

function formatAjvError(e: ErrorObject): SchemaError {
  return {
    path: e.instancePath || "(root)",
    message: `${e.message ?? "invalid"}${e.params && Object.keys(e.params).length ? " " + JSON.stringify(e.params) : ""}`,
  };
}

/**
 * @param ast        the candidate AST (untrusted)
 * @param onlyChecks optional machineCheck ids to restrict semantic lints to
 */
export function validateAst(ast: unknown, onlyChecks?: Iterable<string>): ValidationResult {
  const validate = getValidator();
  const structurallyValid = validate(ast) as boolean;
  const structuralErrors = structurallyValid ? [] : (validate.errors ?? []).map(formatAjvError);

  // Semantic lints can only run on a structurally valid screen.
  let findings: LintFinding[] = [];
  if (structurallyValid) {
    findings = runLints(ast as Screen, onlyChecks);
  }
  const errorCount = findings.filter((f) => f.severity === "error").length;
  const warnCount = findings.filter((f) => f.severity === "warn").length;

  return {
    valid: structurallyValid && errorCount === 0,
    structural: { valid: structurallyValid, errors: structuralErrors },
    semantic: { findings, errorCount, warnCount },
  };
}
