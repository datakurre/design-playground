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

check: gen
	@elm-test
	@elm-review
