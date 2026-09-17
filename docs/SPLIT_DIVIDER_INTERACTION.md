# Optional two-pane divider interaction

- Status: complete
- Date: 2026-09-17

## Purpose, scope, and acceptance

Allow callers to disable mouse dragging of a TwoPaneSplitView divider without
changing its color, children, fraction, programmatic position, or resize layout.
Default remains draggable. This is a generic AppKit mechanism, not a product
keyboard/layout policy. No event or configuration struct version changes.

Add an optional bindings interface/C symbol. Older bridges explicitly report
unsupported when changing the property; failed calls retain the cached value.
Main-thread, typed/generation-checked handles and strict boolean validation
remain required. Disabled dividers skip native tracking and resize cursor rects;
their effective hit rect is empty. Cover native/API/fake tests and full gate.

## Investigation and decisions

- The existing split helper has minimum extents and color/position observation
  but no interaction opt-out. Equal minimum/maximum constraints would still
  advertise draggable cursors and enter mouse tracking, so use explicit policy.
- Add dividerDraggable (default true) with no resource recreation. Programmatic
  setPosition/equalize/zoom and other callers' split behavior remain intact.
- Existing user edits in docs/BUILDING_DART_ENGINE.md and two Engine scripts
  are outside scope and must be preserved. No additional AGENTS.md was found.
- Focused native-test/dart-test passed, including native warnings-as-errors and
  Dart analysis/API/launcher tests. Default, opt-out/restore, unchanged geometry,
  failed-call retention, no mouse tracking, programmatic layout, wrong/stale
  handles, wrong thread, and strict boolean validation are covered.
- First full gate stopped at the generic ownership audit because this memo
  named a consumer-specific category. Reworded only that prose to generic
  product policy; no audit allowlist or assertion was weakened. Full gate is
  rerun on the corrected documentation.
- Corrected full gate passed: generic ownership/scaffold audit, warnings-as-errors
  bridge and Runner builds/tests, runtime/package analysis and builders, API and
  launcher tests, hello-window build, and current/legacy FFI smoke. No API/ABI
  version or event encoding changed; missing optional symbols remain loadable.
- Reviewed the minimal native/Dart diff with git diff --check; existing user
  Engine-script/documentation edits are unchanged. No remaining work for this
  optional mechanism; caller keyboard/layout policy is outside the dependency.
