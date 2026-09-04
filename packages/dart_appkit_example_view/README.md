# dart_appkit_example_view

This integration fixture is a complete dependency-owned native AppKit
capability. Its Dart 3.13 build hook compiles the Objective-C view into a code
asset. `dart_macos_runtime` stages and retains that image; the Dart facade
explicitly initializes it through the versioned AppKit service table and then
creates the registered view through ordinary `dart_appkit` ownership.

Neither an application nor a generic host compiles `ExampleViewPlugin.m`.
