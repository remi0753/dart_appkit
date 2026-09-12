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
DART_ENGINE_AOT_LIBRARY ?= $(DART_ENGINE_ROOT)/xcodebuild/Product$(DART_ENGINE_RELEASE_ARCH)/libdart_engine_aot_shared.dylib

CLANG := $(shell xcrun --find clang)
CLANGXX := $(shell xcrun --find clang++)
SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)

WARNINGS := -Wall -Wextra -Wpedantic -Werror
COMMON_FLAGS := $(WARNINGS) -fvisibility=hidden -isysroot $(SDKROOT) \
	-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)
OBJCXX_FLAGS := $(COMMON_FLAGS) -std=c++20 -fobjc-arc -fblocks
APPKIT_LIBS := -framework AppKit -framework CoreFoundation \
	-framework UserNotifications -framework Carbon

BRIDGE_HEADERS := \
	$(PROJECT_ROOT)/native/bridge/include/dart_appkit.h \
	$(PROJECT_ROOT)/native/bridge/include/dart_appkit_custom_view.h \
	$(PROJECT_ROOT)/native/bridge/include/dart_appkit_native_extension.h \
	$(PROJECT_ROOT)/native/bridge/src/AppKitObjects.h \
	$(PROJECT_ROOT)/native/bridge/src/BridgeInternal.h \
	$(PROJECT_ROOT)/native/bridge/src/CustomViewRegistry.h \
	$(PROJECT_ROOT)/native/bridge/src/ObjectRegistry.h
BRIDGE_SOURCES := \
	$(PROJECT_ROOT)/native/bridge/src/AppKitBridge.mm \
	$(PROJECT_ROOT)/native/bridge/src/CustomViewRegistry.mm \
	$(PROJECT_ROOT)/native/bridge/src/EventSink.mm \
	$(PROJECT_ROOT)/native/bridge/src/ObjectRegistry.mm \
	$(PROJECT_ROOT)/native/bridge/src/TextView.mm
RUNNER_SOURCES := \
	$(PROJECT_ROOT)/native/runner/main.mm \
	$(PROJECT_ROOT)/native/runner/AppDelegate.mm \
	$(PROJECT_ROOT)/native/runner/DartEventEncoder.cc \
	$(PROJECT_ROOT)/native/runner/DartHost.mm \
	$(PROJECT_ROOT)/native/runner/DartMessagePump.mm \
	$(PROJECT_ROOT)/native/runner/RunnerArguments.cc \
	$(PROJECT_ROOT)/native/runner/RunnerConfiguration.mm
RUNNER_HEADERS := \
	$(PROJECT_ROOT)/native/runner/AppDelegate.h \
	$(PROJECT_ROOT)/native/runner/DartEventEncoder.h \
	$(PROJECT_ROOT)/native/runner/DartHost.h \
	$(PROJECT_ROOT)/native/runner/DartMessagePump.h \
	$(PROJECT_ROOT)/native/runner/RunnerArguments.h \
	$(PROJECT_ROOT)/native/runner/RunnerConfiguration.h
NATIVE_TEST_SOURCES := \
	$(PROJECT_ROOT)/native/bridge/test/BridgeTests.mm
MESSAGE_PUMP_TEST_SOURCES := \
	$(PROJECT_ROOT)/native/runner/DartMessagePump.mm \
	$(PROJECT_ROOT)/native/runner/test/DartMessagePumpTests.mm
EVENT_ENCODER_TEST_SOURCES := \
	$(PROJECT_ROOT)/native/runner/DartEventEncoder.cc \
	$(PROJECT_ROOT)/native/runner/test/DartEventEncoderTests.cc
RUNNER_ARGUMENT_TEST_SOURCES := \
	$(PROJECT_ROOT)/native/runner/RunnerArguments.cc \
	$(PROJECT_ROOT)/native/runner/test/RunnerArgumentsTests.cc
RUNNER_CONFIGURATION_TEST_SOURCES := \
	$(PROJECT_ROOT)/native/runner/RunnerConfiguration.mm \
	$(PROJECT_ROOT)/native/runner/test/RunnerConfigurationTests.mm

BRIDGE_LIBRARY := $(NATIVE_BUILD_DIR)/libdart_appkit_bridge.dylib
LEGACY_EVENT_BRIDGE_FIXTURE := \
	$(NATIVE_BUILD_DIR)/libdart_appkit_legacy_event_fixture.dylib
