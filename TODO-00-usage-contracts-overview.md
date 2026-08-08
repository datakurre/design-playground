# Usage contracts: plan overview

This is an index over six standalone, self-contained implementation
documents (`TODO-01` through `TODO-06`) that together close the gap
`Roadmap.md` identifies: DTCG standardizes token *values* but has no
vocabulary for *usage rules* on top of them ("this component may only use
tokens from group X", "no hardcoded hex", "spacing must resolve to the
scale", "this color pairing must pass a contrast threshold").

Each `TODO-NN-*.md` file is written so a single agent picking up just that
file (with no memory of how this set of documents came to be) has
everything it needs: background, exact file paths and line numbers,
existing type shapes to match, and Red/Green TDD steps, per this repo's
`AGENTS.md` SOP ("When tasked with implementing a `TODO-NN-xxxx.md` item:
1. Read the TODO item and this `AGENTS.md` file. ..."). Execute in numeric
order — each later plan depends on the ones before it existing in the
codebase.

1. `TODO-01-colors-module.md` — color math (`Colors.elm`)
2. `TODO-02-contracts-schema.md` — usage-contract schema + codec (`Contracts.elm` types)
3. `TODO-03-contracts-validator.md` — the rule-checking engine (`Contracts.validate`)
4. `TODO-04-contracts-gitlab-wiring.md` — fetch/save/delete contract files, plus gate-to-editor navigation (`Types.elm`, `Update.elm`)
5. `TODO-05-component-registry-ui.md` — live violations, status badges, rule-builder, delete
6. `TODO-06-git-workflows-gate-ui.md` — pre-commit pass/fail summary with click-through

Together these plans deliver a schema for per-component usage contracts, a
validator, and two enforcement surfaces (live in the editor, and a
pass/fail gate before committing).

## UI/UX thread running through 04-06

Called out here since it's easy to lose across separate documents: every
other editable file type in this app (theme, component, screen) supports
create/edit/save/delete and shows its state where a user is already
looking; contracts get the same treatment rather than being a lesser,
write-only feature. Concretely: a status badge reusing the existing
`Ui.pill` component (`src/Ui.elm:404-436`, previously unused) appears both
in the component sidebar list and next to the contract editor itself, so
pass/fail/uncontracted status is visible at a glance and never disagrees
between the two places it's shown; contracts can be deleted, not just
created; violation lists are `aria-live="polite"` since they update as a
side effect of unrelated typing, not an explicit submit; the Git Workflows
gate distinguishes "nothing to check yet" from "passing" (a project with
zero contracts is not the same as a project that passes its contracts);
and clicking a violation in the gate jumps straight to the offending
component instead of leaving the user to find it by hand.
