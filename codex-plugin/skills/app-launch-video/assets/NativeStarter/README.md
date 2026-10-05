# Native launch-film starter

A small, functioning SwiftPM host for deterministic SwiftUI frames, contact sheets, and MP4 export. Requires macOS 14+ and a compatible Xcode toolchain. It pins SwiftRender to a verified Git revision because its `0.8.1` CLI version currently has no corresponding release tag.

Copy this directory into a separate film workspace before editing. `AppContent.swift` is an original generic fixture, not an adapter for any existing app. Replace it with selected real app components, explicit fixture models, and their original resources. Record source paths, hashes, and adaptations in the film's provenance manifest. UIKit-only and RealityKit components need a platform-specific host; this macOS target does not make arbitrary iOS source portable automatically.

```sh
swift run launch-film frame --time 2 --output out/frame.png
swift run launch-film contact --frames 12 --output out/contact.png
swift run launch-film render --output out/portrait.mp4 --width 1080 --height 1920 --duration 16 --fps 30
swift run launch-film render --output out/landscape.mp4 --width 1536 --height 1152 --duration 16 --fps 30 --audio music.wav
```

`--audio` accepts an existing soundtrack with an audio track at least as long as the film. The starter does not compose or loop music. Without this option, output is intentionally silent. Keep visual cues and music arrangement on a shared timeline when adapting the starter.

Existing outputs are preserved unless `--overwrite` is passed. The renderer decodes every MP4 frame after export and checks timing, count, dimensions, duration, and presence of requested audio. Inspect the contact sheet and motion preview yourself: successful decoding does not establish visual or musical quality.

Use `--help` for options. Dimensions must be even, and duration × fps must be a whole number. `FilmScene.swift` demonstrates layout changes between portrait and wider canvases, with post-effects disabled so the sample's background stays black. The source uses explicit time, no timers or wall-clock animation, and tabular numerals for metrics and time labels.
