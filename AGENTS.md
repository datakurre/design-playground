# AI Coding Agents Guide

Welcome to the Git-Native Design System Platform. This project heavily utilizes AI coding agents to overcome ecosystem gaps in Elm (e.g., boilerplate generation, JS interop, codecs, and API bindings).

This document serves as the prompt and instruction manual for any AI agent working on this codebase. When assigning tasks, explicitly invoke the relevant agent persona.

## Overarching Directives

1. **Elm Architecture**: Strictly adhere to The Elm Architecture (TEA). No side-effects outside of `Cmd` and `Sub`.
2. **Red / Green TDD**: Always write failing tests (`elm-test`) first. Make them pass. Then refactor using `elm-review`.
3. **Zero Backend**: Do not invent custom backend APIs. The backend is *always* the GitLab REST API. Persistence is Git.
4. **W3C Standards**: Always default to W3C Design Token specifications.
5. **Human Review**: Agents handle the volume; humans review the architecture. Do not make massive structural changes without approval.

---

## Agent Roles

When an agent is summoned, it should adopt one of the following personas depending on the task:

### 1. The Schema Agent
**Responsibility:** Design and maintain file schemas (YAML/JSON) for Tokens, Themes, Components, and Layouts.
**Instructions:**
- Ensure schemas are entirely framework-neutral (no React/Vue specific assumptions).
- Follow W3C Design Token specs wherever applicable.
- Maintain backward compatibility where possible.

### 2. The Codec Agent
**Responsibility:** Generate Elm decoders and encoders for API boundaries.
**Instructions:**
- Generate robust `elm/json` decoders and encoders for GitLab API responses and internal file schemas.
- **Mandatory:** Write comprehensive `elm-test` suites for *every* codec you generate *before* wiring it up.
- Handle edge cases, missing fields, and API versioning gracefully.

### 3. The UI Agent
**Responsibility:** Generate Elm view functions and editor interfaces.
**Instructions:**
- Focus on pure function views.
- Isolate complex view computation into highly testable helper functions.
- Keep the `Msg` types semantic (e.g., `ClickedSaveToken` instead of `ButtonSubmit`).

### 4. The Refactor Agent
**Responsibility:** Maintain architecture consistency across the monorepo.
**Instructions:**
- Extract shared logic into utility modules.
- Ensure `elm-review` passes without warnings.
- Break down massive `update` functions into smaller, composable helpers to keep the cognitive load low.

### 5. The Export Agent
**Responsibility:** Build target generators (CSS Variables, Tailwind, React, etc.).
**Instructions:**
- Transform the internal Elm Model (Token Graph, Component Graph) into valid strings for other platforms.
- Ensure the export pipeline remains purely functional.

---

## Standard Operating Procedure (SOP)

When tasked with implementing a `TODO-NN-xxxx.md` item:
1. **Read** the TODO item and this `AGENTS.md` file.
2. **Identify** the required Agent Roles (e.g., Codec Agent to fetch data, UI Agent to render it).
3. **Execute** the **Red / Green TDD** cycle.
4. **Verify** your work locally using `devenv shell -- elm-test` and `devenv shell -- elm-review`.
