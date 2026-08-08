# TODO-04: GitLab wiring for contract files (`Types.elm`, `Update.elm`)

Part of the usage-contracts effort — see `TODO-00-usage-contracts-overview.md`
for the full set. This document is standalone: everything needed to
implement it is below.

## Objective

Wire contract files into the app's GitLab-backed load/save flow: fetch
`components/*.contract.json` files when a project's components load, hold
them in `Model`, and support creating/editing/saving/deleting a contract
for the selected component, plus a one-click way to jump from a violation
elsewhere in the app to the component that owns it. This turns the pure
`Contracts` module from TODO-02/03 into something the running app actually
populates from (and writes back to) a real repo, with the same full
CRUD + navigation affordances every other editable thing in this app
(themes, components, screens) already has.

## Prerequisites

Requires `TODO-02-contracts-schema.md` and
`TODO-03-contracts-validator.md` merged (needs `Contracts.decoder`,
`Contracts.encoder`, and the `Contract`/`Rule` types; does not need
`Contracts.validate` itself — that's consumed by the UI plans, 05 and 06).

## Background

This app has no local file storage — everything is fetched from/pushed to
GitLab's REST API over HTTP (`src/GitLab/Files.elm`,
`src/GitLab/Commits.elm`). Existing component load/save flow to mirror
(all in `src/Update.elm`):

- `GotComponentsTree` (`src/Update.elm:506-529`) handles the result of
  `GitLab.Files.listTreeAtPath token project.id project.defaultBranch "components" GotComponentsTree`
  (triggered at `src/Update.elm:223` on project selection, and again at
  `src/Update.elm:1245` on branch switch). It filters the tree to
  `*.json` files, derives component names by stripping `.json`, and fires
  one `GitLab.Files.getFileRaw` per file, routed to `GotComponentFile`.
  **Any `*.contract.json` file already appears in this same tree listing**
  (same `components/` folder) — no new GitLab API call is needed, just
  additional filtering of the existing `tree` value.
- `GotComponentFile filename result` (`src/Update.elm:531-549`) decodes
  with `Components.decoder` and merges into `model.components`,
  replacing any existing entry with the same `.name`.
- `SaveComponent` (`src/Update.elm:690-744`) encodes with
  `Components.encoder`, picks `"update"` vs `"create"` based on whether
  the name is in `model.existingComponents`, and commits to
  `"components/" ++ comp.name ++ ".json"` via
  `GitLab.Commits.createCommit token project.id payload (GotCommitResult (CommitComponent comp.name))`.
- `GotCommitResult context result` (`src/Update.elm:243-282`) has a
  `case context of` with one branch per `CommitContext` variant; on
  `CommitComponent name`, it adds `name` to `model.existingComponents`
  (`src/Update.elm:261-262`).
- `CommitContext` is defined in `src/Types.elm:101-109`.
- `DeleteComponent name` (`src/Update.elm:1180-1203`) commits a `"delete"`
  action for `"components/" ++ name ++ ".json"`, drops the entry from
  `model.components`, clears `selectedComponentName`, and uses commit
  context `CommitDeleteComponent name` — the pattern `DeleteContract`
  below mirrors, minus the selection-clearing.
- Places that reset `components`/`existingComponents`/`originalComponents`
  to empty/`Nothing` when switching project or branch: `src/Types.elm`'s
  `Model` is mutated at `src/Update.elm:175` (logout), `:218` (select
  project), and `:1240` (switch branch) — grep those three lines for the
  full reset record to see the exact field list each touches.

## Files

- Modify `src/Types.elm` (`Model`, `Msg`, `CommitContext`)
- Modify `src/Update.elm`

## Model additions (`src/Types.elm`)

```elm
, contracts : Maybe (List Contracts.Contract)
, existingContracts : List String
, newContractRuleType : String
, newContractRuleFields : Dict String String
```

`newContractRuleType`/`newContractRuleFields` are scratch state for the
rule-builder form built in `TODO-05-component-registry-ui.md` — included
here since they belong on `Model` and the `Msg`s that mutate them are
naturally part of this wiring plan. `newContractRuleFields` is a small
generic `Dict` (keyed by field name, e.g. `"groups"`, `"properties"`,
`"scale"`, `"foreground"`, `"background"`, `"minimumRatio"`) rather than
one named `Model` field per rule-type per field, since the four rule kinds
have different field shapes and this avoids ~8 near-duplicate fields —
follows the same "generic key/value scratch pair" idiom already used for
`newLayoutPropertyName`/`newLayoutPropertyValue`.

Add `import Contracts` and `import Dict` (if not already imported) to
`src/Types.elm`.

## Msg additions (`src/Types.elm`)

```elm
| GotContractFile String (Result Http.Error String)
| UpdateNewContractRuleType String
| UpdateNewContractRuleField String String
| AddContractRule
| RemoveContractRule Int
| SaveContract
| DeleteContract String
| JumpToComponent String
```

`DeleteContract` and `JumpToComponent` exist for UI/UX reasons spelled out
in `TODO-05-component-registry-ui.md` and
`TODO-06-git-workflows-gate-ui.md`: every other editable thing in this app
(themes, components, screens) has a delete action, so a contract without
one would be a dead end once created; and a gate that lists violations
without a way to jump to the component that has them makes the user
re-find it by hand via the sidebar list.

