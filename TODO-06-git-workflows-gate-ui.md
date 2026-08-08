# TODO-06: Git Workflows gate UI — pre-commit pass/fail summary

Part of the usage-contracts effort — see `TODO-00-usage-contracts-overview.md`
for the full set. This document is standalone: everything needed to
implement it is below.

## Objective

Add a pass/fail "Contract check" summary to the Git Workflows page, so
usage-contract violations are visible before a commit — the closest thing
this app has to a CI gate, matching how `elm-review` surfaces issues
before a push in this project's own toolchain.

A gate a user can't act on from where they're standing isn't much of a
gate — this plan also wires each listed violation straight back to the
component that owns it, one click away.

## Prerequisites

Requires `TODO-03-contracts-validator.md` (`Contracts.validate`) and
`TODO-04-contracts-gitlab-wiring.md` (`Model.contracts`, and the
`JumpToComponent String` message) merged. Can be built in parallel with
`TODO-05-component-registry-ui.md` — both only depend on 03/04, not on
each other.

## Background

`src/Pages/GitWorkflows.elm` is pure view code. `viewGitWorkflows`
(`:13-27`) renders `viewBranch`, `viewUnsavedChanges`, then
`viewMergeRequests` in sequence when a project is selected.
`viewUnsavedChanges` (`:65-103`) is the closest existing analogue: it
derives `componentsChanged`/`tokenDiffs` straight from `Model` fields in
a `let` block (no new `Model` state), and renders either a "nothing
changed" message or a `Ui.panelSunken` block listing what changed.

`src/Ui.elm:404-436` already defines the status-badge primitive this
section needs — reuse it rather than reaching for `Tailwind.Theme` colors
directly (this file's existing `emerald`/`red` imports were for other,
now-superseded styling; prefer the shared component so this gate matches
the same visual language `TODO-05-component-registry-ui.md` uses for its
per-component pills):
```elm
type PillTone = Neutral | Positive | Negative
pill : PillTone -> String -> Html msg
```

`Model.components : Maybe (List Components.Component)`,
`Model.tokens : Maybe (List Tokens.FlatToken)`,
`Model.contracts : Maybe (List Contracts.Contract)` (the last one from
TODO-04). `Contracts.validate : List Tokens.FlatToken -> Contracts.Contract -> Components.Component -> List Contracts.Violation`.
`JumpToComponent String` (from TODO-04) switches to the Component
Registry tab with the given component selected.

## Files

- Modify `src/Pages/GitWorkflows.elm`

## What to build

Add a new `viewContractCheck : Model -> Html Msg` function, called from
`viewGitWorkflows` alongside the existing three view calls (insert it
between `viewUnsavedChanges` and `viewMergeRequests`, since "does what I'm
about to commit satisfy its contracts" belongs right after "what changed").

Compute, in a `let` block:
- `tokens = model.tokens |> Maybe.withDefault []`
- `components = model.components |> Maybe.withDefault []`
- `contracts = model.contracts |> Maybe.withDefault []`
- `allViolations : List ( String, Contracts.Violation )` — for every
  component, for every contract whose `.component` matches that
  component's name, `Contracts.validate tokens contract comp`, paired with
  the component's name.

Render three distinct states — do not collapse "nothing to check" into
"everything passed", since those mean different things to a user deciding
whether it's safe to commit:
1. **`List.isEmpty contracts`** → `Ui.pill Neutral "No contracts"` plus a
   `Ui.mutedSmall` line: "This project has no usage contracts yet." (There
   is nothing to gate on — this is not a pass.)
2. **`not (List.isEmpty contracts) && List.isEmpty allViolations`** →
   `Ui.pill Positive "Passing"` plus "All components satisfy their usage
   contracts."
3. **`not (List.isEmpty allViolations)`** →
   `Ui.pill Negative (String.fromInt (List.length allViolations))` next to
   the section heading, then a `Ui.panelSunken` list, one row per
   violation, each row a clickable button (not a bare `div`) reading
   `"<component>: <message>"`, `onClick (JumpToComponent name)`, styled
   with `Ui.btnQuiet` so it reads as a link/action rather than static
   text. Wrap the whole violations block in
   `Html.Attributes.attribute "aria-live" "polite"` — like the editor's
   violation list in `TODO-05-component-registry-ui.md`, this list changes
   as the user edits elsewhere in the app without any page navigation, so
   assistive tech needs the same live-region treatment.

Only components with a matching `Contract` (`c.component == comp.name`)
contribute violations — a component with no contract file is neither
passing nor failing, it's simply not covered, which is why state 1 above
exists as its own distinct case from state 2.

## Manual verification (no automated UI test suite exists in this repo)

1. `make dev`; open a project with no contracts yet. Navigate to Git
   Workflows — confirm the "No contracts" neutral state, not a false
   "passing" state.
2. Following `TODO-05-component-registry-ui.md`'s manual steps, save a
   contract with a rule violation on one component. Navigate to Git
   Workflows — confirm the section now shows the `Negative` count pill and
   lists the violation with the component name and message.
3. Click the violation row — confirm it switches to the Component
   Registry tab with that exact component already selected (exercises
   `JumpToComponent`).
4. Fix the violation (e.g. replace the hardcoded hex with a token
   reference) and return to Git Workflows — confirm the section updates
   to the `Positive "Passing"` state without needing to save/reload (it's
   a pure view computation, so it should react immediately to the
   in-memory `Model.components` edit).
5. Confirm a component with no contract at all does not appear in the
   violations list and does not prevent the "Passing" state once every
   *contracted* component is clean.

## Acceptance criteria

- `make check` passes (compiles cleanly; `elm-review` clean).
- The manual verification steps above all behave as described.
- The three states (no contracts / passing / violations) are visually and
  textually distinct, using `Ui.pill`'s existing tones.
- No new `Model` fields or `Msg` constructors — this plan only reads
  existing state and calls `Contracts.validate` and `JumpToComponent`,
  both already added by `TODO-04-contracts-gitlab-wiring.md`.
