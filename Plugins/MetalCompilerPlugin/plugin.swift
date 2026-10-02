import Foundation
import PackagePlugin

/// Compiles Shaders/*.metal into default.metallib at build time.
///
/// Recent Xcodes ship the Metal compiler as a separate download. When it is
/// missing, the build falls back to the checked-in `Shaders/prebuilt.metallib`
/// (copied with its original mtime, so the CLI's stale-shader check still
/// warns if any .metal source is newer) instead of failing the whole build.
@main
struct MetalCompilerPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let shaderDir = target.directory.appending("Shaders")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: shaderDir.string) else { return [] }
        let metalFiles = entries.filter { $0.hasSuffix(".metal") }.sorted()
            .map { shaderDir.appending($0) }
        guard !metalFiles.isEmpty else { return [] }

        let prebuilt = shaderDir.appending("prebuilt.metallib")
        let hasPrebuilt = fm.fileExists(atPath: prebuilt.string)
        let out = context.pluginWorkDirectory.appending("default.metallib")
        // the plugin sandbox only permits writes inside pluginWorkDirectory —
        // metal's clang module cache must live there too or cold builds fail
        let moduleCache = context.pluginWorkDirectory.appending("ModuleCache")
        let log = context.pluginWorkDirectory.appending("metal.log")

        let script = """
        out="$1"; prebuilt="$2"; cache="$3"; log="$4"; shift 4
        if /usr/bin/xcrun -sdk macosx metal -fmodules-cache-path="$cache" "$@" -o "$out" 2>"$log"; then
          exit 0
        fi
        if [ -f "$prebuilt" ]; then
          echo "warning: Metal compiler unavailable — using Shaders/prebuilt.metallib. Shader edits will NOT take effect until you run: xcodebuild -downloadComponent MetalToolchain" >&2
          /bin/cp -p "$prebuilt" "$out"
          exit 0
        fi
        cat "$log" >&2
        echo "error: Metal compile failed and no Shaders/prebuilt.metallib exists. Try: xcodebuild -downloadComponent MetalToolchain" >&2
        exit 1
        """
        return [.buildCommand(
            displayName: "Compiling \(metalFiles.count) Metal shaders → default.metallib",
            executable: Path("/bin/sh"),
            arguments: ["-c", script, "sh", out.string, prebuilt.string, moduleCache.string, log.string]
                + metalFiles.map(\.string),
            inputFiles: metalFiles + (hasPrebuilt ? [prebuilt] : []),
            outputFiles: [out]
        )]
    }
}
