SHELL := /bin/zsh
.PHONY: build test app demo run clean
build:
	swift build
test:
	./scripts/test.sh
app:
	./scripts/build-app.sh
demo: app
	open -n "dist/AC Control.app" --args --demo --show-panel
run: app
	open "dist/AC Control.app"
clean:
	swift package clean