NATIVE_TEST_BINARY := $(NATIVE_BUILD_DIR)/bridge_tests
MESSAGE_PUMP_TEST_BINARY := $(NATIVE_BUILD_DIR)/message_pump_tests
EVENT_ENCODER_TEST_BINARY := $(NATIVE_BUILD_DIR)/event_encoder_tests
RUNNER_ARGUMENT_TEST_BINARY := $(NATIVE_BUILD_DIR)/runner_argument_tests
RUNNER_CONFIGURATION_TEST_BINARY := \
	$(NATIVE_BUILD_DIR)/runner_configuration_tests
RUNNER_SHELL_TEST_BINARY := $(NATIVE_BUILD_DIR)/runner_shell_test
RUNNER_BINARY := $(NATIVE_BUILD_DIR)/dart_appkit_runner

RUNTIME_HEADERS := \
	$(PROJECT_ROOT)/native/runtime/include/dart_macos_runtime.h \
	$(PROJECT_ROOT)/native/runtime/ReleaseAotHost.h \
	$(PROJECT_ROOT)/native/runtime/RuntimeDiagnostics.h \
	$(PROJECT_ROOT)/native/runtime/RuntimeLifecycle.h
RUNTIME_COMMON_SOURCES := \
	$(PROJECT_ROOT)/native/runtime/RuntimeDiagnostics.mm \
	$(PROJECT_ROOT)/native/runtime/RuntimeLifecycle.mm
RUNTIME_JIT_SOURCES := \
	$(PROJECT_ROOT)/native/runtime/DeveloperJitRunner.mm \
	$(PROJECT_ROOT)/native/runner/AppDelegate.mm \
	$(PROJECT_ROOT)/native/runner/DartEventEncoder.cc \
	$(PROJECT_ROOT)/native/runner/DartHost.mm \
	$(PROJECT_ROOT)/native/runner/DartMessagePump.mm \
	$(PROJECT_ROOT)/native/runner/RunnerArguments.cc \
	$(PROJECT_ROOT)/native/runner/RunnerConfiguration.mm \
	$(RUNTIME_COMMON_SOURCES)
RUNTIME_AOT_SOURCES := \
	$(PROJECT_ROOT)/native/runtime/ReleaseAotRunner.mm \
	$(PROJECT_ROOT)/native/runtime/ReleaseAotHost.mm \
	$(PROJECT_ROOT)/native/runner/DartEventEncoder.cc \
	$(PROJECT_ROOT)/native/runner/DartMessagePump.mm \
	$(PROJECT_ROOT)/native/runner/RunnerConfiguration.mm \
	$(RUNTIME_COMMON_SOURCES)
RUNTIME_JIT_BINARY := $(NATIVE_BUILD_DIR)/dart_macos_runtime_developer
RUNTIME_AOT_BINARY := $(NATIVE_BUILD_DIR)/dart_macos_runtime_release
RUNTIME_LIFECYCLE_TEST_BINARY := \
	$(NATIVE_BUILD_DIR)/runtime_lifecycle_tests
RUNTIME_DIAGNOSTICS_TEST_BINARY := \
	$(NATIVE_BUILD_DIR)/runtime_diagnostics_tests
EXAMPLE_VIEW_PLUGIN_LIBRARY := \
	$(NATIVE_BUILD_DIR)/libdart_appkit_example_view.dylib
NATIVE_CAPABILITY_LOADER_TEST_BINARY := \
	$(NATIVE_BUILD_DIR)/native_capability_loader_tests
TERMINAL_RENDERER_PLUGIN_LIBRARY := \
	$(NATIVE_BUILD_DIR)/libdart_terminal_renderer_macos.dylib
TERMINAL_RENDERER_TEST_BINARY := \
	$(NATIVE_BUILD_DIR)/terminal_renderer_capability_tests
TERMINAL_RENDERER_SHADER_SOURCE := \
	$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/TerminalShaders.metal
TERMINAL_RENDERER_SHADER_LIBRARY := \
	$(NATIVE_BUILD_DIR)/TerminalShaders.metallib
DPTY_CHILD_OBJECT := $(NATIVE_BUILD_DIR)/dpty_exec_child.o
DPTY_SPAWN_OBJECT := $(NATIVE_BUILD_DIR)/dpty_spawn.o
DPTY_SESSION_OBJECT := $(NATIVE_BUILD_DIR)/dpty_session.o
DPTY_LIBRARY := $(NATIVE_BUILD_DIR)/libdart_pty_macos.dylib
DPTY_TEST_BINARY := $(NATIVE_BUILD_DIR)/dart_pty_macos_tests

