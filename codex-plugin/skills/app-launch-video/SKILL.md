---
name: app-launch-video
description: Create or revise native launch videos, teasers, and feature films from Swift, iOS, or macOS app repositories using SwiftRender. Use for app marketing films that reuse real SwiftUI/UIKit/AppKit components, Metal shaders, and brand assets; includes story, motion, music, source provenance, and multiple aspect ratios.
---

# App launch video

Turn the app's actual visual language into a film. Codex authors the story and app-specific adapters; SwiftRender renders deterministic native frames. The bundled starter proves that pipeline, but its demonstration card is not a substitute for the user's app.

## Start from the request and repository

For an existing film, inspect its current edit and change only what the user asked for. Reuse accepted direction and previously provided assets. For a new film, resolve the app root and output location, read its repository instructions and product docs, then identify a small set of components that prove the product's value. Ask for missing choices only when they materially affect the result; otherwise state reasonable assumptions and proceed. Keep the app checkout intact and put film adaptations in a separate directory unless app edits were requested.

Resolve this skill's directory from this `SKILL.md`; scripts and assets are relative to it, never to the user's current working directory. Choose a film workspace outside the app root for the brief, inventories, and exports. Run helpers with `python3`. They do not install dependencies, run the app, upload code, or render by themselves:

```sh
python3 <skill-directory>/scripts/launch.py doctor
python3 <skill-directory>/scripts/launch.py inspect --app <app-root> --output <film-directory>/app-inventory.json
```

The inventory is a heuristic navigation aid, not proof of platform compatibility or complete dependency closure. Read the relevant source, theme tokens, preview fixtures, onboarding, feature views, shaders, and asset catalog entries it identifies. Use a simulator for understanding when helpful; source-based films should render the components themselves. Do not use a person's physical device or private app data without an explicit request.

Reports are new files and must be outside the app root. On revision, reuse the existing report or select a new versioned report filename. Initialize native source in a **new subdirectory** of this film workspace; the inventory command may already have created the workspace itself.

## Match the app and establish a render route

Read [source-reuse.md](references/source-reuse.md) when selecting and adapting source. Map each featured component to its actual file and assets, its data inputs, and its render route:

- macOS-compatible SwiftUI/AppKit: compose directly in a separate SwiftPM film target.
- UIKit or iOS-only SwiftUI: create a Simulator or Catalyst render harness using the compatible SDK. The macOS SwiftRender package cannot import UIKit.
- Metal, RealityKit, or live native surfaces: use an explicit offscreen renderer at film time and composite the resulting frames; prove one representative frame before a full export.

Create an explicit list of reused files and freeze their hashes with the `snapshot` command described in that reference. Preserve logos, palettes, typefaces, meshes, textures, and shaders. Label any substituted component or unsupported effect instead of silently approximating it. Use tabular numerals and stable metric widths while retaining the app's letterforms.

## Direct a film, then implement it

Write a short `film-brief.md` in the film workspace: audience, one product promise, selected evidence moments, aspect ratios, length, visual approach, musical direction, and the reveal/CTA timing. Fit the story to the app; do not reuse a fixed fitness narrative, color, phone, or effect. Make realistic demo data and keep dates, distances, durations, counts, and other related values consistent.

Read [direction.md](references/direction.md) for layout, motion, and audio decisions. Give each shot a clear job: establish the promise, demonstrate it through native elements, then land the brand/CTA. Favor a few strong moments over a screen tour. For a small change, update the existing brief instead of requiring another planning round.

Read [rendering.md](references/rendering.md) for the verified SwiftRender revision, native starter, current APIs, and export procedure. A new film can start with:

```sh
python3 <skill-directory>/scripts/launch.py init --output <film-directory>/NativeComposer
```

Replace the starter's sample content with the selected source and presentation adapters. Keep animation a function of frame time: `t = frameIndex / fps`, including scroll, text, shaders, particles, and camera. Keep the soundtrack on the same edit clock. Write separate compositions for different aspect ratios while reusing their time model and original screen proportions.

## Preview and revise

Render a few key frames first, inspect them, then render a short motion preview with audio. Review the actual encoded output. Fix source fidelity, clipping, type hierarchy, empty holds, uneven reveals, transition speed, and musical discontinuities before the expensive full export. Do not describe audio as listened to unless you actually auditioned it; technical waveform checks do not establish taste.

For feedback, locate the cause: source adaptation, layout, timing, camera, or sound. If the visuals are accepted and only sound changes, preserve the encoded video and replace its audio; see [delivery.md](references/delivery.md). If an app file changes, reverify the selected source manifest and rebuild affected caches.

## Deliver

Use the focused verification procedure in [delivery.md](references/delivery.md). Deliver the playable film(s), a poster/contact sheet, and reproducible source with the brief, source mapping, version pin, and verification report. Report what was actually tested and any remaining platform or aesthetic limits. Keep previous accepted exports. Producing a film does not authorize posting it, uploading the app source, or publishing an upstream contribution.
