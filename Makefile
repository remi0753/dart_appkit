SHELL := /bin/zsh

PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_DIR ?= $(PROJECT_ROOT)/build
NATIVE_BUILD_DIR := $(BUILD_DIR)/native
MACOSX_DEPLOYMENT_TARGET ?= 14.0
DART_EXECUTABLE := $(shell command -v dart)
DART_SDK ?= $(shell realpath $(DART_EXECUTABLE) | xargs dirname | xargs dirname)
DART_ENGINE_ROOT ?= $(PROJECT_ROOT)/.dart_tool/dart-engine/sdk
HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),arm64)
DART_ENGINE_RELEASE_ARCH := ARM64
else ifeq ($(HOST_ARCH),x86_64)
DART_ENGINE_RELEASE_ARCH := X64
else
DART_ENGINE_RELEASE_ARCH := UNSUPPORTED
endif
DART_ENGINE_LIBRARY ?= $(DART_ENGINE_ROOT)/xcodebuild/Release$(DART_ENGINE_RELEASE_ARCH)/libdart_engine_jit_shared.dylib

CLANG := $(shell xcrun --find clang)
CLANGXX := $(shell xcrun --find clang++)
SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)

WARNINGS := -Wall -Wextra -Wpedantic -Werror
COMMON_FLAGS := $(WARNINGS) -fvisibility=hidden -isysroot $(SDKROOT) \
	-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)
OBJCXX_FLAGS := $(COMMON_FLAGS) -std=c++20 -fobjc-arc -fblocks
APPKIT_LIBS := -framework AppKit -framework CoreFoundation

BRIDGE_HEADERS := \
	$(PROJECT_ROOT)/native/bridge/include/dart_appkit.h \
	$(PROJECT_ROOT)/native/bridge/src/AppKitObjects.h \
	$(PROJECT_ROOT)/native/bridge/src/BridgeInternal.h \
	$(PROJECT_ROOT)/native/bridge/src/ObjectRegistry.h
BRIDGE_SOURCES := \
	$(PROJECT_ROOT)/native/bridge/src/AppKitBridge.mm \
	$(PROJECT_ROOT)/native/bridge/src/EventSink.mm \
	$(PROJECT_ROOT)/native/bridge/src/ObjectRegistry.mm \
	$(PROJECT_ROOT)/native/bridge/src/TextView.mm
RUNNER_SOURCES := \
	$(PROJECT_ROOT)/native/runner/main.mm \
	$(PROJECT_ROOT)/native/runner/AppDelegate.mm \
	$(PROJECT_ROOT)/native/runner/DartHost.mm \
	$(PROJECT_ROOT)/native/runner/DartMessagePump.mm \
	$(PROJECT_ROOT)/native/runner/RunnerArguments.cc
RUNNER_HEADERS := \
	$(PROJECT_ROOT)/native/runner/AppDelegate.h \
	$(PROJECT_ROOT)/native/runner/DartHost.h \
	$(PROJECT_ROOT)/native/runner/DartMessagePump.h \
	$(PROJECT_ROOT)/native/runner/RunnerArguments.h \
	$(PROJECT_ROOT)/native/runner/RunnerConfiguration.h
NATIVE_TEST_SOURCES := \
	$(PROJECT_ROOT)/native/bridge/test/BridgeTests.mm
MESSAGE_PUMP_TEST_SOURCES := \
	$(PROJECT_ROOT)/native/runner/DartMessagePump.mm \
	$(PROJECT_ROOT)/native/runner/test/DartMessagePumpTests.mm
RUNNER_ARGUMENT_TEST_SOURCES := \
	$(PROJECT_ROOT)/native/runner/RunnerArguments.cc \
	$(PROJECT_ROOT)/native/runner/test/RunnerArgumentsTests.cc

BRIDGE_LIBRARY := $(NATIVE_BUILD_DIR)/libdart_appkit_bridge.dylib
NATIVE_TEST_BINARY := $(NATIVE_BUILD_DIR)/bridge_tests
MESSAGE_PUMP_TEST_BINARY := $(NATIVE_BUILD_DIR)/message_pump_tests
RUNNER_ARGUMENT_TEST_BINARY := $(NATIVE_BUILD_DIR)/runner_argument_tests
RUNNER_SHELL_TEST_BINARY := $(NATIVE_BUILD_DIR)/runner_shell_test
RUNNER_BINARY := $(NATIVE_BUILD_DIR)/dart_appkit_runner

.PHONY: help validate contract-check engine engine-check bridge native-test runner runner-syntax runner-argument-test runner-shell-test message-pump-test dart-test example-test example-smoke run-example ffi-smoke test clean