PUBLIC_HOST_PROBE_BUILD_DIR := $(BUILD_DIR)/public-dart-api-host
PUBLIC_HOST_PROBE_SOURCE := \
	$(PROJECT_ROOT)/native/runner/PublicDartApiHostProbe.cc
PUBLIC_HOST_PROBE_DART_SOURCE := \
	$(PROJECT_ROOT)/tool/public_dart_api_host_probe.dart
PUBLIC_HOST_PROBE_RUNNER := \
	$(PROJECT_ROOT)/tool/public_dart_api_host_probe_runner.dart
PUBLIC_HOST_RELEASE_OUT := $(DART_ENGINE_ROOT)/xcodebuild/ReleaseARM64
PUBLIC_HOST_PRODUCT_OUT := $(DART_ENGINE_ROOT)/xcodebuild/ProductARM64
PUBLIC_HOST_NINJA := $(DART_ENGINE_ROOT)/buildtools/ninja/ninja
PUBLIC_HOST_JIT_LIBRARY := \
	$(PUBLIC_HOST_RELEASE_OUT)/libdart_engine_jit_shared.dylib
PUBLIC_HOST_AOT_LIBRARY := \
	$(PUBLIC_HOST_PRODUCT_OUT)/libdart_engine_aot_shared.dylib
PUBLIC_HOST_JIT_COMPILER := \
	$(PUBLIC_HOST_RELEASE_OUT)/bootstrap_gen_kernel.exe
PUBLIC_HOST_AOT_COMPILER := \
	$(PUBLIC_HOST_PRODUCT_OUT)/bootstrap_gen_kernel.exe
PUBLIC_HOST_AOT_SNAPSHOTTER := $(PUBLIC_HOST_PRODUCT_OUT)/gen_snapshot
PUBLIC_HOST_JIT_PLATFORM := \
	$(PUBLIC_HOST_RELEASE_OUT)/clang_arm64_shared/vm_platform.dill
PUBLIC_HOST_AOT_PLATFORM := \
	$(PUBLIC_HOST_PRODUCT_OUT)/clang_arm64_shared/vm_platform.dill
PUBLIC_HOST_JIT_KERNEL := \
	$(PUBLIC_HOST_PROBE_BUILD_DIR)/application.jit.dill
PUBLIC_HOST_AOT_KERNEL := \
	$(PUBLIC_HOST_PROBE_BUILD_DIR)/application.aot.dill
PUBLIC_HOST_AOT_SNAPSHOT := \
	$(PUBLIC_HOST_PROBE_BUILD_DIR)/application.aot.snapshot
PUBLIC_HOST_JIT_BINARY := \
	$(PUBLIC_HOST_PROBE_BUILD_DIR)/public_host_jit
PUBLIC_HOST_AOT_BINARY := \
	$(PUBLIC_HOST_PROBE_BUILD_DIR)/public_host_aot

.PHONY: help validate contract-check engine engine-check bridge native-test runner runner-syntax runner-argument-test runner-configuration-test runner-shell-test message-pump-test event-encoder-test runtime-contract-check runtime-lifecycle-test runtime-diagnostics-test native-capability-loader-test terminal-renderer-contract-check terminal-renderer-native-test terminal-renderer-dart-test dpty-contract-check dpty-child-audit dpty-native-test dpty-dart-test runtime-jit-runner runtime-aot-runner runtime-dart-test example-view-dart-test dart-test example-test example-smoke run-example ffi-smoke public-dart-api-host-engine public-dart-api-host-probe test clean

