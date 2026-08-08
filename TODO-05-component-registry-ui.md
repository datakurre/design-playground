# TODO-05: Component Registry UI — live violations, badges, rule-builder

Part of the usage-contracts effort — see `TODO-00-usage-contracts-overview.md`
for the full set. This document is standalone: everything needed to
implement it is below.

## Objective

Surface contract violations both while editing a single component and at
a glance across the whole component list, and provide a minimal form to
author/edit/save/delete that component's usage contract — the "editor"
half of the enforcement UI. A validator nobody sees is not enforcement;
this plan is entirely about making contract state and violations legible
at every point a user is already looking during normal editing.

## Prerequisites

Requires `TODO-03-contracts-validator.md` (`Contracts.validate`) and
`TODO-04-contracts-gitlab-wiring.md` (`Model.contracts`,
`Model.existingContracts`, the `AddContractRule`/`RemoveContractRule`/
`SaveContract`/`DeleteContract`/`UpdateNewContractRule*` messages) merged.

## Background

`src/Pages/ComponentRegistry.elm` is pure view code (`Html Msg`), no I/O.
Relevant existing structure:
- `viewComponentRegistry` (`:145-155`) shows a "Loading components..."
  message while `model.components == Nothing`, then renders
  `viewComponentList` beside `viewSelectedComponent` once loaded — the
  existing loading-state idiom to preserve; contract state does not need
  its own loading message since it always arrives alongside components
  (see `TODO-04-contracts-gitlab-wiring.md`'s `GotComponentsTree` change).
- `viewComponentList model components` (`:158-222`) renders the sidebar
  `<ul>` of component names as buttons (`:162-196`), each highlighted when
  selected, followed by the "new component" form.
- `viewSelectedComponent` (`:225-265`) computes `displayTokens`
  (theme-resolved tokens for the active component) inline in a `let`
  block, then renders `viewComponentEditor model comp displayTokens`
  alongside a live preview. This theme-resolution logic (base tokens, or
  `Themes.applyTheme` against `model.activeThemeName`) is currently
  private to this function — this plan needs the same resolved tokens in
  `viewComponentList` too (see below), so extract it into a top-level
  `resolveDisplayTokens : Model -> List Tokens.FlatToken` helper in this
  same file and call it from both places, rather than duplicating the
  `case model.activeThemeName of ...` logic.
- `viewComponentEditor` (`:268-298`) renders the Save/Delete buttons, the
  variants/states/slots lists (via the reusable `viewNameList` helper,
  `:303-341`), and the Layout section.
- `viewNameList label names draft onDraftChange onAdd` (`:303-341`) is the
  existing "list of strings + text input + add button" idiom — a useful
  reference for the simple parts of the new rule-builder form, though the
  rule form itself needs more than one input per rule (see below), so it
  will be a new, purpose-built view function rather than a reuse of
  `viewNameList` verbatim.
- Style helpers to reuse (`src/Ui.elm`): `Ui.panel`, `Ui.panelSunken`,
  `Ui.pageTitle`, `Ui.sectionTitle`, `Ui.muted`, `Ui.mutedSmall`,
  `Ui.divider`, `Ui.textInput`, `Ui.selectInput`, `Ui.fieldLabel`,
  `Ui.btnPrimary`, `Ui.btnNeutral`, `Ui.btnDanger`, `Ui.btnQuiet`. Notably,
  `Ui.elm` already exports exactly the status-badge primitive this plan
  needs — do not invent new color usage for pass/fail state:
  ```elm
  type PillTone = Neutral | Positive | Negative
  pill : PillTone -> String -> Html msg
  ```
  (`src/Ui.elm:404-436`, already used nowhere yet in this repo except its
  own definition — this plan is its first consumer).
- `Contracts.validate : List Tokens.FlatToken -> Contracts.Contract -> Components.Component -> List Contracts.Violation` (from TODO-03) and `Contracts.Violation = { path : List Int, property : Maybe String, message : String }`.
- `Model.contracts : Maybe (List Contracts.Contract)`,
  `Model.existingContracts : List String`,
  `Model.newContractRuleType : String`,
  `Model.newContractRuleFields : Dict String String` (from TODO-04).
- Messages available: `UpdateNewContractRuleType String`,
  `UpdateNewContractRuleField String String`, `AddContractRule`,
  `RemoveContractRule Int`, `SaveContract`, `DeleteContract String` (from
  TODO-04).

## Files

- Modify `src/Pages/ComponentRegistry.elm`

## What to build

### 1. Status badge in the component list (`viewComponentList`, `:158-222`)

For each component button in the `<ul>` (`:162-196`), compute its
contract status and render a small `Ui.pill` beside the name, inside the
same `button`:
- No entry in `model.contracts` for this component → no pill (nothing to
  report — most components won't have a contract, and a "no contract"
  pill on every row would be noise, not signal).
- Entry exists, `Contracts.validate resolvedTokens contract comp` is
  `[]` → `Ui.pill Positive "OK"`.
- Entry exists, violations non-empty →
  `Ui.pill Negative (String.fromInt (List.length violations))`.

This is the "at a glance" surface — a user browsing the component list
should see which components have failing contracts without clicking into
each one. Use the `resolveDisplayTokens` helper introduced above so this
matches exactly what `viewComponentEditor` computes for the same
component.

### 2. Usage contract section (`viewComponentEditor`, `:268-298`)

After the existing Layout section, add a new "Usage contract" section:

1. **Resolve the active contract**: `activeContract = model.contracts |> Maybe.withDefault [] |> List.filter (\c -> c.component == comp.name) |> List.head |> Maybe.withDefault { component = comp.name, rules = [] }`.
2. **Compute violations**: `violations = Contracts.validate displayTokens activeContract comp` — call this directly in the view (pure, no new `Model` field needed), the same "derive from `Model` in the view" pattern `viewUnsavedChanges` already uses for `componentsChanged`/`tokenDiffs` in `src/Pages/GitWorkflows.elm:65-103`.
3. **Section heading pill**: put a `Ui.pill` next to the "Usage contract"
   `h4` mirroring the list-badge logic above (`Positive "OK"` /
   `Negative "<n>"` / no pill when `activeContract.rules == []`), so the
   same status reads consistently whether the user is scanning the
   sidebar or looking at the open editor.
4. **Render violations**: wrap the violation list in a container with
   `Html.Attributes.attribute "aria-live" "polite"` — violations appear
   and disappear as the user types style values, with no explicit submit
   step, so a screen-reader user needs to hear about that change the same
   way a sighted user sees the pill count update. If `violations` is
   non-empty, render each as a small warning row (property name, if
   present, plus message) styled with `Tw.text_color (red s700)` (the
   same token `Pages/GitWorkflows.elm` already imports `red` for). If
   `activeContract.rules` is non-empty and `violations` is empty, show an
   affirming `Ui.mutedSmall` line ("No contract violations."). If
   `activeContract.rules` is empty, show a first-use hint instead ("No
   rules yet — add one below to start enforcing usage for this
   component.") rather than an empty list, so a component with no
   contract doesn't read as broken or loading.
5. **List existing rules**: for each rule in `activeContract.rules`
   (indexed), render a one-line human-readable summary (e.g. for
   `AllowedTokenGroups groups` → `"Allowed token groups: " ++ String.join ", " (List.map (String.join ".") groups)`) plus a small "Remove" action — use `Ui.btnQuiet` (the existing quiet inline-text-action style used for repeated per-row secondary actions) wired to `RemoveContractRule index`, rather than a full bordered button per row.
6. **Add-rule form**: a `select` (`Ui.selectInput`) for rule type bound to
   `model.newContractRuleType` via `onInput UpdateNewContractRuleType`,
   with options `"allowedTokenGroups"`, `"noHardcodedValues"`,
   `"spacingOnScale"`, `"contrastThreshold"` (labelled readably). Below it,
   conditionally render 1-3 `Ui.textInput` fields depending on the
   selected type, each wired via
   `onInput (UpdateNewContractRuleField "<fieldKey>")` reading its current
   value from `Dict.get "<fieldKey>" model.newContractRuleFields |> Maybe.withDefault ""`,
   each paired with a `Ui.mutedSmall` hint line underneath stating the
   expected format (not just a placeholder, which disappears the moment
   the user starts typing and offers no help if they get it wrong):
   - `allowedTokenGroups`: one field, key `"groups"`, placeholder
     `"interactive, spacing"`, hint "Comma-separated token group paths.".
   - `noHardcodedValues`: one field, key `"properties"`, placeholder
     `"color, background-color"`, hint "Comma-separated CSS property names.".
   - `spacingOnScale`: two fields, keys `"properties"` (placeholder
     `"padding, margin, gap"`) and `"scale"` (placeholder `"spacing"`,
     hint "Token group path acting as the allowed scale.").
   - `contrastThreshold`: three fields, keys `"foreground"` (placeholder
     `"color"`), `"background"` (placeholder `"background-color"`),
     `"minimumRatio"` (placeholder `"4.5"`, hint "A number, e.g. 4.5 for
     WCAG AA.").
   An "Add rule" button (`Ui.btnNeutral`, `onClick AddContractRule`). Per
   `TODO-04-contracts-gitlab-wiring.md`, `AddContractRule` silently does
   nothing on unparsable/empty required fields (matching this codebase's
   existing guard-and-no-op convention, e.g. `CreateComponent`'s empty-name
   guard at `src/Update.elm:568`) — the hint lines above exist specifically
   so that silent no-op doesn't read as a broken button to the user.
7. **Save / Delete buttons**: `Ui.btnPrimary`, `onClick SaveContract`,
   labelled "Save contract". Beside it, only when
   `List.member comp.name model.existingContracts` (i.e. a contract file
   already exists in the repo for this component — matches the same
   existence check `SaveComponent`/`DeleteComponent` already use),
   `Ui.btnDanger`, `onClick (DeleteContract comp.name)`, labelled "Delete
   contract" — every other editable file type in this app (theme,
   component, screen) has a delete action; a contract without one is a
   dead end once saved.

## Manual verification (no automated UI test suite exists in this repo)

1. `make dev`; open a project with at least two components.
2. Confirm neither component shows a pill in the sidebar yet (no
   contracts exist).
3. Select a component; confirm the "Usage contract" section shows the
   first-use hint (no rules yet).
4. Add a rule via the form (e.g. `noHardcodedValues` on `color`), click
   "Add rule" — confirm it appears in the rule list with a "Remove"
   action.
5. Give the component a raw hex `color` style value — confirm a violation
   appears live without saving anything, and the section's pill switches
   to `Negative "1"`.
6. Change the value to a `{token}` reference — confirm the violation
   clears and the pill switches to `Positive "OK"`.
7. Click "Save contract" — confirm (via the Network tab or GitLab UI)
   that `components/<name>.contract.json` is committed with the expected
   JSON shape from `TODO-02-contracts-schema.md`, and that the sidebar now
   shows the same `Positive "OK"` pill next to this component's name.
8. Reload the project — confirm the saved contract and its rules reload
   correctly, including both pills (exercises `GotContractFile` from
   TODO-04).
9. Click "Delete contract" — confirm the file is deleted from the repo,
   the button disappears (no `existingContracts` entry left), and the
   sidebar pill disappears too, while the component itself and its
   selection are untouched.

## Acceptance criteria

- `make check` passes (compiles cleanly; `elm-review` clean).
- The manual verification steps above all behave as described.
- The sidebar list and the open editor never disagree about a given
  component's contract status (both derive from the same
  `resolveDisplayTokens` + `Contracts.validate` call).
- No new `Model` fields or `Msg` constructors are introduced by this plan
  — it only consumes what `TODO-04-contracts-gitlab-wiring.md` already
  added.
