SHELL := /bin/sh

.PHONY: setup format analyze test test-core test-app run-windows run-macos run-linux \
	build-windows build-macos build-linux cli cli-install mock clean installer

# Runner único cross-platform (Windows/macOS/Linux). Requer `dart` no PATH.
setup:
	dart tool/tasks.dart setup

format:
	dart tool/tasks.dart format

analyze:
	dart tool/tasks.dart analyze

test:
	dart tool/tasks.dart test

test-core:
	cd packages/models && dart test
	cd packages/core && dart test
	cd packages/cli && dart test

test-app:
	cd app && flutter test

run-windows:
	dart tool/tasks.dart run-windows

run-macos:
	dart tool/tasks.dart run-macos

run-linux:
	dart tool/tasks.dart run-linux

build-windows:
	dart tool/tasks.dart build-windows

build-macos:
	dart tool/tasks.dart build-macos

build-linux:
	dart tool/tasks.dart build-linux

installer:
	dart tool/tasks.dart installer

cli:
	dart tool/tasks.dart cli $(ARGS)

cli-install:
	cd packages/cli && dart pub global activate --source path .

mock:
	cd app && flutter run -d macos --dart-define=QDECK_MOCK=1

clean:
	cd packages/models && dart pub cache clean >/dev/null 2>&1 || true
	rm -rf app/build packages/*/.dart_tool packages/*/build
