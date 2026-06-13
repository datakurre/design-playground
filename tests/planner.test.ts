import { describe, it, expect } from "vitest";
import { buildScreen, type FlowStep } from "@design-playground/planner";
import { validateAst } from "@design-playground/ui-ir";

const flow = { id: "account-settings", goal: "manage account" };

const destructiveStep: FlowStep = {
  id: "settings",
  title: "Account settings",
  components: ["card", "form", "button", "dialog"],
  fields: [
    { name: "email", label: "Email address", variant: "email", required: true, autocomplete: "email" },
  ],
  submitLabel: "Save changes",
  ruleTags: ["primary-action", "form-a11y", "destructive-action", "danger-zone"],
};

describe("buildScreen", () => {
  it("produces a valid screen that obeys the rules by construction", () => {
    const { screen } = buildScreen(flow, destructiveStep);
    expect(validateAst(screen).valid).toBe(true);
  });

  it("guards a destructive step with a danger zone and confirmation dialog", () => {
    const { screen } = buildScreen(flow, destructiveStep);
    const json = JSON.stringify(screen);
    expect(json).toContain('"role":"danger-zone"');
    expect(screen.dialogs?.[0]?.destructive).toBe(true);
    expect(screen.dialogs?.[0]?.confirmVariant).toBe("danger");
  });

  it("is deterministic", () => {
    const a = buildScreen(flow, destructiveStep).screen;
    const b = buildScreen(flow, destructiveStep).screen;
    expect(a).toEqual(b);
  });

  it("adds a skip action only for skippable steps", () => {
    const skippable: FlowStep = {
      id: "profile",
      title: "Your profile",
      components: ["form", "button"],
      fields: [{ name: "name", label: "Name", variant: "text" }],
      submitLabel: "Continue",
      ruleTags: ["primary-action", "skippable-step", "form-a11y"],
    };
    const json = JSON.stringify(buildScreen(flow, skippable).screen);
    expect(json).toContain('"kind":"skip"');
  });
});
