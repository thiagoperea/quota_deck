SHELL := /bin/zsh

.PHONY: setup format analyze test test-core test-app run-macos run-windows run-linux build-macos build-windows build-linux cli cli-install mock clean

setup:
	cd packages/models && dart pub get
	cd packages/core && dart pub get
	cd packages/cli && dart pub get
	cd app && flutter pub get

format:
	cd packages/models && dart format lib test
	cd packages/core && dart format lib test tool
	cd packages/cli && dart format lib bin test
	cd app && dart format lib test

analyze:
	cd packages/models && dart analyze
	cd packages/core && dart analyze
	cd packages/cli && dart analyze
	cd app && dart analyze lib test

test: test-core test-app

test-core:
	cd packages/models && dart test
	cd packages/core && dart test
	cd packages/cli && dart test

test-app:
	cd app && flutter test

run-macos:
	cd app && flutter run -d macos

run-windows:
	cd app && flutter run -d windows

run-linux:
	cd app && flutter run -d linux

build-macos:
	cd app && flutter build macos --release

build-windows:
	cd app && flutter build windows --release

build-linux:
	cd app && flutter build linux --release

cli:
	cd packages/cli && dart run bin/qdeck.dart $(ARGS)

cli-install:
	cd packages/cli && dart pub global activate --source path .

mock:
	cd app && flutter run -d macos --dart-define=QDECK_MOCK=1

clean:
	rm -rf app/build packages/*/.dart_tool packages/*/build