help:
	@echo "Dart AppKit Embedder targets:"
	@echo "  make validate       Validate layout, scripts, and C/C++ ABI headers"
	@echo "  make engine         Fetch, build, and validate the pinned Dart Engine"
	@echo "  make engine-check   Validate DART_SDK/DART_ENGINE_* inputs"
	@echo "  make bridge         Build the standalone AppKit bridge dylib"
	@echo "  make native-test    Build and run native bridge contract tests"
	@echo "  make runner-syntax  Compile-check Runner against Dart 3.13.2 declarations"
	@echo "  make runner-argument-test  Test Runner CLI parsing and exit contract"
	@echo "  make runner-configuration-test  Test Runner bundle policy parsing"
	@echo "  make runner-shell-test  Link Runner shell and execute pre-VM failures"
	@echo "  make message-pump-test  Test bounded main-run-loop Dart scheduling"
	@echo "  make event-encoder-test  Test versioned native event serialization"
	@echo "  make runner         Build the embedded Dart/AppKit Runner"
	@echo "  make runtime-jit-runner  Build the generic Developer JIT host"
	@echo "  make runtime-aot-runner  Build the generic Release AOT host"
	@echo "  make runtime-dart-test   Analyze and test dart_macos_runtime"
	@echo "  make native-capability-loader-test  Test dynamic view capability"
	@echo "  make terminal-renderer-native-test  Test terminal renderer capability"
	@echo "  make terminal-renderer-dart-test  Test renderer build hook asset"
	@echo "  make dpty-native-test  Test bounded macOS PTY capability"
	@echo "  make dpty-dart-test  Test PTY Dart facade and build hook asset"
	@echo "  make example-view-dart-test  Test the dependency build hook asset"
	@echo "  make dart-test      Analyze and test the Dart package"
	@echo "  make example-test   Analyze and compile the hello-window Kernel"
	@echo "  make example-smoke  Launch hello-window and close it automatically"
	@echo "  make run-example    Launch hello-window until its window is closed"
	@echo "  make public-dart-api-host-probe  Test the stock public VM host boundary"
	@echo "  make test           Run all locally available checks"

validate: contract-check
	@$(PROJECT_ROOT)/scripts/validate_scaffold.sh

contract-check:
	@mkdir -p $(NATIVE_BUILD_DIR)
	@$(CLANG) $(COMMON_FLAGS) -std=c11 -I$(PROJECT_ROOT)/native/bridge/include \
		-fsyntax-only $(PROJECT_ROOT)/native/bridge/test/header_compile.c
	@$(CLANGXX) $(COMMON_FLAGS) -std=c++20 -I$(PROJECT_ROOT)/native/bridge/include \
		-fsyntax-only $(PROJECT_ROOT)/native/bridge/test/header_compile.cc
	@$(MAKE) runtime-contract-check

runtime-contract-check:
	@mkdir -p $(NATIVE_BUILD_DIR)
	@$(CLANG) $(COMMON_FLAGS) -std=c11 \
		-I$(PROJECT_ROOT)/native/runtime/include -fsyntax-only \
		$(PROJECT_ROOT)/native/runtime/test/header_compile.c
	@$(CLANGXX) $(COMMON_FLAGS) -std=c++20 \
		-I$(PROJECT_ROOT)/native/runtime/include -fsyntax-only \
		$(PROJECT_ROOT)/native/runtime/test/header_compile.cc

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

$(LEGACY_EVENT_BRIDGE_FIXTURE): \
		$(PROJECT_ROOT)/native/bridge/include/dart_appkit.h \
		$(PROJECT_ROOT)/native/bridge/test/LegacyEventBridgeFixture.c
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANG) $(COMMON_FLAGS) -std=c11 -dynamiclib \
		-I$(PROJECT_ROOT)/native/bridge/include \
		$(PROJECT_ROOT)/native/bridge/test/LegacyEventBridgeFixture.c -o $@

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

$(RUNNER_CONFIGURATION_TEST_BINARY): $(RUNNER_CONFIGURATION_TEST_SOURCES) \
		$(PROJECT_ROOT)/native/runner/RunnerConfiguration.h
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-I$(PROJECT_ROOT)/native/runner \
		$(RUNNER_CONFIGURATION_TEST_SOURCES) $(APPKIT_LIBS) -o $@

runner-configuration-test: $(RUNNER_CONFIGURATION_TEST_BINARY)
	@$(RUNNER_CONFIGURATION_TEST_BINARY)

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

$(EVENT_ENCODER_TEST_BINARY): $(BRIDGE_HEADERS) $(RUNNER_HEADERS) \
		$(EVENT_ENCODER_TEST_SOURCES)
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(COMMON_FLAGS) -std=c++20 \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/native/bridge/src \
		-I$(PROJECT_ROOT)/native/runner \
		-iquote$(shell realpath $(shell command -v dart) | xargs dirname | xargs dirname) \
		$(EVENT_ENCODER_TEST_SOURCES) -o $@

event-encoder-test: $(EVENT_ENCODER_TEST_BINARY)
	@$(EVENT_ENCODER_TEST_BINARY)

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

