# SwiftRender Codex plugin 0.1.0 validation

Checked 2026-10-06 with Codex CLI 0.160.0, Xcode 27.0, Swift 6.4, and Python 3.9. The renderer baseline is commit `a63f3d5f846d17b127faff803a7b9d5c368c16d0`.

## Automated checks

- Eight helper tests pass: discovery, imports/hints, exclusions, scan limits, paths containing spaces, traversal/symlink rejection, source-change detection, report protection, and new-project initialization.
- Thirteen packaging tests pass: manifest and reference integrity, path containment, exclusion of caches/private output, deterministic ZIP generation, input stability, and preservation of prior output on failure.
- Skill Creator's frontmatter validator passes. Its PyYAML dependency was installed in an isolated temporary directory for validation, not added as a plugin runtime dependency.
- Codex's actual plugin parser discovered the repository marketplace. Local installation reports `swift-render@swift-render-local`, version `0.1.0`, installed and enabled. All 19 installed runtime files match the source package hashes.

## Native smoke render

Initialized an isolated copy of the bundled NativeStarter. For the local smoke build only, resolved its SwiftRender dependency from the local checkout at the pinned renderer revision; the packaged dependency remains the public fork URL plus exact revision. Tested Swift sources match the packaged files.

- Exported a silent portrait movie at 320×568, 12 fps, 2 seconds.
- Exported a 4:3 movie with a generated test WAV at 640×480, 12 fps, 2 seconds.
- Both movies decoded all 24 frames with continuous timestamps. Requested audio was present in the second movie.
- Inspected standalone frame images and an eight-frame contact sheet. They are generic pipeline fixtures, not evidence of automatic arbitrary-app adaptation.
- Invalid duration, odd dimensions, out-of-range frame time, empty contact sheet, unknown option, and accidental overwrite were rejected.
- The standalone AVFoundation verifier passed both movies and rejected an incorrect frame count, missing required audio, and changed reference picture. It also confirmed unchanged compressed video data/timing/transform across an existing audio-only revision.

The native decoder/encoder required normal host permission to use macOS media services. Compilation under the newer SDK reports deprecations for APIs intentionally available on macOS 14; no compile errors occurred. The verifier checks audio-track presence, not audio quality. No musical audition is claimed by these tests.

## Independent workflow test

Used a small original iOS fixture with product docs, a SwiftUI card importing UIKit, and a blue Metal shimmer. Another agent followed the skill to prepare a 12-second teaser workspace, without being given the intended rendering route. It identified the iOS dependency, selected an iOS/Catalyst capture route with a separate macOS composer, wrote the product-specific brief and source mapping, froze the source, and copied originals without changes. All three input files remained unchanged. It correctly disclosed that native-host construction, shader frame proof, and export were still pending at that requested stopping point.

The test found an ordering defect: inventory creation could occupy the directory that initialization required to be new. The skill now puts native source in a new `NativeComposer` subdirectory beneath the report workspace. Initialization in that layout passed.

## Scope

These checks verify the helpers, package, installation, native starter, media verifier, and setup workflow. They do not establish compatibility with every iOS/macOS codebase, prove an arbitrary app's Metal effect can use ImageRenderer, or guarantee subjective video/music quality. The CI workflow repeats Python package checks and a macOS native export; its remote result must be assessed separately from these local results.

## Useful follow-on renderer work

The baseline Recorder can skip a missing pixel buffer, ignore an append failure, or lose an audio-mux failure. The starter's decoded-output validation detects incomplete exports, but propagating those errors in the renderer would make failures clearer. Separating demo scenes/resources from the library would also reduce consumer setup. Implement and review those changes in this fork with focused regression coverage; they are not included in this plugin release.