help:
	@echo "Dart AppKit Embedder targets:"
	@echo "  make validate       Validate layout, scripts, and C/C++ ABI headers"
	@echo "  make engine         Fetch, build, and validate the pinned Dart Engine"
	@echo "  make engine-check   Validate DART_SDK/DART_ENGINE_* inputs"
	@echo "  make bridge         Build the standalone AppKit bridge dylib"
	@echo "  make native-test    Build and run native bridge contract tests"
	@echo "  make runner-syntax  Compile-check Runner against Dart 3.13.2 declarations"
	@echo "  make runner-argument-test  Test Runner CLI parsing and exit contract"
	@echo "  make runner-shell-test  Link Runner shell and execute pre-VM failures"
	@echo "  make message-pump-test  Test bounded main-run-loop Dart scheduling"
	@echo "  make runner         Build the embedded Dart/AppKit Runner"
	@echo "  make dart-test      Analyze and test the Dart package"
	@echo "  make example-test   Analyze and compile the hello-window Kernel"
	@echo "  make example-smoke  Launch hello-window and close it automatically"
	@echo "  make run-example    Launch hello-window until its window is closed"
	@echo "  make test           Run all locally available checks"

validate: contract-check
	@$(PROJECT_ROOT)/scripts/validate_scaffold.sh

contract-check:
	@mkdir -p $(NATIVE_BUILD_DIR)
	@$(CLANG) $(COMMON_FLAGS) -std=c11 -I$(PROJECT_ROOT)/native/bridge/include \
		-fsyntax-only $(PROJECT_ROOT)/native/bridge/test/header_compile.c
	@$(CLANGXX) $(COMMON_FLAGS) -std=c++20 -I$(PROJECT_ROOT)/native/bridge/include \
		-fsyntax-only $(PROJECT_ROOT)/native/bridge/test/header_compile.cc

engine:
	@$(PROJECT_ROOT)/scripts/bootstrap_dart_engine.sh

engine-check:
	@DART_SDK="$(DART_SDK)" \
		DART_ENGINE_ROOT="$(DART_ENGINE_ROOT)" \
		DART_ENGINE_LIBRARY="$(DART_ENGINE_LIBRARY)" \
		$(PROJECT_ROOT)/scripts/check_dart_engine.sh

$(BRIDGE_LIBRARY): $(BRIDGE_HEADERS) $(BRIDGE_SOURCES)
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) -dynamiclib \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/native/bridge/src \
		$(BRIDGE_SOURCES) $(APPKIT_LIBS) \
		-Wl,-install_name,@rpath/libdart_appkit_bridge.dylib \
		-o $@

bridge: $(BRIDGE_LIBRARY)

$(NATIVE_TEST_BINARY): $(BRIDGE_HEADERS) $(BRIDGE_SOURCES) $(NATIVE_TEST_SOURCES)
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/native/bridge/src \
		$(BRIDGE_SOURCES) $(NATIVE_TEST_SOURCES) $(APPKIT_LIBS) \
		-o $@

native-test: $(NATIVE_TEST_BINARY)
	@$(NATIVE_TEST_BINARY)

$(RUNNER_ARGUMENT_TEST_BINARY): $(RUNNER_ARGUMENT_TEST_SOURCES) \
		$(PROJECT_ROOT)/native/runner/RunnerArguments.h \
		$(PROJECT_ROOT)/native/runner/RunnerConfiguration.h
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(COMMON_FLAGS) -std=c++20 \
		-I$(PROJECT_ROOT)/native/runner \
		$(RUNNER_ARGUMENT_TEST_SOURCES) -o $@

runner-argument-test: $(RUNNER_ARGUMENT_TEST_BINARY)
	@$(RUNNER_ARGUMENT_TEST_BINARY)

$(RUNNER_SHELL_TEST_BINARY): $(BRIDGE_HEADERS) $(BRIDGE_SOURCES) \
		$(RUNNER_HEADERS) $(RUNNER_SOURCES) $(PROJECT_ROOT)/Makefile
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-Wno-gnu-anonymous-struct -Wno-nested-anon-types \
		-DDA_DART_ENGINE_REVISION=\"shell-test\" \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/native/bridge/src \
		-I$(PROJECT_ROOT)/native/runner \
		-I$(PROJECT_ROOT)/native/runner/test_support \
		-iquote$(shell realpath $(shell command -v dart) | xargs dirname | xargs dirname) \
		$(BRIDGE_SOURCES) $(RUNNER_SOURCES) $(APPKIT_LIBS) \
		-Wl,-undefined,dynamic_lookup -Wl,-export_dynamic \
		-o $@

runner-shell-test: $(RUNNER_SHELL_TEST_BINARY)
	@$(PROJECT_ROOT)/scripts/test_runner_shell.sh $(RUNNER_SHELL_TEST_BINARY)