$(RUNTIME_LIFECYCLE_TEST_BINARY): $(RUNTIME_HEADERS) \
		$(PROJECT_ROOT)/native/runtime/RuntimeLifecycle.mm \
		$(PROJECT_ROOT)/native/runtime/RuntimeDiagnostics.mm \
		$(PROJECT_ROOT)/native/runtime/test/RuntimeLifecycleTests.mm
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-I$(PROJECT_ROOT)/native/runtime/include \
		-I$(PROJECT_ROOT)/native/runtime \
		$(PROJECT_ROOT)/native/runtime/RuntimeLifecycle.mm \
		$(PROJECT_ROOT)/native/runtime/RuntimeDiagnostics.mm \
		$(PROJECT_ROOT)/native/runtime/test/RuntimeLifecycleTests.mm \
		$(APPKIT_LIBS) -o $@

runtime-lifecycle-test: $(RUNTIME_LIFECYCLE_TEST_BINARY)
	@$(RUNTIME_LIFECYCLE_TEST_BINARY)

$(RUNTIME_DIAGNOSTICS_TEST_BINARY): $(RUNTIME_HEADERS) \
		$(PROJECT_ROOT)/native/runtime/RuntimeDiagnostics.mm \
		$(PROJECT_ROOT)/native/runtime/test/RuntimeDiagnosticsTests.mm
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-I$(PROJECT_ROOT)/native/runtime/include \
		-I$(PROJECT_ROOT)/native/runtime \
		$(PROJECT_ROOT)/native/runtime/RuntimeDiagnostics.mm \
		$(PROJECT_ROOT)/native/runtime/test/RuntimeDiagnosticsTests.mm \
		-framework Foundation -o $@

runtime-diagnostics-test: $(RUNTIME_DIAGNOSTICS_TEST_BINARY)
	@$(RUNTIME_DIAGNOSTICS_TEST_BINARY)

$(EXAMPLE_VIEW_PLUGIN_LIBRARY): \
		$(PROJECT_ROOT)/packages/dart_appkit_example_view/native/ExampleViewPlugin.h \
		$(PROJECT_ROOT)/packages/dart_appkit_example_view/native/ExampleViewPlugin.m \
		$(PROJECT_ROOT)/native/bridge/include/dart_appkit.h \
		$(PROJECT_ROOT)/native/bridge/include/dart_appkit_native_extension.h
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANG) $(COMMON_FLAGS) -fobjc-arc -dynamiclib \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_appkit_example_view/native \
		$(PROJECT_ROOT)/packages/dart_appkit_example_view/native/ExampleViewPlugin.m \
		-framework AppKit \
		-Wl,-install_name,@rpath/libdart_appkit_example_view.dylib -o $@

$(NATIVE_CAPABILITY_LOADER_TEST_BINARY): $(BRIDGE_HEADERS) $(BRIDGE_SOURCES) \
		$(PROJECT_ROOT)/native/runtime/test/NativeCapabilityLoaderTests.mm \
		$(PROJECT_ROOT)/packages/dart_appkit_example_view/native/ExampleViewPlugin.h
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/native/bridge/src \
		-I$(PROJECT_ROOT)/packages/dart_appkit_example_view/native \
		$(BRIDGE_SOURCES) \
		$(PROJECT_ROOT)/native/runtime/test/NativeCapabilityLoaderTests.mm \
		$(APPKIT_LIBS) -o $@

native-capability-loader-test: $(EXAMPLE_VIEW_PLUGIN_LIBRARY) \
		$(NATIVE_CAPABILITY_LOADER_TEST_BINARY)
	@$(NATIVE_CAPABILITY_LOADER_TEST_BINARY) $(EXAMPLE_VIEW_PLUGIN_LIBRARY)

terminal-renderer-contract-check:
	@$(CLANG) $(COMMON_FLAGS) -std=c11 \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native \
		-fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/test/header_compile.c
	@$(CLANGXX) $(COMMON_FLAGS) -std=c++20 \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native \
		-fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/test/header_compile.cc

$(TERMINAL_RENDERER_SHADER_LIBRARY): $(TERMINAL_RENDERER_SHADER_SOURCE)
	@mkdir -p $(NATIVE_BUILD_DIR)
	xcrun -sdk macosx metal -target air64-apple-macos14.0 $< -o $@

