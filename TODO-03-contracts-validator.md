# TODO-03: Contract validator (`Contracts.validate`)

Part of the usage-contracts effort — see `TODO-00-usage-contracts-overview.md`
for the full set. This document is standalone: everything needed to
implement it is below.

## Objective

Add the rule-checking engine to `src/Contracts.elm`: a pure function that
checks a `Component`'s layout tree against a `Contract` and a token list,
returning a list of violations. This is roadmap item 2 ("A validator that
checks token/component/screen files against that schema").

## Prerequisites

Requires `TODO-01-colors-module.md` (`src/Colors.elm`) and
`TODO-02-contracts-schema.md` (`Contract`/`Rule` types + codec in
`src/Contracts.elm`) to already be merged.

## Background

- Components are a recursive tree: `type Layout = Stack StackProps (List Layout) | Grid GridProps (List Layout) | Element ElementProps String`, and every variant carries a `styles : Dict String String` (`src/Components.elm:8-26`).
- The existing layout-tree editor already addresses tree nodes by a
  `List Int` index path from the root (root = `[]`, child `i` of node at
  path `p` = `p ++ [i]`) — see `updateLayoutNode` in
  `src/Update.elm:24-39`. Reuse the same addressing scheme for violations
  so a `Violation.path` is directly usable elsewhere in the app.
- Token aliasing: a style value can be a token reference like
  `"{interactive.primary.fg}"`, resolved via
  `Tokens.resolveAlias : List Tokens.FlatToken -> String -> String`
  (`src/Tokens.elm:82-130`) — note it silently returns the raw string
  unresolved if no matching token is found (no error type exists in this
  codebase; don't introduce one here either — just treat "didn't resolve"
  as "doesn't satisfy the rule" for the rules that need a resolved value).
- `Tokens.TokenPath = List String`, `Tokens.FlatToken = ( TokenPath, DesignToken )`, `DesignToken = { value : TokenValue, type_ : String, description : Maybe String }`, `TokenValue = StringValue String | CompositeValue (Dict String String)` (`src/Tokens.elm:8-25`).
- `Colors.parseHex : String -> Maybe Colors.Rgb` and
  `Colors.contrastRatio : Colors.Rgb -> Colors.Rgb -> Float` from
  `TODO-01-colors-module.md`.

## Files

- Modify `src/Contracts.elm` (add to the existing module from TODO-02)
- Modify `tests/ContractsTest.elm` (add validator tests alongside the
  existing codec tests)

## Types/functions to add

```elm
module Contracts exposing (Contract, Rule(..), Violation, decoder, encoder, validate)

type alias Violation =
    { path : List Int
    , property : Maybe String
    , message : String
    }

validate : List Tokens.FlatToken -> Contract -> Components.Component -> List Violation
```

Internal helpers (not necessarily exposed):
- `styleNodes : Components.Layout -> List ( List Int, Dict String String )` — flattens the tree into `(path, styles)` pairs using the `path ++ [i]` addressing described above.
- `extractAliasPaths : String -> List Tokens.TokenPath` — scans a style value for every `{...}` occurrence and returns the parsed dot-paths inside (do not resolve — just extract references). A single pass, non-overlapping brace pairs, similar in spirit to the brace-scanning in `Tokens.resolveAliasHelp` (`src/Tokens.elm:87-130`) but collecting rather than substituting.
- `containsHexLiteral : String -> Bool` — true if the string contains a `#` followed by a maximal run of hex digit characters (`0-9a-fA-F`) whose length is exactly 3, 4, 6, or 8. No regex (none is available) — scan with `String.indexes "#"` plus a hand-written greedy hex-run counter.
- `isPrefixOf : List a -> List a -> Bool` — list-prefix check for group scoping.

## Rule semantics (one per `Rule` variant)

- **`AllowedTokenGroups groups`**: for every `(property, value)` in a
  node's `styles`, for every alias path extracted from `value` via
  `extractAliasPaths`, the path must have one of `groups` as a prefix
  (`isPrefixOf`). Otherwise emit a `Violation` at that node's path naming
  the offending token path and the allowed groups.
- **`NoHardcodedValues properties`**: for every `(property, value)` in a
  node's `styles` where `property` is in `properties`, if
  `containsHexLiteral value` is true, emit a violation (checks the raw
  authored value, not the resolved one — an alias reference is never
  flagged even if it eventually resolves to a hex color).
- **`SpacingOnScale properties scale`**: collect every token's resolved
  string value (`Tokens.resolveAliasValue`, keeping only `StringValue`
  results) whose `TokenPath` has `scale` as a prefix — this is "the
  scale". For every `(property, value)` in a node's `styles` where
  `property` is in `properties`, resolve `value` with
  `Tokens.resolveAlias`; if the resolved string isn't a member of the
  scale's value set, emit a violation.
- **`ContrastThreshold { foreground, background, minimumRatio }`**: only
  applies to a node whose `styles` sets *both* `foreground` and
  `background` keys. Resolve both values with `Tokens.resolveAlias`, parse
  both with `Colors.parseHex`; if either fails to parse, skip (no
  violation — nothing meaningful to check). Otherwise compute
  `Colors.contrastRatio`; if it's below `minimumRatio`, emit a violation
  whose message includes the computed ratio (round to 2 decimals for
  readability) and the required minimum.

`validate tokens contract component` = `case component.layout of Nothing -> []; Just layout -> styleNodes layout |> List.concatMap (\(path, styles) -> List.concatMap (applyRule tokens path styles) contract.rules)`.

## Red/Green TDD steps

1. **Red**: extend `tests/ContractsTest.elm` with a `validateTests`
   `describe` block. Build small fixture `Component`s inline (a one- or
   two-node layout is enough per test) and small fixture token lists.
   Write at minimum:
   - `AllowedTokenGroups`: one test where a style references a token
     inside an allowed group (expect `[]`), one where it references a
     token outside the allowed groups (expect one `Violation`).
   - `NoHardcodedValues`: one test with a raw hex value on a listed
     property (expect a violation), one with a `{token}` reference on the
     same property (expect `[]`), one with a hex value on a property *not*
     listed in the rule (expect `[]`).
   - `SpacingOnScale`: one test where the property's resolved value
     matches a token in the scale group (expect `[]`), one where it
     doesn't (expect a violation).
   - `ContrastThreshold`: one test with a passing contrast pair (e.g.
     black on white, ratio ≈ 21, threshold 4.5 → `[]`), one with a failing
     pair (e.g. two near-identical grays → one violation), one where only
     one of `foreground`/`background` is set (expect `[]`, rule doesn't
     apply).
   - One test combining multiple rules on the same contract/component to
     confirm violations from different rules all surface.
   Confirm these fail (function doesn't exist yet).
2. **Green**: implement `styleNodes`, `extractAliasPaths`,
   `containsHexLiteral`, `isPrefixOf`, `applyRule`, and `validate` in
   `src/Contracts.elm`. Iterate until all tests pass.
3. Run `elm-review`.

## Acceptance criteria

- All new validator tests pass, alongside the existing codec tests from
  TODO-02.
- `make check` passes.
- `Contracts.validate` is a pure function — no `Cmd`, no `Http`, no model
  dependency — so it is usable directly from view code later.
