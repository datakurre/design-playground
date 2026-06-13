import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { validateAst, runLints, type Screen } from "@design-playground/ui-ir";

const ex = (f: string) => JSON.parse(readFileSync(join(process.cwd(), "ui-ir/examples", f), "utf8"));

describe("structural validation", () => {
  it("accepts a well-formed screen", () => {
    expect(validateAst(ex("valid-login.json")).valid).toBe(true);
  });

  it("rejects unknown node types and bad enums", () => {
    const r = validateAst(ex("invalid-structure.json"));
    expect(r.structural.valid).toBe(false);
    expect(r.structural.errors.length).toBeGreaterThan(0);
  });

  it("rejects additional properties (no escape hatch)", () => {
    const ast = { type: "Screen", id: "x", title: "X", children: [{ type: "Text", value: "hi", html: "<script>" }] };
    expect(validateAst(ast).structural.valid).toBe(false);
  });
});

describe("semantic lints", () => {
  it("flags more than one primary action", () => {
    const findings = runLints(ex("invalid-semantics.json") as Screen);
    expect(findings.map((f) => f.check)).toContain("single-primary-action");
  });

  it("flags an unguarded destructive action", () => {
    const findings = runLints(ex("invalid-semantics.json") as Screen);
    expect(findings.map((f) => f.check)).toContain("destructive-needs-confirmation");
  });

  it("accepts a properly guarded destructive screen", () => {
    expect(validateAst(ex("valid-delete-account.json")).valid).toBe(true);
  });

  it("can scope checks to a subset", () => {
    const only = runLints(ex("invalid-semantics.json") as Screen, ["field-has-label"]);
    expect(only.every((f) => f.check === "field-has-label")).toBe(true);
  });
});