$(TERMINAL_RENDERER_PLUGIN_LIBRARY): $(TERMINAL_RENDERER_SHADER_LIBRARY) \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.h \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.m \
		$(PROJECT_ROOT)/native/bridge/include/dart_appkit.h \
		$(PROJECT_ROOT)/native/bridge/include/dart_appkit_native_extension.h
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANG) $(COMMON_FLAGS) -fobjc-arc -fblocks -dynamiclib \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.m \
		-framework AppKit -framework CoreText -framework Metal -framework MetalKit \
		-Wl,-sectcreate,__DATA,__dtrlib,$(TERMINAL_RENDERER_SHADER_LIBRARY) \
		-Wl,-install_name,@rpath/libdart_terminal_renderer_macos.dylib -o $@

$(TERMINAL_RENDERER_TEST_BINARY): $(BRIDGE_HEADERS) $(BRIDGE_SOURCES) \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.h \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/test/TerminalRendererCapabilityTests.mm
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/native/bridge/src \
		-I$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native \
		$(BRIDGE_SOURCES) \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/test/TerminalRendererCapabilityTests.mm \
		$(APPKIT_LIBS) -framework Metal -framework MetalKit -o $@

terminal-renderer-native-test: terminal-renderer-contract-check \
		$(TERMINAL_RENDERER_PLUGIN_LIBRARY) $(TERMINAL_RENDERER_TEST_BINARY)
	@$(TERMINAL_RENDERER_TEST_BINARY) $(TERMINAL_RENDERER_PLUGIN_LIBRARY)

dpty-contract-check:
	@$(CLANG) $(COMMON_FLAGS) -std=c11 \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native -fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/test/header_compile.c
	@$(CLANGXX) $(COMMON_FLAGS) -std=c++20 \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native -fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/test/header_compile.cc

$(DPTY_CHILD_OBJECT): \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtyExecChild.c \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtySpawnInternal.h
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANG) $(COMMON_FLAGS) -std=c11 -c \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native $< -o $@

$(DPTY_SPAWN_OBJECT): \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtySpawn.c \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtySpawnInternal.h \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/dart_pty_macos.h
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANG) $(COMMON_FLAGS) -std=c11 -c \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native $< -o $@

$(DPTY_SESSION_OBJECT): \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtySession.cc \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtySpawnInternal.h \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/dart_pty_macos.h
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(COMMON_FLAGS) -std=c++20 -pthread -c \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native $< -o $@

dpty-child-audit: $(DPTY_CHILD_OBJECT)
	@dart $(PROJECT_ROOT)/packages/dart_pty_macos/tool/audit_pty_child.dart $<

$(DPTY_LIBRARY): $(DPTY_CHILD_OBJECT) $(DPTY_SPAWN_OBJECT) \
		$(DPTY_SESSION_OBJECT)
	$(CLANGXX) $(COMMON_FLAGS) -std=c++20 -pthread -dynamiclib \
		$(DPTY_SESSION_OBJECT) $(DPTY_SPAWN_OBJECT) $(DPTY_CHILD_OBJECT) \
		-Wl,-install_name,@rpath/libdart_pty_macos.dylib -o $@

$(DPTY_TEST_BINARY): \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/test/PtyCapabilityTests.cc \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/dart_pty_macos.h
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(COMMON_FLAGS) -std=c++20 -pthread \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native $< -o $@

dpty-native-test: dpty-contract-check dpty-child-audit $(DPTY_LIBRARY) \
		$(DPTY_TEST_BINARY)
	@$(DPTY_TEST_BINARY) $(DPTY_LIBRARY)

$(RUNTIME_JIT_BINARY): $(BRIDGE_HEADERS) $(BRIDGE_SOURCES) $(RUNNER_HEADERS) \
		$(RUNTIME_HEADERS) $(RUNTIME_JIT_SOURCES) $(DART_ENGINE_LIBRARY)
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-Wno-gnu-anonymous-struct -Wno-nested-anon-types \
		-DDA_DART_ENGINE_REVISION=\"$(shell git -C $(DART_ENGINE_ROOT) rev-parse HEAD)\" \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/native/bridge/src \
		-I$(PROJECT_ROOT)/native/runner \
		-I$(PROJECT_ROOT)/native/runtime/include \
		-I$(PROJECT_ROOT)/native/runtime \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(BRIDGE_SOURCES) $(RUNTIME_JIT_SOURCES) \
		$(DART_ENGINE_LIBRARY) $(APPKIT_LIBS) \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic -o $@

