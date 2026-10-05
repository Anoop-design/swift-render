# Native render setup

## Verified renderer baseline

The bundled starter depends on `https://github.com/Anoop-design/swift-render` at revision `a63f3d5f846d17b127faff803a7b9d5c368c16d0`. This is the upstream HEAD verified on 2026-10-06, whose CLI identifies as 0.8.1. Upstream had no matching 0.8.1 release tag; use the revision pin instead of `from: "0.8.1"`. Keep the existing renderer pin for revisions to an accepted film unless there is a specific need to upgrade it.

SwiftRender has a macOS 14+ SwiftPM library and executable. `RenderScene.body(at:duration:)` describes a view as a pure function of time. `Recorder.Config` controls size, integer FPS, codec, bitrate, scale, and post-processing. `Recorder.render(to:duration:audioURL:content:)` exports MP4, and `RenderFrame` applies the same render context to preview images. `Score`, `ScoreSynth`, `Timeline`, easing, and spring utilities can coordinate music and motion. Consult the checked-out source before using an API that is not shown by the starter; do not invent renderer commands.

## Initialize and prove the native path

```sh
python3 <skill-directory>/scripts/launch.py doctor
python3 <skill-directory>/scripts/launch.py init --output <film-directory>/NativeComposer
cd <film-directory>/NativeComposer
swift build
swift run launch-film frame --time 2 --output out/frame.png --width 540 --height 960 --duration 16 --fps 30
swift run launch-film contact --frames 12 --output out/contact.png --width 540 --height 960 --duration 16 --fps 30
swift run launch-film render --output out/preview.mp4 --width 540 --height 960 --duration 4 --fps 30
```

`init` requires a new output directory and only copies the bundled source starter. Use `NativeComposer` inside the film workspace, so earlier inventory/brief files do not cause an existing-directory failure. Dependency resolution/building happens explicitly afterward. First resolution needs access to the fork. Follow the host's normal build permissions; do not disable sandboxing globally or edit user security settings to make a render work.

The sample `AppContent.swift` is original generic demo content. Replace it with selected app views, original assets, and a film-only adapter. The starter is suitable for macOS-compatible SwiftUI; do not paste UIKit into it and expect the macOS compiler to accept it. Read [source-reuse.md](source-reuse.md) for alternate native routes.

The CLI accepts `render`, `frame`, and `contact`. Shared flags are `--width`, `--height`, `--duration`, `--fps`, and `--output`; `frame` adds `--time`, `contact` adds `--frames`, and `render` can receive an existing `--audio` file. Use even dimensions for H.264. Choose an integer frame count and derive duration from it. A silent sample export is not a finished soundtrack.

Example delivery sizes are 1080×1920 (9:16), 1920×1080 (16:9), and 1536×1152 (4:3). These are canvas dimensions, not instructions to stretch the app viewport. Recompose source content for each aspect.

## Integrating into the renderer repository

If working on SwiftRender itself rather than an independent film package, its existing CLI supports `new`, `check`, `contact`, `frame`, `preview`, `audio`, and `render`. Run `swift run swift-render --help` and command-specific help for exact options. The baseline supports explicit `--width`/`--height` for 4:3 even though its named `--aspect` presets only list 16:9, 9:16, and 1:1. A ranged preview render skips audio in that baseline; use a complete short scene when auditioning a transition.

The baseline includes prebuilt Metal shaders. Editing `.metal` files requires a compatible Metal toolchain or an app-specific runtime compilation path; a successful build using an old prebuilt metallib does not prove a new shader edit was used. Verify shader/resource bundles and compare a visible effect at two known times. SwiftUI effects may require native rendering paths that ImageRenderer does not support; prove the real effect before committing to the route.

Build temporary caches outside source assets. A macOS build produces `.build/`, `.swiftpm/`, and sometimes resolved dependency files; these must not enter the plugin package or become app inventory inputs.
