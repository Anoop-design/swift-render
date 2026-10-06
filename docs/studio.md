# SwiftRender Studio for macOS

SwiftRender Studio is a native Mac workspace for preparing launch films from an Apple app's source. Select an app repository, inspect its native components and resources, and create a separate film project with a brief that Codex can use. The app bundles the same source-inventory, provenance, and SwiftRender starter workflow as the Codex plugin.

The Studio interface is local. It does not upload app source, require an API key, or modify the selected app to make a marketing export work. App-specific adaptation remains a Codex task: an arbitrary UIKit, Metal, or RealityKit app cannot be turned into a faithful macOS render by copying its target wholesale.

## Build the app

Use macOS 14 or newer with a compatible Xcode/Swift toolchain and Python 3.9 or newer. From the repository root:

```sh
python3 tools/studio/build.py
open 'out/SwiftRender Studio.app'
```

The script runs `swift build --product swift-render-studio --configuration release`, locates the resulting executable using SwiftPM, and creates a standard `.app` bundle. The app's executable is `Contents/MacOS/SwiftRenderStudio`; its self-contained workflow is under `Contents/Resources/Workflow`. The application can locate those resources through `Bundle.main.resourceURL` and does not depend on the repository's working directory to find them.

The builder signs the bundle ad hoc when `/usr/bin/codesign` is available and checks that signature before installing the bundle at the destination. This is a local development build, **not a notarized distribution**. A downloadable release needs its own Developer ID signing, notarization, and distribution process.

For a debug build that opens immediately:

```sh
python3 tools/studio/build.py --debug --output 'out/SwiftRender Studio Debug.app' --open
```

Rebuilding an existing generated app requires an explicit flag:

```sh
python3 tools/studio/build.py --overwrite
```

The builder stages the complete app beside the destination, signs it, and then swaps it into place. It replaces only an existing bundle carrying its own build marker and matching bundle identifier. It refuses an unrelated directory, app, or symlink, even with `--overwrite`. If the final replacement fails, it restores the previous bundle.

Before signing, the builder removes only `com.apple.ResourceFork` and `com.apple.FinderInfo` metadata from its newly copied app. It preserves the source files' attributes and does not broadly strip extended attributes. It verifies the signature again at the final destination before discarding the previous bundle. Some iCloud/File Provider folders can recreate signing-prohibited metadata; if signing still fails there, choose a local destination outside that provider with `--output`, for example:

```sh
python3 tools/studio/build.py --output "$HOME/Applications/SwiftRender Studio.app"
```

For a disposable local test, `/private/tmp/SwiftRender Studio.app` is another suitable destination. The builder does not relocate a user's chosen output silently.

If another process already compiled the executable, reuse that build:

```sh
python3 tools/studio/build.py --skip-build --binary '<built-executable-path>' --output 'out/SwiftRender Studio.app'
```

Use `--debug` when that binary came from a debug build. Without `--binary`, `--skip-build` asks SwiftPM for the binary directory for the selected configuration but does not compile. Avoid simultaneous Swift builds in the same checkout. Run `python3 tools/studio/build.py --help` for all options.

## Prepare a source-based film

1. Use **Choose App Folder** to select the original Swift/iOS/macOS codebase.
2. Enter the film's title, product promise, aspect ratio, duration, and frame rate, then prepare a new project outside that app folder.
3. Use **Copy Codex Brief** and paste it into a Codex chat with SwiftRender enabled. The brief identifies the source app and film workspace and asks Codex to adapt the real components.
4. After those adaptations are ready, use **Render Preview**. Inspect the film and soundtrack, revise as needed in Codex, then use **Export Film**. Select an audio file when the film has an accompanying score.

Choose the original app repository and a separate film destination. The workflow inventories relevant source and assets without running the app or contacting its services. Its inventory is a navigation aid; Codex still needs to read the selected components, theme values, shader inputs, and product documentation.

Use the prepared brief with Codex to choose a small set of real product moments. Codex can then map those elements to their original files, freeze selected source hashes, and author film-only adapters. SwiftUI/AppKit components compatible with macOS can render directly. UIKit and iOS-only views need a Simulator or Catalyst harness. Live Metal and RealityKit surfaces may need explicit offscreen rendering before their frames are composed by SwiftRender.

Prepare representative frames and a short motion/audio preview before a full export. Keep original typography and assets, give numeric metrics tabular digits and stable widths, and put animation and music on one deterministic edit clock. Multiple aspect ratios require separate compositions that preserve the source view's proportions.

## Run the sample pipeline

Use **Try Sample** to create a separate demonstration project, then **Render Preview** to build and watch it inside the app. This path needs no source app or Codex adaptation step.

The bundled native starter supplies an immediately usable rendering demonstration once its Swift package dependencies have resolved. It is generic sample content, not a reconstruction of the selected app. A new starter project can produce a short preview with:

```sh
cd '<prepared-film-directory>/NativeComposer'
swift run launch-film render --output out/sample.mp4 --width 540 --height 960 --duration 4 --fps 30
```

The first run needs network access to fetch the pinned SwiftRender dependency and may take time to compile. Studio keeps package configuration, security state, and compiler caches inside the film workspace’s `.studio-cache` folder; the composer’s build products remain in `NativeComposer/.build`. Successful sample rendering proves the basic pipeline; it does not prove that the app's native effects are correctly adapted. Replace the demonstration content with the selected real components, or connect verified native frame sequences, before describing an export as that app's launch film.

After adaptation, `launch-film frame`, `launch-film contact`, and `launch-film render` provide preview and export operations. Use explicit duration, size, and FPS from the brief. An optional `--audio` path attaches an existing audio file to a render. Review the actual encoded video and audition the music; successful compilation and waveform checks do not establish artistic quality.

Source projects, generated films, and user-supplied artwork retain their own licenses. This app includes no private app code or assets. Preparing or rendering a film does not publish it to social media or submit an app to a store.