runtime-jit-runner: engine-check $(RUNTIME_JIT_BINARY)

$(RUNTIME_AOT_BINARY): $(BRIDGE_HEADERS) $(BRIDGE_SOURCES) \
		$(RUNNER_HEADERS) $(RUNTIME_HEADERS) $(RUNTIME_AOT_SOURCES) \
		$(DART_ENGINE_AOT_LIBRARY)
	@mkdir -p $(NATIVE_BUILD_DIR)
	$(CLANGXX) $(OBJCXX_FLAGS) \
		-Wno-gnu-anonymous-struct -Wno-nested-anon-types \
		-DDMR_DART_SDK_VERSION=\"$(shell cat $(DART_SDK)/version)\" \
		-I$(PROJECT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/native/bridge/src \
		-I$(PROJECT_ROOT)/native/runner \
		-I$(PROJECT_ROOT)/native/runtime/include \
		-I$(PROJECT_ROOT)/native/runtime \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(BRIDGE_SOURCES) $(RUNTIME_AOT_SOURCES) \
		$(DART_ENGINE_AOT_LIBRARY) $(APPKIT_LIBS) \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic -o $@

runtime-aot-runner: engine-check $(RUNTIME_AOT_BINARY)

runtime-dart-test:
	@cd $(PROJECT_ROOT)/packages/dart_macos_runtime && dart pub get
	@cd $(PROJECT_ROOT)/packages/dart_macos_runtime && dart analyze
	@cd $(PROJECT_ROOT)/packages/dart_macos_runtime && \
		dart run test/run_tests.dart

example-view-dart-test:
	@cd $(PROJECT_ROOT)/packages/dart_appkit_example_view && dart pub get
	@cd $(PROJECT_ROOT)/packages/dart_appkit_example_view && dart analyze
	@cd $(PROJECT_ROOT)/packages/dart_appkit_example_view && \
		dart run test/native_asset_test.dart

terminal-renderer-dart-test:
	@cd $(PROJECT_ROOT)/packages/dart_terminal_renderer_macos && dart pub get
	@cd $(PROJECT_ROOT)/packages/dart_terminal_renderer_macos && dart analyze
	@cd $(PROJECT_ROOT)/packages/dart_terminal_renderer_macos && \
		dart run test/run_tests.dart

dpty-dart-test:
	@cd $(PROJECT_ROOT)/packages/dart_pty_macos && dart pub get
	@cd $(PROJECT_ROOT)/packages/dart_pty_macos && dart analyze
	@cd $(PROJECT_ROOT)/packages/dart_pty_macos && \
		dart run test/run_tests.dart

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

ffi-smoke: bridge $(LEGACY_EVENT_BRIDGE_FIXTURE)
	@cd $(PROJECT_ROOT)/packages/dart_appkit && \
		dart run test/ffi_bridge_smoke.dart $(BRIDGE_LIBRARY)
	@cd $(PROJECT_ROOT)/packages/dart_appkit && \
		dart run test/legacy_event_bridge_smoke.dart \
			$(LEGACY_EVENT_BRIDGE_FIXTURE)

public-dart-api-host-engine: engine-check
	@test "$(HOST_ARCH)" = arm64 || \
		(echo "public Dart API host probe currently targets M1/arm64" >&2; exit 1)
	@$(DART_ENGINE_ROOT)/tools/gn.py --mode=release --arch=arm64
	@$(PUBLIC_HOST_NINJA) -C $(PUBLIC_HOST_RELEASE_OUT) \
		dart_engine_jit_shared bootstrap_gen_kernel.exe \
		clang_arm64_shared/vm_platform.dill
	@$(DART_ENGINE_ROOT)/tools/gn.py --mode=product --arch=arm64
	@$(PUBLIC_HOST_NINJA) -C $(PUBLIC_HOST_PRODUCT_OUT) \
		dart_engine_aot_shared gen_snapshot bootstrap_gen_kernel.exe \
		clang_arm64_shared/vm_platform.dill

$(PUBLIC_HOST_JIT_KERNEL): $(PUBLIC_HOST_PROBE_DART_SOURCE) | \
		public-dart-api-host-engine
	@mkdir -p $(PUBLIC_HOST_PROBE_BUILD_DIR)
	@$(PUBLIC_HOST_JIT_COMPILER) \
		--platform=$(PUBLIC_HOST_JIT_PLATFORM) \
		--no-aot --link-platform --no-embed-sources \
		--output=$@ \
		-Ddart.vm.product=false -Ddart.vm.asan=false \
		-Ddart.vm.msan=false -Ddart.vm.tsan=false \
		$(PUBLIC_HOST_PROBE_DART_SOURCE)

