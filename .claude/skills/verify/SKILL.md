---
name: verify
description: Run the right check for a change to this Elm/devenv project and interpret the failure. Use before claiming any work is done, and whenever elm-test, elm-review, elm-format or `make check` fails and the message is not self-explanatory.
---

# Verifying work in design-playground

`make check` is the gate. It is what the pre-commit hook runs and what CI runs.
Nothing is done until it passes.

```
make check
```

runs, in order: `make gen` → `elm-format --validate src/ tests/` → `elm make
src/Main.elm --output=/dev/null` → `elm-test` → `node --test
tests/schemas.test.js` → `elm-review`.

## Run the narrow thing first

`make check` is the gate, not the loop. While working, use:

| Command | When |
| --- | --- |
| `make test T=Contracts` | You are changing one module. Runs `tests/ContractsTest.elm` only. |
| `make test` | Both suites (elm-test + the JSON Schema tests). |
| `make fmt` | `check` reported a formatting problem. This fixes it. |
| `make review` | You want elm-review's opinion without the rest. |
| `make watch` | Re-runs `make test` on every Elm change. |
| `make smoke` | You changed anything that affects boot, routing, or styling. |

Passing a narrow target is not the same as passing `make check`. Run the gate
before you report.

## Reading the failures

**`I cannot find module 'Tailwind'` / anything about `.elm-tailwind`**
You ran `elm-test` or `elm-review` directly without generating first.
`elm.json` lists `.elm-tailwind` as a source directory and it is gitignored, so
it must be generated before any Elm tool can compile. Run `make gen`, or just
use the `make` targets — they all depend on it. This is the single most common
self-inflicted failure in this repo.

**`File is not formatted with elm-format`**
`--validate` reports, it does not rewrite. Run `make fmt`.

**elm-test passes but `make check` fails at `elm make src/Main.elm`**
Expected and deliberate. elm-test only compiles test modules and their
dependencies, and elm-review parses rather than type-checks — neither reaches
`src/Main.elm`. A broken `Model` or view shows up only at this step.

**elm-review complains about an unused import or variable**
Fix it rather than suppressing it. The config is deliberately small
(`review/src/ReviewConfig.elm`): `NoUnused.Variables`, `NoUnused.Dependencies`,
`NoMissingTypeAnnotation`. All three are cheap to satisfy.

**`make smoke` says a stylesheet has no `.bg-slate-50` rule**
Tailwind class extraction failed. See the `run` skill — this is an environment
problem, not a problem with your change.

## Before you say it is done

- `make check` passes.
- If the change touches views, routing, `src/main.js`, ports, or the build:
  `make smoke` passes and you have *looked at* `.smoke/home.png`.
- New behaviour has a test. New `Msg` branches and new modules are not exempt —
  see the `elm-tdd` skill.
