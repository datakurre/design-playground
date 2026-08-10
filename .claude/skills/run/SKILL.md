---
name: run
description: Launch, render or screenshot the design-playground app. Use when asked to run or start the app, to check a change works in the real browser rather than only in tests, or when a build looks fine but the page renders wrong.
---

# Running design-playground

A backend-less Elm SPA served by Vite. There is nothing to start but the front
end.

## The two ways to run it

**`make smoke`** — build it, render it in headless chromium, assert it booted,
and write screenshots to `.smoke/`. This is what you want in an agent session:
it is non-interactive, it exits non-zero when the app is broken, and it produces
images you can open with the Read tool.

```
make smoke          # builds first, then scripts/smoke.sh
```

It checks two URLs: the home route, and the deep link
`#/acme/design/components/Button`, which proves a fragment route is parsed and
rendered rather than throwing. Screenshots land at `.smoke/home.png` and
`.smoke/route.png`. **Open them.** An exit code of 0 only means the app root
rendered; the picture is where you see whether it rendered *correctly*.

Signed out, the two screenshots are identical — opening a project needs a token,
so the deep link falls back to the landing page. That is expected.

**`make dev`** — the Vite dev server with hot reload, at
`http://localhost:5173/design-playground/`. Useful for a human. It blocks, so
run it in the background if you start it at all.

Note the `/design-playground/` base path in both cases — it is set by `base` in
`vite.config.js` because the site is served from a GitHub Pages subpath. A URL
without it 404s.

## What you can and cannot see without signing in

**You cannot sign in locally.** `clientId` and `redirectUri` in `src/Auth.elm`
are hardcoded to the deployed instance, so the OAuth round trip always redirects
to the hosted site rather than back to localhost. Do not try to work around it
by editing those constants.

So without a token you can verify: the app boots, the shell and app bar render,
fragment routing resolves, styling is applied, and anything reachable before a
project is opened. You cannot verify anything that needs repository data —
tokens, components, screens, branches, commits. That is what the unit tests are
for, and after the `Effect` refactor it is what asserting on effects is for.

## Deep links

Routing is fragment-based (`#/namespace/project/tab/item`) because GitHub Pages
has no history fallback. `src/Route.elm` is the parser, and `tests/RouteTest.elm`
covers the awkward cases — notably that a trailing `export`/`tokens`/
`components` only counts as a tab when at least two segments remain to name the
project, so `#/acme/export` is the *project* `acme/export`.

## When the page renders but looks wrong

Almost always Tailwind class extraction. Tailwind's scanner only sees class
names that appear literally in the source; every colour in this app is composed
at runtime (`Tw.bg_color (slate s50)` → `"bg-slate-50"`) and is found instead by
the elm-tailwind-classes extractor, which shells out to `elm-review`. When that
fails, `vite build` prints `CLASS EXTRACTION FAILED` **and still exits 0**,
leaving a stylesheet that is the right size and missing every colour.

`make smoke` fails loudly on this now. The usual cause is `elm-review` being
unable to reach `package.elm-lang.org`: the dev container has no direct DNS and
proxies all egress, and Node ignores `HTTP_PROXY` unless told. `devenv.nix` sets
`NODE_USE_ENV_PROXY=1` for exactly this reason, so if you hit it, check you are
in the devenv shell.
