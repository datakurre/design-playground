# AI Coding Agents Guide

Welcome to the Git-Native Design System Platform. This project heavily utilizes AI coding agents to overcome ecosystem gaps in Elm (e.g., boilerplate generation, JS interop, codecs, and API bindings).

This document serves as the prompt and instruction manual for any AI agent working on this codebase. When assigning tasks, explicitly invoke the relevant agent persona.

## Build Toolchain

The app is built with **Vite 7** and **Tailwind CSS v4**. `elm-tailwind-classes`
generates a type-safe Tailwind API into `.elm-tailwind/`, which `elm.json`
lists as a required source directory — **`make gen` must run before `elm-test`,
`elm-review`, or any other Elm tooling will even compile.** Do not invoke
`elm-test` or `elm-review` directly without having run `make gen` first; use
`make check`, which handles this ordering (see SOP below).

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
**Responsibility:** Build target generators (CSS Variables, Tailwind, React, etc.) for *external* consumers of the design system.
**Instructions:**
- Transform the internal Elm Model (Token Graph, Component Graph) into valid strings for other platforms.
- Ensure the export pipeline remains purely functional.
- Note: this is distinct from the app's own internal Tailwind build pipeline (`elm-tailwind-classes`, see Build Toolchain above) — the Export Agent targets what *other* projects consume, not how this app itself is built.

---

## Standard Operating Procedure (SOP)

When tasked with implementing a unit of work (optionally tracked as a local,
gitignored `TODO-NN-xxxx.md` file — this convention is optional, not every
task will have one):
1. **Read** the task description (and the `TODO-NN-xxxx.md` item, if one exists) and this `AGENTS.md` file.
2. **Identify** the required Agent Roles (e.g., Codec Agent to fetch data, UI Agent to render it).
3. **Execute** the **Red / Green TDD** cycle.
4. **Verify** your work locally using `devenv shell -- make check` (runs `make gen`, then `elm-test`, then `elm-review` — see Build Toolchain above).
