---
name: add-contract-rule
description: Add a new usage-contract rule type to design-playground. Use when asked to add, extend or change a contract rule (allowedTokenGroups, noHardcodedValues, spacingOnScale, contrastThreshold, or a new one) — it touches seven places and missing one leaves the rule half-wired.
---

# Adding a usage-contract rule

Usage contracts are the layer DTCG does not standardise, and the reason this
project exists rather than being a token editor. A rule type is a cross-cutting
change: get all seven places or the rule will decode but not save, or save but
never fire.

Contracts live on disk as `components/<name>.contract.json` and in
`src/Contracts.elm`.

## The seven places

### 1. The variant — `src/Contracts.elm`, `type Rule`

```elm
type Rule
    = AllowedTokenGroups (List TokenPath)
    | NoHardcodedValues (List String)
    | SpacingOnScale (List String) TokenPath
    | ContrastThreshold { foreground : String, background : String, minimumRatio : Float }
```

Carry a record when there are more than two fields, as `ContrastThreshold` does;
positional arguments stop being readable past two.

### 2. The decoder — `ruleDecoder`

Dispatches on a `"type"` string field. Add a `case` arm whose literal matches the
name you will use everywhere else (camelCase, matching the existing four).

### 3. The encoder — `ruleEncoder`

Must round-trip with the decoder exactly. `tokenPathEncoder`/`tokenPathDecoder`
handle the dotted-path form (`"color.brand.500"` ↔ `["color","brand","500"]`) —
reuse them rather than joining strings by hand.

### 4. The check — `validate`

```elm
validate : List Tokens.FlatToken -> Contract -> Components.Component -> List Violation
```

It walks the component's layout tree and returns a `Violation` per problem, each
carrying `path : List Int` (the index path to the offending node), an optional
`property`, a `message`, and `context`. The `path` is what makes the finding
clickable in the UI, so populate it properly.

**Reuse `valueParts`.** It splits a style value into its alias and literal
halves: `"1px solid {core.border}"` → aliases `["core.border"]`, literal
`"1px solid"`. Rules about *which tokens* read the alias half; rules about
*hardcoded values* read the literal half. Every existing rule is built on it.

For anything colour-related, `src/Colors.elm` already does hex parsing and WCAG
contrast ratios.

### 5. The tests — `tests/ContractsTest.elm`

Red first. Two kinds, both of which the existing rules have:

- a round-trip: `decoder (encoder rule) == Ok rule`;
- `validate` cases: one component that violates the rule and one that satisfies
  it, asserting the `Violation` fields — including `path`, not just `message`.

Run with `make test T=Contracts`.

### 6. The form — `src/Update.elm` and `src/Pages/ComponentRegistry.elm`

The form is generic and driven by two model fields: `newContractRuleType : String`
(the selected type name) and `newContractRuleFields : Dict String String` (every
input, keyed by name).

- `src/Pages/ComponentRegistry.elm` ~817: add an `<option>` to the rule-type
  `select`, then a branch to the `case model.newContractRuleType of` below it
  describing your inputs. There is a helper right underneath that renders one
  labelled field bound to `newContractRuleFields` with a hint line — use it.
- `src/Update.elm`, the `AddContractRule` branch: add a case that builds your
  variant from those strings. `getFloat`, `getList` (comma-separated) and
  `getString` (trimmed, `Nothing` when blank) are defined in the branch already.
  Build a `Maybe Rule` — returning `Nothing` on bad input is how the form
  refuses.

### 7. The help topic — `src/Help.elm`

`usageContract` is the topic behind the contracts form. If your rule introduces
vocabulary a user would not guess, it belongs there. `AGENTS.md` is explicit that
a control with no explanation is only half-built.

## Not a place you need to touch

`schemas/contracts.schema.json` types `rules` as an array of plain objects, so it
does not enumerate rule types and needs no change. If you ever tighten it, update
`tests/schemas.test.js` in the same commit.

## Finish

`make check`. The contract check panel is rendered by `viewContractCheck` in
`src/Pages/GitWorkflows.elm` — it runs `validate` across every component and
turns each violation into a jump-to-component button. Advisory only: nothing
blocks a commit on a violation.