$(MESSAGE_PUMP_TEST_BINARY): $(RUNNER_HEADERS) $(MESSAGE_PUMP_TEST_SOURCES)
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-Wno-gnu-anonymous-struct -Wno-nested-anon-types \
		-I$(PROJECT_ROOT)/native/runner \
		-I$(PROJECT_ROOT)/native/runner/test_support \
		-iquote$(shell realpath $(shell command -v dart) | xargs dirname | xargs dirname) \
		$(MESSAGE_PUMP_TEST_SOURCES) -framework CoreFoundation \
		-o $@

message-pump-test: $(MESSAGE_PUMP_TEST_BINARY)
	@$(MESSAGE_PUMP_TEST_BINARY)

runner-syntax: $(BRIDGE_HEADERS) $(RUNNER_HEADERS) $(RUNNER_SOURCES)
	@$(CLANGXX) $(OBJCXX_FLAGS) \
		-Wno-gnu-anonymous-struct -Wno-nested-anon-types -fsyntax-only \
		-DDA_DART_ENGINE_REVISION=\"syntax-only\" \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/native/bridge/src \
		-I$(PROJECT_ROOT)/native/runner \
		-I$(PROJECT_ROOT)/native/runner/test_support \
		-iquote$(shell realpath $(shell command -v dart) | xargs dirname | xargs dirname) \
		$(RUNNER_SOURCES)

$(RUNNER_BINARY): $(BRIDGE_HEADERS) $(BRIDGE_SOURCES) $(RUNNER_HEADERS) \
		$(RUNNER_SOURCES) $(PROJECT_ROOT)/Makefile $(DART_ENGINE_LIBRARY)
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-Wno-gnu-anonymous-struct -Wno-nested-anon-types \
		-DDA_DART_ENGINE_REVISION=\"$(shell git -C $(DART_ENGINE_ROOT) rev-parse HEAD)\" \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/native/bridge/src \
		-I$(PROJECT_ROOT)/native/runner \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(BRIDGE_SOURCES) $(RUNNER_SOURCES) \
		$(DART_ENGINE_LIBRARY) $(APPKIT_LIBS) \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic \
		-o $@

runner: engine-check $(RUNNER_BINARY)

dart-test:
	@cd $(PROJECT_ROOT)/packages/dart_appkit && dart pub get
	@cd $(PROJECT_ROOT)/packages/dart_appkit && dart analyze
	@cd $(PROJECT_ROOT)/packages/dart_appkit && dart run test/run_tests.dart
	@cd $(PROJECT_ROOT)/packages/dart_appkit && dart run test/launcher_tests.dart

example-test:
	@mkdir -p $(BUILD_DIR)/test
	@cd $(PROJECT_ROOT)/examples/hello_window && dart pub get
	@cd $(PROJECT_ROOT)/examples/hello_window && dart analyze
	@cd $(PROJECT_ROOT)/examples/hello_window && \
		dart compile kernel --link-platform \
		--packages=.dart_tool/package_config.json \
		--depfile=$(BUILD_DIR)/test/hello_window.dill.d \
		-o $(BUILD_DIR)/test/hello_window.dill bin/main.dart

example-smoke: engine-check
	@cd $(PROJECT_ROOT)/examples/hello_window && dart pub get
	@cd $(PROJECT_ROOT)/examples/hello_window && \
		DART_ENGINE_ROOT="$(DART_ENGINE_ROOT)" \
		DART_ENGINE_LIBRARY="$(DART_ENGINE_LIBRARY)" \
		dart run dart_appkit:run bin/main.dart -- --auto-close-after=3

run-example: engine-check
	@cd $(PROJECT_ROOT)/examples/hello_window && dart pub get
	@cd $(PROJECT_ROOT)/examples/hello_window && \
		DART_ENGINE_ROOT="$(DART_ENGINE_ROOT)" \
		DART_ENGINE_LIBRARY="$(DART_ENGINE_LIBRARY)" \
		dart run dart_appkit:run bin/main.dart

ffi-smoke: bridge
	@cd $(PROJECT_ROOT)/packages/dart_appkit && \
		dart run test/ffi_bridge_smoke.dart $(BRIDGE_LIBRARY)

test: validate native-test runner-syntax runner-argument-test runner-shell-test message-pump-test dart-test example-test ffi-smoke

clean:
	@if [[ "$(BUILD_DIR)" != "$(PROJECT_ROOT)/build" ]]; then \
		echo "refusing to clean non-default BUILD_DIR: $(BUILD_DIR)" >&2; \
		exit 1; \
	fi
	@rm -rf $(PROJECT_ROOT)/build
