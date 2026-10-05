# SwiftRender for Codex

An open-source Codex plugin for making launch videos from the actual code and assets in a Swift, iOS, or macOS app.

The plugin guides Codex through understanding the product, selecting native components, adapting them to film time, directing the story and soundtrack, and exporting a verified video. It includes executable source-inventory and provenance tools and a small native SwiftRender starter. It is a local, skills-based plugin: rendering uses your Mac, Apple frameworks, and SwiftRender. There is no hosted render service, separate API key, or upload step.

This plugin is developed in [Anoop's fork of SwiftRender](https://github.com/Anoop-design/swift-render), based on [skyblanket/swift-render](https://github.com/skyblanket/swift-render). It is not an official OpenAI or Apple plugin.

## Install in Codex

Clone this fork, then register its local marketplace:

```sh
git clone https://github.com/Anoop-design/swift-render.git
cd swift-render
codex plugin marketplace add .
codex plugin list --available --marketplace swift-render-local
codex plugin add swift-render@swift-render-local
```

The last two commands are supported by the tested Codex CLI 0.160.0. If your version does not expose them, open the desktop app's Plugins directory, select **SwiftRender Local**, and install **SwiftRender**. Restart/refresh the desktop app if the local source is not shown, then begin a new chat so the installed skill is loaded. Local installation copies the plugin into Codex's cache; changing source files does not hot-reload an already running chat.

The marketplace path is relative to the repository root. `codex-plugin/` is intentionally separate from `Plugins/`, which contains SwiftPM build plugins. Do not rename the latter.

The package uses the current portable root `plugin.json` format and supplies the supported `.codex-plugin/plugin.json` compatibility manifest with matching metadata. It has no MCP server or lifecycle hook. See the official [plugin packaging guide](https://developers.openai.com/plugins/build/plugins) for the format and [Codex plugin documentation](https://learn.chatgpt.com/docs/plugins) for supported clients.

## Use it with an app

Open a chat in the app repository and select SwiftRender, or invoke its **App Launch Video** skill. Example requests:

> Make a 15-second vertical launch teaser from this app's real SwiftUI views and Metal assets. Understand the product from its docs and source, use demo data, and render the components themselves. Give me a preview before the final export.

> Adapt this macOS app into a 20-second feature film. Use its actual window layout, typography, and animations. Export 16:9 and 4:3 compositions.

> Keep the accepted visuals. Make the music continue into the logo reveal, with a short anticipation dip and a satisfying landing. Export a new version without re-encoding the video.

Codex follows the same workflow for either a new film or a focused revision:

1. Inspect product docs, views, theme tokens, shaders, resources, and build requirements.
2. Map selected on-screen components back to their originals and record source hashes.
3. Build a separate film target or native capture harness with deterministic time and demo inputs.
4. Author the story, motion, aspect-specific layouts, and musical arc.
5. Inspect key frames and a motion/audio preview, then export and verify the result.

## Requirements and honest limits

- Python 3.9+ runs the bundled local helpers using only the standard library.
- Rendering needs a Mac and compatible Apple development tools. The SwiftRender library targets macOS 14+; the selected app may require a newer SDK or OS.
- The native starter supports macOS-compatible SwiftUI. UIKit and iOS-only views need a Simulator/Catalyst harness authored for that app. Metal, RealityKit, and live native surfaces may need offscreen rendering. These routes are documented, not universal prebuilt adapters.
- The plugin helps Codex author and iterate on films; it cannot automatically compile every arbitrary app target or guarantee a finished artistic result from one prompt.
- The starter's generic demonstration is a pipeline check. Replace it with real app components before calling the result an app launch video.
- Source hashing proves inputs have not changed; it does not prove a copied view looks correct. Preview inspection and audio audition remain separate checks.

The starter pins the verified SwiftRender commit `a63f3d5f846d17b127faff803a7b9d5c368c16d0` in this fork. Upstream calls that revision 0.8.1 but did not have a matching release tag when checked on 2026-10-06; a revision pin avoids an unresolvable version requirement.

## Development

From the fork root:

```sh
python3 -m unittest discover -s codex-plugin/tests -v
python3 -m unittest discover -s tools/plugin -p 'test_*.py' -v
python3 tools/plugin/validate.py codex-plugin
python3 tools/plugin/package.py codex-plugin --output out/swift-render-plugin.zip
```

The helper and starter usage live in [the skill](skills/app-launch-video/SKILL.md). Keep plugin-specific tests in this package and reusable renderer changes in the appropriate SwiftRender targets. See [CONTRIBUTING.md](CONTRIBUTING.md) for the validation and contribution boundaries.

## License and privacy

This plugin is MIT-licensed; SwiftRender retains its upstream MIT attribution. User app code, fonts, artwork, store badges, third-party audio, and rendered films keep their own licenses. No private app resources are bundled with this plugin. The local helpers do not send telemetry or upload files. The agent runs within the permissions of its host; using the plugin is not a claim that the entire host conversation is offline.
