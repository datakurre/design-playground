.PHONY: gen check dev build dist-ci test test-js fmt review watch smoke clean distclean

# elm-tailwind-classes generates the type-safe Tailwind API into .elm-tailwind/,
# which elm.json lists as a source directory. It must exist before elm, elm-test
# or elm-review run, so every target depends on it.
gen:
	@elm-tailwind-classes gen

dev: gen
	@vite

build: gen
	@vite build

dist-ci: gen
	@vite build

# elm-test only compiles the test modules and their dependencies, and elm-review
# parses rather than type-checks — neither reaches src/Main.elm. Compile the app
# entry point explicitly so a broken Model/view can't pass `make check`.
#
# elm-format runs first because neither of the others has an opinion about
# layout, so unformatted code used to reach main unnoticed. `--validate` reports
# rather than rewrites; run `make fmt` to fix what it finds.
check: gen
	@elm-format --validate src/ tests/
	@elm make src/Main.elm --output=/dev/null
	@elm-test
	@node --test tests/schemas.test.js
	@elm-review

# The targets below exist so you don't have to run the whole of `check` to learn
# one thing. `check` is still the gate — it is what the pre-commit hook and CI
# run, and passing a narrower target is not the same as passing it.

# `make test` runs both suites; `make test T=Contracts` runs tests/ContractsTest.elm
# alone, which is the fast loop while you are working on one module.
test: gen
ifdef T
	@elm-test tests/$(T)Test.elm
else
	@elm-test
	@node --test tests/schemas.test.js
endif

test-js:
	@node --test tests/schemas.test.js

# The fixer for what `check` reports. elm-format rewrites Elm; treefmt covers the
# Nix files (see the treefmt block in devenv.nix for what it is configured to do).
fmt:
	@elm-format --yes src/ tests/
	@treefmt

review: gen
	@elm-review

# Re-runs the tests whenever an Elm file changes. entr exits when the file list
# it was given goes stale, so adding a new module means restarting the watch.
watch: gen
	@find src tests -name '*.elm' | entr -c make test

# Boots the built app in headless chromium and checks it actually rendered.
# Type-checking cannot tell you the app still starts; this can. See scripts/smoke.sh.
smoke: build
	@./scripts/smoke.sh

clean:
	@rm -rf .elm-tailwind dist .vite .smoke

# elm-stuff/0.19.1/{d.dat,i.dat} is the only Elm package cache in the dev
# container — there is no ELM_HOME and no ~/.elm. Removing it forces a fresh
# download from package.elm-lang.org, which fails if the network is restricted.
# That is why `clean` leaves it alone and this target is separate.
distclean: clean
	@rm -rf elm-stuff
