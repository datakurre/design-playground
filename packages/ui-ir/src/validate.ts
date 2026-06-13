/**
 * Validates a UI AST in two layers:
 *   1. structural - Ajv against ui-ast.schema.json (closed vocabulary,
 *      required props, no unknown keys). A failure here means the AST is
 *      not even safe to look at; the renderer must reject it.
 *   2. semantic - design lints (see lints.ts) that enforce the design
 *      rules an agent must obey.
 */
import AjvModule from "ajv/dist/2020.js";
import addFormatsModule from "ajv-formats";
import type { ErrorObject, ValidateFunction } from "ajv";
import type { Screen } from "./types.js";
import { runLints, type LintFinding } from "./lints.js";
// Import the schema as a JSON module so the validator is isomorphic:
// the same code runs under Node (tsx) and in the browser (Vite), with no
// filesystem access. ui-ir/ui-ast.schema.json remains the single source.
import schema from "../../../ui-ir/ui-ast.schema.json" with { type: "json" };

// Interop shim: Ajv and ajv-formats ship as CJS, so the default export
// lands differently under tsx (ESM) vs bundlers. Normalise both.
type AjvCtor = new (opts: Record<string, unknown>) => {
  compile: (schema: object) => ValidateFunction;
};
const Ajv2020 = (((AjvModule as unknown as { default?: AjvCtor }).default ?? AjvModule) as unknown) as AjvCtor;
const addFormats = (((addFormatsModule as unknown as { default?: unknown }).default ?? addFormatsModule) as unknown) as (
  ajv: unknown,
) => void;

let validator: ValidateFunction | null = null;
function getValidator(): ValidateFunction {
  if (!validator) {
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
