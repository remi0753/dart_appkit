# Dynamic text presentation and split divider color

- Status: complete
- Date: 2026-09-16

## Purpose and scope

Allow a caller to update an existing TextEditor's base font, padding and colors,
and explicitly color a TwoPaneSplitView divider without replacing native objects.
This supports applications with sibling themed text surfaces. Application themes
and caller-specific navigation, observation and workflows stay outside AppKit.

## Contract and acceptance

- Optional Dart binding interfaces and optional FFI symbols preserve older fakes
  and bridges; missing native support returns the existing unsupported status.
- Existing C ABI layouts and event protocols do not change.
- Text, selection, editable state, marked text, scroll origin, line highlight and
  explicit foreground/underline runs survive a presentation update.
- Parameter validation precedes mutation; native calls require the AppKit main
  thread and correctly typed generation-safe handles.
- No explicit divider color retains the platform default. Color reset is allowed;
  geometry, drag, zoom, minimum extents and ownership stay unchanged.
- Focused fake API and real native bridge tests, format/analysis, package tests,
  and consumer Developer JIT/Release AOT acceptance must pass.

## Existing work and risks

The initial dirty tree contains only BUILDING_DART_ENGINE.md and the bootstrap
and build Engine scripts. They are unrelated and must not be touched or staged.
Replacing text resources would lose focus/scroll; a bounded in-place update is
preferred. Explicit attributed colors must not be silently overwritten by base
color changes. Shared defaults for other applications must remain unchanged.

## Record

- The existing configured text-view decoder and sRGB validation can be reused.
- The existing TextEditor has no live presentation API; TwoPaneSplitView has no
  caller-selected divider color. Both additions are generic, optional mechanisms.
- Added optional in-place presentation and divider appearance APIs with bounded
  OpenType font descriptor coordinates (16 maximum). Explicit attributed colors
  carry a private storage marker and are reapplied after base color changes.
- Initial Dart format and package analysis passed. Focused fake API and real
  bridge tests now cover no-op updates, failure atomicity, stable document,
  selection, scroll, line highlight, style runs and divider reset/validation.
- Real native bridge tests passed. The first Dart test run exposed the explicit
  public export list missing TextEditorFontVariation; added that export and rerun.
- Native and full Dart API/launcher tests then passed. Added genuine scrolled
  viewport and marked-text preservation, transparency opacity, off-thread and
  stale-handle checks. No editor selection assignment is made if it is unchanged.
- Full native/Dart/FFI/legacy smoke checks passed. The first full gate detected
  caller-specific vocabulary in this task note; changed the note to describe
  only generic library boundaries without changing the ownership audit.
- The depot_tools formatter wrapper required a Chromium checkout and changed
  nothing. Use the Xcode toolchain's actual formatter for touched native ranges.
- Final review classified excess variation count as the existing limit-exceeded
  status in both FFI and C rather than an internal error. Added native count
  rejection coverage; public Dart validation still throws before native mutation.
- Final `make test` passed after all code changes: ownership/scaffold audit,
  native bridge/runner/runtime contracts, runtime assembly/publication tests,
  Dart API/launcher/example analysis and compilation, FFI and legacy smoke.
- Explicit Dart format check passed for eight changed API/test files with zero
  changes. Touched native ranges were formatted with the Xcode formatter;
  `git diff --check` passed. No unrelated Engine changes are included.
- Consumer native acceptance passed in Developer JIT (11128 ms) and Release AOT
  (10387 ms) with custom named font, colors and background opacity. The final
  count-error classification is separately covered by the full native gate.
- Subjective visual/accessibility quality remains a caller-side manual check.
