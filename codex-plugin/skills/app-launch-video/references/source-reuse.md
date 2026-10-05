# Reusing app code faithfully

## Discover the product

Read product docs and the app entry points before naming features in marketing copy. Follow the featured view into its style definitions, model inputs, image names, custom fonts, and native renderer. Previews and tests often supply useful fixture models. Avoid loading unrelated services just to draw a component.

The inventory helper reads a bounded set of relevant source files, identifies likely views/frameworks/time dependencies, and lists asset paths. It excludes common generated/dependency folders and does not follow symlinks. Inspect its coverage/exclusion fields; use targeted searches for omitted areas. It is not a Swift parser or a credential scanner. Do not upload its output or the app's private sources as part of publishing the generic plugin.

## Choose the smallest faithful adapter

Prefer, in order: import an existing shared UI module; compile selected unmodified source with fixture inputs; copy original source into a film-only target and add a small explicit adapter. If a compatibility edit is required, retain the original and record the transformation. Avoid rewriting a card from a screenshot when its actual view is available.

Keep a source mapping for each on-screen element:

| Field | Meaning |
|---|---|
| Element | Feature/card/shader/logo visible in the film |
| Original | Relative source and resource paths |
| Adapter | Film-only wrapper or compatibility transformation |
| Route | SwiftUI, AppKit, Catalyst, Simulator harness, offscreen Metal/RealityKit |
| Inputs | Fixture model, theme, locale, screen bounds, film time |
| Status | Actual source / adapted source / disclosed substitute |

UIKit, platform-specific modifiers, bundle lookups, live shader layers, and RealityKit surfaces may not render through a macOS SwiftUI ImageRenderer. Compile a representative component before adapting the entire app. Offscreen native frame sequences are valid source rendering; a simulator screen recording is a different capture method and should be chosen only when it fits the user's request.

## Make time and data explicit

Move wall-clock and live-service inputs into film-only presentation values: time, progress, scroll position, fixture model, and camera pose. Do not remove production animation code from the original app. `Timer`, `TimelineView`, `.task`, `Date.now`, random seeds, and implicit `withAnimation` depend on runtime history; offline frame rendering needs deterministic equivalents. Fix the seed and advance a simulation consistently when the original effect is stateful. Seek/reset or cache simulations so contact frames match the movie.

Use demo data with internal consistency. Do not open HealthKit, account databases, Keychain, personal photos, or a live backend merely to populate a launch film. This avoids accidentally marketing private data and makes the film reproducible.

Typography belongs to the app's design. Verify bundled fonts and their licensing, preserve the correct rounded or standard face, apply `.monospacedDigit()`/tabular-number features to metrics, and reserve stable widths for changing values. Preserve `tnum` if font assets are subsetted. Match the app's corner radii, card spacing, line weight, textures, and native lighting before adding presentation flourishes.

## Freeze selected originals

Create a JSON array containing only the relative source/resource files actually selected, for example:

```json
["Sources/Feature/MilestoneCard.swift", "Resources/Assets.xcassets/Mark.imageset/mark.png"]
```

```sh
python3 <skill-directory>/scripts/launch.py snapshot --app <app-root> --selection <selection.json> --output <film-directory>/source-manifest.json
python3 <skill-directory>/scripts/launch.py verify --app <app-root> --manifest <film-directory>/source-manifest.json
```

This checks original files, not the fidelity of film adaptations. Record hashes of the generated/copied files and their transformations in the film project as well. Recheck before delivery and invalidate any native frame cache when source, resources, adapter, renderer revision, output geometry, or timing changes. Include font, texture, seed, mesh, HDR, shader, and asset catalog metadata dependencies, not only `.swift` files.
