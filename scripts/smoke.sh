#!/usr/bin/env bash
#
# Boots the built app in headless chromium and checks that it rendered.
#
# `make check` proves the code type-checks and that the pure logic behaves. It
# cannot tell you the app still starts: a bad flag decoder, a broken port wiring
# in src/main.js, or a failed asset path all compile fine and produce a blank
# page. This is the cheapest thing that catches that class of failure.
#
# What it does NOT catch: console warnings, visual regressions, anything behind
# GitLab sign-in (see .claude/skills/run/SKILL.md for why you cannot sign in
# locally). Treat a pass as "the app boots and routes", nothing more.
#
# Reads dist/, so run `make build` first — `make smoke` does that for you.
# Screenshots land in .smoke/ and are worth looking at, not just exit-code
# checking; they are the only rendering feedback in the repo.
set -euo pipefail

cd "$(dirname "$0")/.."

PORT="${SMOKE_PORT:-4173}"
OUT=".smoke"
BASE="http://localhost:${PORT}/design-playground/"

if [ ! -f dist/index.html ]; then
    echo "smoke: dist/index.html is missing — run 'make build' first." >&2
    exit 1
fi

mkdir -p "$OUT"

# Tailwind's own scanner only sees class names that appear literally in the
# source. Anything the Elm code composes at runtime — `Tw.bg_color (slate s50)`
# becoming "bg-slate-50", i.e. every colour in the app — is found instead by the
# elm-tailwind-classes extractor, which shells out to elm-review. When that
# fails, vite prints "CLASS EXTRACTION FAILED" and *still exits 0*, leaving a
# stylesheet that looks fine by size and is missing every colour. Chromium
# renders such a build without complaint, so the screenshots alone would not
# tell you. Check the stylesheet directly.
css="$(ls dist/assets/*.css 2>/dev/null | head -1)"
if [ -z "$css" ]; then
    echo "smoke: no stylesheet in dist/assets — did the build finish?" >&2
    exit 1
fi

for utility in bg-slate-50 bg-orange-600; do
    if ! grep -q "\.${utility}" "$css"; then
        echo "smoke: ${css} has no .${utility} rule — Tailwind class extraction failed." >&2
        echo "       Re-run 'make build' and look for CLASS EXTRACTION FAILED in the output." >&2
        echo "       Usual cause: elm-review could not reach package.elm-lang.org. The dev" >&2
        echo "       container proxies all egress, so Node needs NODE_USE_ENV_PROXY=1 — it is" >&2
        echo "       set in devenv.nix, so check you are actually in the devenv shell." >&2
        exit 1
    fi
done

vite preview --port "$PORT" --strictPort >"$OUT/preview.log" 2>&1 &
PREVIEW_PID=$!
trap 'kill "$PREVIEW_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 60); do
    if curl -sf -o /dev/null "$BASE"; then break; fi
    sleep 0.25
done

if ! curl -sf -o /dev/null "$BASE"; then
    echo "smoke: vite preview never came up on port ${PORT}:" >&2
    cat "$OUT/preview.log" >&2
    exit 1
fi

# --no-sandbox is required because the dev container already runs unprivileged
# and cannot create the nested user namespace chromium's sandbox wants.
chrome() {
    chromium \
        --headless \
        --no-sandbox \
        --disable-gpu \
        --disable-dev-shm-usage \
        --user-data-dir="$OUT/chrome" \
        --window-size=1280,900 \
        --virtual-time-budget=5000 \
        "$@" 2>/dev/null
}

# The marker is a data-smoke attribute on the app root in src/Main.elm. If Elm's
# init throws, the body stays as index.html left it and the attribute is absent.
check() {
    local name="$1" url="$2"

    if ! chrome --dump-dom "$url" | grep -q 'data-smoke="app"'; then
        echo "smoke: ${name} did not render — no data-smoke marker at ${url}" >&2
        echo "smoke: the app root is in src/Main.elm's view; if you removed the" >&2
        echo "       marker deliberately, update this script too." >&2
        return 1
    fi

    chrome --screenshot="${OUT}/${name}.png" "$url" >/dev/null
    echo "smoke: ${name} ok — ${OUT}/${name}.png"
}

failed=0

# The home route, i.e. does the shell boot at all.
check home "$BASE" || failed=1

# A deep link. Routing is fragment-based (GitHub Pages has no history
# fallback), so this proves a fragment route is parsed and rendered rather than
# throwing on the way in.
#
# Signed out, it looks identical to home: opening a project needs a token, so
# the app falls back to the landing page. The screenshots being the same is
# expected, not a bug. What this catches is a route that crashes the app.
check route "${BASE}#/acme/design/components/Button" || failed=1

# The same, carrying a branch. The branch is split off the fragment before the
# segments are, on the first raw "?" — this is the only place that pre-pass is
# exercised in a real browser rather than in a unit test.
check branch "${BASE}#/acme/design/tokens?branch=feature%2Fx" || failed=1

if [ "$failed" -ne 0 ]; then
    echo "smoke: FAILED" >&2
    exit 1
fi

echo "smoke: passed"
