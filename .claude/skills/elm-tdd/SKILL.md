---
name: elm-tdd
description: Write tests for this Elm codebase — where they go, the house style, what is reachable from a test and what is not, and how to work around the Nav.Key barrier. Use when adding or changing behaviour in src/, or when a change seems untestable.
---

# Testing design-playground

`AGENTS.md` mandates Red/Green: write the failing test first, make it pass, then
tidy under `elm-review`. This skill is the mechanics.

## Where tests go

`tests/<Module>Test.elm`, one per source module, exposing a single `suite : Test`.
The JSON Schema tests are separate and live in `tests/schemas.test.js`, run by
`node --test`.

Run one file while working: `make test T=Contracts`.

## House style

Look at `tests/NamingTest.elm` for the plain shape and `tests/RendererTest.elm`
for a view test. The conventions actually followed here:

- `describe "<Module>"` at the top, nested `describe` per function.
- Test names are sentences describing the behaviour, not the mechanics:
  `"trims before accepting, so the name that gets stored is the trimmed one"`,
  not `"test trim"`.
- A module docstring at the top of the suite when the *reason* the test exists is
  not obvious from the assertions — especially when it locks user-visible wording
  or records a bug that already happened once.
- `Expect.equal expected actual`.

## What is reachable from a test

**Freely testable** — no `Model`, no `Html`: `Tokens`, `Themes`, `Screens`,
`Components`, `Contracts`, `Colors`, `Naming`, `Export`, `TokenScale`,
`TokenBrowse`, `Templates`, `Route`, `Help`, and the `GitLab/*` decoders. This is
where most new logic should live.

**Testable through `Test.Html.Query`**: view helpers that take plain data. Both
existing view tests deliberately target the sub-function that takes dictionaries
rather than the `Model`-taking entry point.

**Not reachable at all**: `src/Update.elm` and `src/Main.elm`. `Types.Model` has
a `key : Nav.Key` field, and a `Nav.Key` cannot be constructed outside a running
`Browser.application`. So `Types.initial` cannot be called from a test, and
neither can anything that takes a `Model`.

## Working with the Nav.Key barrier

Until the planned `Effect` refactor lands, the way to make new logic testable is
to keep it out of `Update.elm`:

- Put the decision in a pure function in the relevant domain module, and have the
  `update` branch call it. `src/Naming.elm` exists for exactly this reason — its
  docstring says so.
- Give view helpers the data they need, not the `Model`.
- If you find yourself about to write a non-trivial `case` inside an `update`
  branch, that is the signal: extract it.

Do **not** work around the barrier by adding a `Maybe Nav.Key`, by exposing
internals just for tests, or by asserting on `Cmd`s — a `Cmd` is opaque and
cannot be inspected.

## Fuzz tests

`elm-explorations/test` ships `Fuzz` and nothing in the suite uses it yet. The
obvious win is codec round-trips: every one of `Tokens`, `Components`,
`Contracts`, `Screens` and `Themes` has an encoder/decoder pair currently covered
by hand-written examples only. `decode (encode x) == Ok x` over a fuzzer catches
the cases nobody thought of.

## Adding a dependency

Don't, without asking. The dev container has no direct DNS, and a new Elm package
means `elm-json install` reaching `package.elm-lang.org`. See the `devenv-tools`
skill.
