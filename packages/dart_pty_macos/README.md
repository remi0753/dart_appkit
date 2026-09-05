# dart_pty_macos

`dart_pty_macos` is an AppKit-independent PTY/process capability for Dart macOS
applications. Native code owns only `forkpty`, the audited child `execve` path,
master-FD readiness, bounded byte queues, resize/signals, close escalation, and
child reaping. Dart owns session policy and terminal semantics.

The v2 `dpty_*` C ABI provides:

- copied argv, environment, working directory, and initial size before fork;
- an isolated C child branch using only audited async-signal-safe operations;
- one kqueue reactor thread per session;
- output chunks no larger than 64 KiB retained until ordered ACK;
- configurable read high/low watermarks and bounded write admission;
- foreground process-group signals, `TIOCSWINSZ`, SIGHUP/grace/SIGKILL close;
- idempotent, nonblocking immediate force close before or during graceful close;
- exactly one started/error and exit lifecycle, `waitpid` reaping, and
  generation-checked session handles.

The Dart facade uses a listener-style native callback so reactor threads enqueue
events without entering the UI isolate synchronously. `FakePtyBackend` provides
the same public process surface for deterministic product tests.

`PtyProcess.close()` starts the graceful SIGHUP/deadline policy.
`PtyProcess.forceClose()` is a separate lifecycle operation that remains valid
after graceful close starts and asks the reactor to send SIGKILL immediately;
neither call waits for exit or `waitpid` on the caller thread. Consumers still
await `exit` when they need proof that reaping completed.

`MacosPtyBackend.shared` uses the official native-assets mapping in ordinary
Dart tools. A custom application host can instead call
`MacosPtyBackend.open(absoluteBundleLibraryPath)` using the path supplied by its
bundle runtime; the same facade then retains and resolves that staged image.

The package contains no AppKit dependency, Objective-C source, VT parser,
renderer, pane model, or application policy.
