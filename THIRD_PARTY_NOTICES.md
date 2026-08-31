# Third-party notices

The source code authored for Dart AppKit Embedder is licensed under the MIT
License in [`LICENSE`](LICENSE). That license does not replace the licenses of
Dart or other third-party software used to build or run the project.

## Dart SDK and Dart Engine

The bootstrap scripts fetch the Dart SDK repository at the pinned revision
`60a57cd42d64dc03e9f07aa60a2e250755c1ef28`. The checkout and all generated
build products live below ignored `.dart_tool/` or `build/` directories and
are not part of this repository.

The Dart SDK repository is licensed under the BSD 3-Clause License. A copy of
the license for the pinned revision is kept at
[`licenses/DART_SDK_LICENSE`](licenses/DART_SDK_LICENSE). The launcher also
copies the exact checkout's `LICENSE` file into a generated application bundle
as `Contents/Resources/DART_SDK_LICENSE.txt` whenever it packages
`libdart_engine_jit_shared.dylib`.

- Dart SDK license:
  <https://github.com/dart-lang/sdk/blob/60a57cd42d64dc03e9f07aa60a2e250755c1ef28/LICENSE>
- Dart SDK patent grant:
  <https://github.com/dart-lang/sdk/blob/60a57cd42d64dc03e9f07aa60a2e250755c1ef28/PATENT_GRANT>

## Binary distribution

The Dart SDK checkout contains separately licensed third-party components.
Before distributing a generated dylib or `.app`, inventory the components
included by the exact pinned build and reproduce every applicable license and
notice from the checkout's `third_party` sources and build metadata. The
automatically copied Dart SDK license is a baseline safeguard; it is not a
complete third-party notice bundle for redistribution.

This file records the project's engineering treatment of licenses and is not
legal advice.
