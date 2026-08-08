# TODO-01: Color math module (`Colors.elm`)

Part of the usage-contracts effort — see `TODO-00-usage-contracts-overview.md`
for the full set. This document is standalone: everything needed to
implement it is below.

## Objective

Add a small, dependency-free color-math module, `src/Colors.elm`, providing
hex-color parsing and WCAG contrast-ratio calculation. This is a pure
foundation module — no dependency on any other new code in this project —
needed later by the contract validator's contrast-threshold rule.

## Background

`design-playground` is a pure-Elm app (`elm.json` lists only
`elm/browser`, `elm/core`, `elm/html`, `elm/http`, `elm/json`, `elm/url` as
direct dependencies — no `elm/regex`, no color package). Do not add new
`elm.json` dependencies; implement hex parsing and WCAG math with plain
`String`/`Char`/`List` functions. Design tokens' color values in this
codebase are plain hex strings, e.g. `"#ff0000"` (see
`tests/TokensTest.elm`), so `parseHex` only needs to handle `#rgb` and
`#rrggbb` forms (alpha variants `#rgba`/`#rrggbbaa` are out of scope — return
`Nothing` for anything else).

## Files

- Create `src/Colors.elm`
- Create `tests/ColorsTest.elm`

## Red/Green TDD steps

1. **Red**: write `tests/ColorsTest.elm` first, using the existing test
   style (see `tests/TokensTest.elm` for the `module X exposing (..)` /
   `import Expect` / `import Test exposing (..)` / `describe`/`test`
   idiom). Cover:
   - `parseHex "#fff"` and `parseHex "#ffffff"` both equal
     `Just { r = 255, g = 255, b = 255 }`.
   - `parseHex "#000"` equals `Just { r = 0, g = 0, b = 0 }`.
   - `parseHex "#3366CC"` equals `Just { r = 51, g = 102, b = 204 }`
     (case-insensitive hex digits).
   - `parseHex "not-a-color"`, `parseHex "#12"`, `parseHex "#12345"` all
     equal `Nothing`.
   - `contrastRatio { r=0,g=0,b=0 } { r=255,g=255,b=255 }` is approximately
     `21.0` (use `Expect.within (Expect.Absolute 0.05) 21.0 ...`).
   - `contrastRatio` is symmetric: same result regardless of argument order.
   - `contrastRatio { r=255,g=255,b=255 } { r=255,g=255,b=255 }` is
     approximately `1.0`.
   Run `devenv shell -- elm-test` (or `elm-test` if already inside
   `devenv shell`) and confirm these fail (module doesn't exist yet).
2. **Green**: implement `src/Colors.elm`:
   ```elm
   module Colors exposing (Rgb, parseHex, contrastRatio)

   type alias Rgb =
       { r : Int, g : Int, b : Int }

   parseHex : String -> Maybe Rgb
   contrastRatio : Rgb -> Rgb -> Float
   ```
   - `parseHex`: trim input, strip a leading `#`, then handle exactly 3 or
     6 remaining hex-digit characters (reject anything else, including
     non-hex characters). For 3 digits, duplicate each digit (`"3ac"` →
     `"33aacc"`) before parsing. Parse each 2-digit pair as base-16.
   - `contrastRatio`: implement the WCAG relative-luminance formula per
     channel — `cs = channel / 255`, then
     `if cs <= 0.03928 then cs / 12.92 else ((cs + 0.055) / 1.055) ^ 2.4`;
     `L = 0.2126 * R' + 0.7152 * G' + 0.0722 * B'`; ratio is
     `(max(L1,L2) + 0.05) / (min(L1,L2) + 0.05)`.
   Run `elm-test` again until green.
3. Run `elm-review` (via `devenv shell -- elm-review` or `make check`) to
   confirm no unused-code/missing-type-annotation warnings.

## Acceptance criteria

- `tests/ColorsTest.elm` passes.
- `make check` passes (this module doesn't touch anything else, so the
  full existing suite must stay green).
- No new `elm.json` dependencies added.
