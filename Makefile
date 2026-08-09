.PHONY: gen check dev build dist-ci

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
check: gen
	@elm make src/Main.elm --output=/dev/null
	@elm-test
	@elm-review
