/// Runtime services supplied by a `dart_macos_runtime` macOS application host.
library;

export 'src/application_manifest.dart'
    show
        MacosApplicationManifest,
        MacosApplicationManifestException,
        MacosAppIntentsManifest,
        MacosApplicationServiceKind,
        MacosApplicationServiceManifest,
        MacosDiagnosticsManifest,
        MacosNativeAssetManifest,
        MacosNativeCapabilityManifest,
        MacosRunnerActivationPolicy,
        MacosRunnerMessagePumpManifest,
        MacosRunnerManifest,
        MacosScriptingDefinitionManifest;
export 'src/native_capability.dart'
    show MacosNativeCapability, MacosNativeCapabilityException;
export 'src/runtime.dart'
    show MacosRuntime, MacosRuntimeException, RuntimeDiagnosticPhase;