## `CommitContext` addition (`src/Types.elm`)

Add `CommitContract String` and `CommitDeleteContract String` alongside
the existing `CommitComponent String` / `CommitDeleteComponent String`
etc.

## `Update.elm` changes

1. **`GotComponentsTree`**: change the `jsonFiles`/`componentNames`
   derivation to exclude `*.contract.json` from the plain component list
   (e.g. `String.endsWith ".json" item.name && not (String.endsWith ".contract.json" item.name)`), and add a parallel
   `contractFiles = List.filter (\item -> String.endsWith ".contract.json" item.name) tree` with
   `contractComponentNames = List.map (\item -> String.replace ".contract.json" "" item.name) contractFiles`.
   Fetch each contract file the same way component files are fetched
   (`GitLab.Files.getFileRaw token project.id project.defaultBranch file.path (GotContractFile file.name)`),
   appended into the same `Cmd.batch cmds`. Set
   `existingContracts = contractComponentNames` and
   `contracts = Just []` in the resulting model, alongside the existing
   `components = Just [], existingComponents = componentNames`.
2. **New `GotContractFile filename result`**: same shape as
   `GotComponentFile` (`src/Update.elm:531-549`) but decode with
   `Contracts.decoder` and merge into `model.contracts` by `.component`
   (replace-if-same-name, keep others).
3. **New `UpdateNewContractRuleType type_`**:
   `( { model | newContractRuleType = type_ }, Cmd.none )`.
4. **New `UpdateNewContractRuleField key value`**:
   `( { model | newContractRuleFields = Dict.insert key value model.newContractRuleFields }, Cmd.none )`.
5. **New `AddContractRule`**: look up `model.selectedComponentName`; if
   present, build a `Contracts.Rule` from `model.newContractRuleType` and
   `model.newContractRuleFields` (comma-split and trim for list-valued
   fields like `groups`/`properties`; `String.toFloat` for
   `minimumRatio`; no-op — leave model unchanged — if required fields are
   missing/unparsable). Find or create the `Contract` for that component
   name in `model.contracts` (`{ component = name, rules = [] }` if none
   exists), append the new rule, write it back into `model.contracts`,
   and clear `newContractRuleFields` back to `Dict.empty`.
6. **New `RemoveContractRule index`**: for the selected component's
   `Contract`, drop the rule at `index` (`List.indexedMap` + filter, or
   `List.take index rules ++ List.drop (index + 1) rules`).
7. **New `SaveContract`**: mirror `SaveComponent`
   (`src/Update.elm:690-744`) exactly, but: encode with
   `Contracts.encoder`, look up the `Contract` (not `Component`) for
   `model.selectedComponentName` in `model.contracts`, `actionType` from
   `List.member activeName model.existingContracts`, file path
   `"components/" ++ name ++ ".contract.json"`, commit context
   `GotCommitResult (CommitContract name)`.
8. **New `DeleteContract name`**: mirror `DeleteComponent`
   (`src/Update.elm:1180-1203`) exactly, but delete
   `"components/" ++ name ++ ".contract.json"`, drop the matching entry
   from `model.contracts` instead of `model.components`, do **not** touch
   `selectedComponentName` (unlike `DeleteComponent`, deleting a contract
   should leave you looking at the same component, just with no contract
   attached), and use commit context
   `GotCommitResult (CommitDeleteContract name)`.
9. **New `JumpToComponent name`**: `( { model | activeTab = ComponentRegistry, selectedComponentName = Just name }, Cmd.none )` — a same-frame tab switch plus selection, so clicking a violation in the Git Workflows gate (`TODO-06-git-workflows-gate-ui.md`) lands the user on that component's editor, already selected, in one click.
10. **`GotCommitResult`**: add
    `CommitContract name -> { model | existingContracts = addUnique name model.existingContracts }`
    and
    `CommitDeleteContract name -> { model | existingContracts = List.filter ((/=) name) model.existingContracts }`
    branches (reuse the existing local `addUnique` helper already defined
    in this case, `src/Update.elm:247-251`).
11. **Reset sites**: add `contracts = Nothing, existingContracts = []` (and
    reset the two scratch fields to their empty defaults) at each of the
    three `Model`-reset call sites identified above (logout, select
    project, switch branch) — same treatment `components`/
    `existingComponents` already get at each site.

## Tests

This plan is glue code against `Http`/GitLab, which the existing test
suite does not attempt to test directly (no HTTP mocking anywhere in
`tests/`) — skip new tests here; correctness is verified manually per the
acceptance criteria below. Do not skip `make check` — it must stay green
throughout (compile correctness across `Types.elm`/`Update.elm` is what
regresses easiest here).

## Acceptance criteria

- `make check` passes (this plan is Elm-compiler-verified glue; there is
  no new automated test, so a clean compile plus the full existing suite
  staying green is the bar).
- Manual check via `make dev`: selecting a GitLab project whose
  `components/` folder contains a `*.contract.json` file causes it to
  load into `model.contracts` without errors (verify via `elm-review`
  passing and no runtime decode errors in the browser console).
