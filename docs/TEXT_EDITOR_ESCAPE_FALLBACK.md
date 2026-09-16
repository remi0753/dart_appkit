# Opt-in silent unhandled Escape

Status: complete (2026-09-17, macOS arm64)

## Purpose, scope and acceptance

Allow a caller owning Escape as a Dart modal command to suppress the native
unhandled `cancelOperation:` responder fallback. Dual window event routing
posts asynchronously and still sends the original key through AppKit; changing
routing after the Dart event arrives cannot undo an earlier fallback beep.
Default native behavior must remain unchanged and ordinary editing, input
context, marked text, completion, document/styles and selection remain owned
by NSTextView. Do not globally swallow keys, mute sound, or alter routing.

The wrapper implements only the final unhandled responder command, after the
inner text view's ordinary handling. Add an optional bool API with cached
success-only state, same-value no-op, unsupported legacy status 8, typed handle
and main-thread checks. Native tests must count the ultimate window fallback
under actual native sendEvent, without making the test play a sound. Test
default, enabled, reset, non-Escape editing, exactly-once Dart delivery, invalid
input/handle/thread and immutable text/selection/marked-state behavior.

## Dependencies, alternatives and verification

Read README, ROADMAP and current text editor API/native tests. Preserve the
three existing engine-building docs/scripts changes. Reject Dart-only routing
for editable input, a global no-op cancel handler, and an inner NSTextView
override: the wrapper fallback preserves native processing first. Verify C/C++
headers, native contract, Dart API fake/legacy FFI, formatter/analyzer and full
`make test`, review diff, then commit this capability independently.

## Findings

- A standalone NSTextView inside NSWindow receives Esc as `cancelOperation:`
  and forwards it to NSWindow when there is no cancellation to perform.
  A counted window cancel override observed one fallback, unchanged draft,
  exit 0. This observer stops before the final beep and is safe to reuse in
  native regression tests.
- Native responder fallback in the outer editor wrapper is narrower than
  intercepting keyDown or cancelOperation in the inner text view: it leaves
  native input-context/completion handling ahead of the fallback.
- First patch had a mismatched implementation-line context and made no changes;
  read the exact declaration with ivars and anchor the method at its synthesis.
- First native build failed because the new test omitted the create function's
  font-family pointer/length parameters. Use the actual four-argument signature
  with null/0 for the default system font; no production behavior was weakened.
- The first native run exposed that NSView's superclass does not implement
  cancelOperation: (unrecognized selector). Preserve default behavior by
  forwarding with nextResponder.tryToPerform; only invoke noResponderFor when
  the chain has no handler. Never call a nonexistent super cancel method.
- Refined the regression observer to replace/restore an existing method with
  method_setImplementation rather than permanently adding a method to a class.
  An attempted NSResponder.noResponderFor observer failed all three expected
  default/reset counts (actual 0): AppKit's final NSWindow cancel handler runs
  before that generic no-responder path. Observe the existing NSWindow
  cancelOperation implementation instead; keep default 1 / enabled 1 / reset 2
  count expectations unchanged, and restore the original method in finally.

## Verification and handoff

- Native actual sendEvent regression: default Esc reaches the window fallback
  once; enabling the policy and pressing Esc twice does not increase the count;
  Dart still gets all three keyDown events exactly once. Reset restores the
  fallback. Text/selection are unchanged by Esc; ordinary typing adds one
  character; policy updates retain marked text/range/selection. Invalid bool,
  wrong handle kind, wrong thread and released handle are rejected.
- Dart API tests cover default false, same-value no-op, success publication,
  failure preserving the cached value, reset without document/style changes,
  and disposed setter. Legacy FFI lacks the optional symbol and returns 8.
- Focused native/Dart/launcher tests passed. Full `make test` passed after the
  corrected observer, including repository/contract/header validation, bridge,
  Runner/scheduler/event encoder/runtime, API/example and real/legacy FFI.
  Formatting: all 26 package Dart files unchanged; changed native ranges were
  clang-formatted, followed by another passing native test.
- Final diff check passed. Existing engine-building docs/scripts are excluded.
  No native event version, ABI struct, routing mode or default is changed.
- Consumers must explicitly set `suppressesUnhandledEscape = true` on each
  editor they create/recreate and still handle Esc via Dart window events.
  This is not a system-wide sound setting or a general keyboard interception.
