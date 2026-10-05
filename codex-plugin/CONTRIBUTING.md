# Contributing to the Codex plugin

Develop changes in this fork, [Anoop-design/swift-render](https://github.com/Anoop-design/swift-render). Open contribution pull requests here. A separate explicit decision is needed before proposing a change to another repository.

Keep the plugin portable: no developer home paths, private app source or assets, machine-specific caches, API tokens, compiled binaries, or recorded personal data. Generic fixtures should be original and small. Retain any required upstream attribution.

The portable manifest and compatibility manifest describe the same plugin. Keep their identity, version, description, and interface metadata synchronized. The local marketplace lives at the repository's `.agents/plugins/marketplace.json`; the package lives at `codex-plugin/`.

For helper changes, run the Python tests and package validation. For starter changes, initialize a fresh temporary film, compile it, and render/decode a short movie on macOS. Test failure cases such as unsupported inputs and existing output directories. Avoid making a passing metadata check stand in for actually rendering.

For workflow changes, test a realistic request with a small independent app fixture. Record what the agent selected, what it adapted, where it wrote files, and whether it disclosed unsupported render routes. A useful test includes iOS-only imports and a shader so the skill cannot succeed merely by drawing a generic SwiftUI card.

Keep native library changes separate from plugin packaging where practical. Do not change the original app to make a marketing export work. Put compatibility adapters in the film project, record transformations, and add a reusable library API only when several apps need the same capability.

Publishing a GitHub fork or a plugin ZIP does not publish to OpenAI's public plugin directory. Public directory submission requires its own publisher details, review, and approval flow. See the [official submission guide](https://developers.openai.com/plugins/deploy/submission).
