# Two-pane divider repaint coverage

- Status: complete
- Started: 2026-09-17

## Purpose, scope, and dependencies

Ensure programmatic fraction/equalize/zoom and resize layout invalidates the
native split's divider paint, including its former location under nonopaque
children. Keep geometry/minima, mouse interaction, colors, and native ownership
unchanged. No application-specific color, keyboard or redraw timer is added.
Depend on DaSplitView's existing synchronous main-thread layout and native tests.
No new public API, event record or version change is needed.

## Acceptance and verification

Confirm the old implementation fails a redraw coverage/retained bitmap test,
then cover both axes, repeated movement, zoom/unzoom, intermediate/zero/opaque
child background alpha, 1x/2x rendering and unchanged-layout avoidance. Use explicit
sRGB RGBA pixels and preserve existing split tests. Run native and full generic
gates, review/commit only the scoped files. Existing Engine documentation/scripts
edits remain untouched. A fresh full capture alone cannot prove dirty repaint.

## Investigation log

- daApplyLayout sets child frames directly but never marks the parent divider
  paint dirty. Appearance changes independently set needsDisplay; unchanged
  appearance does not. Test old/new area invalidation before deciding the fix.
- Use a split probe to record public display requests and retained bitmap redraw,
  rather than bypassing native drawing with a synthetic divider implementation.
- Before the fix, native-test failed six expectations across both axes: parent
  needsDisplay stayed false and recorded invalidation covered neither the old
  nor new divider. The public invalidation probe confirms missing parent paint
  requests, not merely a screenshot/color interpretation.
- Invalidate parent paint only when child frames or hidden state actually change.
  Cover zoom and ordinary fraction/equalize/resize in the shared layout path.
  No-op reconciliation should not force redraw. Full bounds are bounded by the
  view and ensure formerly exposed pixels beneath nonopaque children are cleared.
- First retained-pixel attempt used detached views: display requests were recorded,
  but public needsDisplay stayed false and native display emitted no divider ink.
  Attach each fixture to a real shown 201x201 content window, as existing bitmap
  tests do. Keep strict pixel/flag assertions, own capture lifecycle and cleanup.
- Current AppKit offscreen hierarchy display omits NSSplitView divider ink;
  CA layer rendering did not solve this and was removed. The retained fixture
  calls the public native drawDividerInRect painter for the current child
  geometry after background/hierarchy display, clipped to requested dirty area.
  It retains pixels between moves, asserts exact white line count/current
  position, child background alpha/channel order, and no divider during zoom.
  It does not draw a synthetic replacement divider. CGContext state must be
  saved/restored around hierarchy display, which otherwise retains a clip.
- Correct the flipped view-to-Y-up bitmap position conversion; the initial
  full gate failed 36 test location assertions without it. No production
  geometry or pixel count/location expectation was weakened.
- Removing only the own 14-line fix reproduced 234 native failures: missing
  requested dirty area/current ink and retained divider pixels during zoom.
  Restored the fix immediately. Earlier focused bitmap/coverage tests passed;
  final expanded native tests also passed in the full gate.
- Both axes, eight repeated position changes per alpha/scale, zero/0.4/1 alpha,
  1x/2x native ink, both zoom targets/unzoom, equalize, outer resize and no-op
  fraction/resize are covered. Existing nested geometry, mouse opt-out and
  resource/thread/lifecycle tests remain intact.
- Verification: CI=true DART_SUPPRESS_ANALYTICS=true make test passed, including
  generic repository/scaffold audit, warning-as-error native tests, runner,
  runtime, Dart API static analysis/tests, examples and FFI smoke. Changed
  Objective-C test ranges were clang-formatted; git diff --check passed.
  Existing Engine documentation and two scripts are excluded from staging.
- No new public API or event version, product ownership, runtime policy or
  global input hook; no remaining blocker in this scoped repaint fix.
