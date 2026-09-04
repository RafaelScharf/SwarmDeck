# SwarmDeck Makefile

.PHONY: all build release app dmg zip test clean run

all: app

build:
	swift build

release:
	swift build -c release

app:
	./scripts/package_app.sh

zip:
	./scripts/package_app.sh --zip

dmg:
	./scripts/package_app.sh --dmg

dist:
	./scripts/package_app.sh --zip --dmg

run:
	open build/Release/SwarmDeck.app

test:
	swift build
	swift temp/prototypes/test_packaging_release.swift

clean:
	swift package clean
	rm -rf build/
