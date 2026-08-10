---
name: elm-tdd
description: Write tests for this Elm codebase — where they go, the house style, and how to test an update branch by asserting on the Effect it returns. Use when adding or changing behaviour in src/, or when a change seems untestable.
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
existing view tests target the sub-function that takes dictionaries rather than
the `Model`-taking entry point.

**`update` itself.** `Types.initial` is callable from a test, so any `Model` can
be built and any `Msg` run through `Update.update`. See `tests/UpdateTest.elm`.

## Testing an update branch

`update` returns `( Model, Effect Msg )`, and an `Effect` is data you can read.

```elm
let
    ( model, effect ) =
        Update.update SaveComponent someModel
in
Effect.requests effect
    |> List.head
    |> Maybe.andThen (.body >> GitLab.Request.bodyValue)
    |> Maybe.map (Decode.decodeValue (Decode.at [ "actions", "0", "action" ] Decode.string))
    |> Expect.equal (Just (Ok "create"))
```

- `Effect.requests` gives the GitLab calls, with `.method`, `.url`, `.headers`
  and `.body`. `GitLab.Request.bodyValue` gives the JSON to decode.
- `Effect.toList` flattens `Batch` and drops `None`, for navigation and port
  effects: `Expect.equal [ Effect.ClearToken, Effect.PushUrl "#/" ]`.
- **Never `Expect.equal` a whole `Effect` containing `SendRequest`.** It carries
  an `Http.Expect`, which contains a function, and Elm's `==` throws at runtime
  on functions. It works for `PushUrl` and `ClearToken`, which makes the trap
  worse rather than better.
- Saving is two steps: the branch records a pending commit and emits
  `ValidateSchema`, then `GotSchemaValidationResult` issues the commit. Run both.

Keep effects as data all the way: `update` must never return a `Cmd`, and
`Nav.Key` must never go back into the `Model` — that is what made all of this
untestable before.

## Where new logic goes

Still prefer a pure function in the relevant domain module over a non-trivial
`case` inside an `update` branch — `src/Naming.elm` is the model for this. It is
now a readability argument rather than a testability one, but it holds.

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
