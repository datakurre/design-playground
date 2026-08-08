# TODO-02: Usage-contract schema + codec (`Contracts.elm` types)

Part of the usage-contracts effort — see `TODO-00-usage-contracts-overview.md`
for the full set. This document is standalone: everything needed to
implement it is below.

## Objective

Define the data model for a component "usage contract" and its JSON
codec, in a new `src/Contracts.elm` module — the schema half of roadmap
item 1 ("A schema for component-level usage contracts"). This plan is
**schema and codec only** — no validation logic yet (that's
`TODO-03-contracts-validator.md`).

## Background

Components in this app are stored as JSON files fetched from a GitLab
repo, decoded with hand-written `elm/json` decoders/encoders — see
`src/Components.elm` for the exact style to match: a `type` field used to
dispatch a union type's decoder (`layoutDecoder` at
`src/Components.elm:37-69`), and a flat `encoder : X -> Value` for the
inverse (`src/Components.elm:75-100`). Token references inside a
component's `styles : Dict String String` are raw strings like
`"{interactive.primary.fg}"`; token paths are represented elsewhere as
`type alias TokenPath = List String` (`src/Tokens.elm:8-9`), with
dot-string ↔ `TokenPath` conversion done via `String.split "."` (see
`src/Tokens.elm:106`, inside `resolveAliasHelp`).

Usage contracts are meant to be their own git-diffable file per component,
at `components/<name>.contract.json`, decoupled from
`components/<name>.json` (that decoupling/storage decision is implemented
in `TODO-04-contracts-gitlab-wiring.md`; this plan only defines the Elm
types and their JSON shape).

## Files

- Create `src/Contracts.elm`
- Create `tests/ContractsTest.elm`

## Target JSON shape

```json
{
  "component": "Button",
  "rules": [
    { "type": "allowedTokenGroups", "groups": ["interactive", "spacing"] },
    { "type": "noHardcodedValues", "properties": ["color", "background-color", "border-color"] },
    { "type": "spacingOnScale", "properties": ["padding", "margin", "gap"], "scale": "spacing" },
    { "type": "contrastThreshold", "foreground": "color", "background": "background-color", "minimumRatio": 4.5 }
  ]
}
```

`groups` and `scale` are dot-path strings (e.g. `"interactive.primary"`),
consistent with the `{a.b.c}` alias syntax used everywhere else in this
codebase — convert to/from `Tokens.TokenPath` with `String.split "."`
(splitting) and `String.join "."` (joining).

## Types to define

```elm
module Contracts exposing (Contract, Rule(..), decoder, encoder)

import Tokens exposing (TokenPath)

type Rule
    = AllowedTokenGroups (List TokenPath)
    | NoHardcodedValues (List String)
    | SpacingOnScale (List String) TokenPath
    | ContrastThreshold { foreground : String, background : String, minimumRatio : Float }

type alias Contract =
    { component : String
    , rules : List Rule
    }

decoder : Decoder Contract
encoder : Contract -> Value
```

## Red/Green TDD steps

1. **Red**: write `tests/ContractsTest.elm` first, matching the style of
   `tests/ComponentsTest.elm` (`describe "Contracts Codec" [ ... ]`,
   encode-then-decode round-trip tests via `Decode.decodeValue`, plus a
   `Decode.decodeString` test against a literal JSON string like the one
   above). Include at least one round-trip test per `Rule` variant, and one
   test decoding a `Contract` containing all four rule kinds at once (the
   JSON sample above). Run `elm-test` and confirm these fail.
2. **Green**: implement `src/Contracts.elm`'s types, `ruleDecoder`
   (dispatch on `Decode.field "type" Decode.string`, one branch per rule
   kind, `Decode.fail` on an unknown tag — mirrors
   `src/Components.elm:37-69`), `decoder`, `ruleEncoder`, and `encoder`.
   Run `elm-test` until green, then `elm-review`.

## Acceptance criteria

- `tests/ContractsTest.elm` passes, including the round-trip and
  multi-rule-kind decode tests.
- `make check` passes.
- `Contracts.elm` does not yet expose or implement any validation function
  — that is out of scope for this plan.
