/// Test-only hooks for exercising the raw native-event boundary.
library;

export 'src/api.dart'
    show
        attachApplicationForTesting,
        injectRawAppKitEventForTesting,
        nativeWindowHandleForTesting;
