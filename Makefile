.PHONY: build test app run clean

build:
	swift build

test:
	swift test

app:
	scripts/make-app.sh

run: app
	open "build/all the ports.app"

clean:
	rm -rf .build build