$(PUBLIC_HOST_AOT_KERNEL): $(PUBLIC_HOST_PROBE_DART_SOURCE) | \
		public-dart-api-host-engine
	@mkdir -p $(PUBLIC_HOST_PROBE_BUILD_DIR)
	@$(PUBLIC_HOST_AOT_COMPILER) \
		--platform=$(PUBLIC_HOST_AOT_PLATFORM) \
		--aot --link-platform --no-embed-sources --target-os=macos \
		--invocation-modes=compile --verbosity=error \
		--output=$@ \
		-Ddart.vm.product=true -Ddart.vm.asan=false \
		-Ddart.vm.msan=false -Ddart.vm.tsan=false \
		$(PUBLIC_HOST_PROBE_DART_SOURCE)

$(PUBLIC_HOST_AOT_SNAPSHOT): $(PUBLIC_HOST_AOT_KERNEL)
	@$(PUBLIC_HOST_AOT_SNAPSHOTTER) \
		--snapshot-kind=app-aot-macho-dylib --macho=$@ $<

$(PUBLIC_HOST_JIT_BINARY): $(PUBLIC_HOST_PROBE_SOURCE) | \
		public-dart-api-host-engine
	@mkdir -p $(PUBLIC_HOST_PROBE_BUILD_DIR)
	$(CLANGXX) $(COMMON_FLAGS) -std=c++20 -arch arm64 \
		-I$(DART_ENGINE_ROOT)/runtime \
		$(PUBLIC_HOST_PROBE_SOURCE) $(PUBLIC_HOST_JIT_LIBRARY) \
		-Wl,-rpath,$(PUBLIC_HOST_RELEASE_OUT) -o $@

$(PUBLIC_HOST_AOT_BINARY): $(PUBLIC_HOST_PROBE_SOURCE) | \
		public-dart-api-host-engine
	@mkdir -p $(PUBLIC_HOST_PROBE_BUILD_DIR)
	$(CLANGXX) $(COMMON_FLAGS) -std=c++20 -arch arm64 \
		-I$(DART_ENGINE_ROOT)/runtime \
		$(PUBLIC_HOST_PROBE_SOURCE) $(PUBLIC_HOST_AOT_LIBRARY) \
		-Wl,-rpath,$(PUBLIC_HOST_PRODUCT_OUT) -o $@

public-dart-api-host-probe: $(PUBLIC_HOST_JIT_BINARY) \
		$(PUBLIC_HOST_JIT_KERNEL) $(PUBLIC_HOST_AOT_BINARY) \
		$(PUBLIC_HOST_AOT_SNAPSHOT)
	@dart $(PUBLIC_HOST_PROBE_RUNNER) \
		--engine-root=$(DART_ENGINE_ROOT) \
		--host-source=$(PUBLIC_HOST_PROBE_SOURCE) \
		--jit-host=$(PUBLIC_HOST_JIT_BINARY) \
		--jit-library=$(PUBLIC_HOST_JIT_LIBRARY) \
		--jit-application=$(PUBLIC_HOST_JIT_KERNEL) \
		--jit-platform=$(PUBLIC_HOST_JIT_PLATFORM) \
		--aot-host=$(PUBLIC_HOST_AOT_BINARY) \
		--aot-library=$(PUBLIC_HOST_AOT_LIBRARY) \
		--aot-application=$(PUBLIC_HOST_AOT_SNAPSHOT)
	@$(MAKE) engine-check

test: validate native-test runner-syntax runner-argument-test runner-configuration-test runner-shell-test message-pump-test event-encoder-test runtime-lifecycle-test runtime-diagnostics-test native-capability-loader-test terminal-renderer-native-test dpty-native-test runtime-dart-test example-view-dart-test terminal-renderer-dart-test dpty-dart-test dart-test example-test ffi-smoke

clean:
	@if [[ "$(BUILD_DIR)" != "$(PROJECT_ROOT)/build" ]]; then \
		echo "refusing to clean non-default BUILD_DIR: $(BUILD_DIR)" >&2; \
		exit 1; \
	fi
	@rm -rf $(PROJECT_ROOT)/build
