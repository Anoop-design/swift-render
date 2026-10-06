import AppKit
import Foundation
import Observation
import StudioCore
import UniformTypeIdentifiers

@MainActor @Observable
final class StudioStore {
    var sourceURL: URL?
    var workspaceURL: URL?
    var settings = FilmSettings()
    var inventory: SourceInventory?
    var movieURL: URL?
    var posterURL: URL?
    var isBusy = false
    var statusText = "Choose an app to begin."
    var logText = ""
    var errorMessage: String?
    var isSample = false
    @ObservationIgnored private let runner = CommandRunner()
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var inventoryData: Data?

    var hasComposer: Bool { workspaceURL != nil }
    var canRender: Bool { hasComposer && !isBusy }
    var canPrepare: Bool { sourceURL != nil && !isBusy && !hasComposer }

    private var workflow: URL {
        get throws {
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("Workflow")
            if let bundled, FileManager.default.fileExists(atPath: bundled.appendingPathComponent("scripts/launch.py").path) { return bundled }
            let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("codex-plugin/skills/app-launch-video")
            guard FileManager.default.fileExists(atPath: development.appendingPathComponent("scripts/launch.py").path) else {
                throw StudioError.message("Workflow resources are missing. Build the app bundle with tools/studio/build.py.")
            }
            return development
        }
    }

    func chooseSource() {
        guard !isBusy, let url = pickDirectory(title: "Choose an app codebase", message: "Select the folder containing your Swift, iOS, or macOS app.") else { return }
        sourceURL = url; workspaceURL = nil; movieURL = nil; posterURL = nil
        inventory = nil; inventoryData = nil; isSample = false
        settings = FilmSettings(); settings.title = url.lastPathComponent
        begin("Reading the app’s source…") { [self] in
            let report = FileManager.default.temporaryDirectory.appendingPathComponent("swift-render-inventory-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: report) }
            try await helper(["inspect", "--app", url.path, "--output", report.path])
            let data = try Data(contentsOf: report)
            inventory = try JSONDecoder().decode(SourceInventory.self, from: data)
            inventoryData = data
            let count = inventory?.files.count ?? 0
            statusText = count == 0 ? "No supported app files found. Choose another folder." : "Found \(count) source and resource files. Prepare a film project next."
            if inventory?.coverage?.limitReached == true { statusText += " Inventory reached its scan limit." }
            if let errors = inventory?.coverage?.errors, !errors.isEmpty { statusText += " Some files could not be read; see Activity."; appendLog(errors.joined(separator: "\n")) }
        }
    }

    func prepareProject() {
        guard canPrepare, let sourceURL else { return }
        createWorkspace(source: sourceURL, sample: false)
    }

    func createSample() {
        guard !isBusy else { return }
        createWorkspace(source: nil, sample: true)
    }

    private func createWorkspace(source: URL?, sample: Bool) {
        let panel = NSSavePanel()
        panel.title = sample ? "Create a sample film project" : "Create a film project"
        panel.message = "Choose a new workspace folder outside your app codebase."
        panel.nameFieldStringValue = sample ? "Sample Film" : "\(settings.title) Film"
        panel.canCreateDirectories = true
        panel.prompt = "Create Project"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do { try FilmProject.checkNewWorkspace(folder, source: source) }
        catch { errorMessage = error.localizedDescription; return }
        var projectSettings = sample ? FilmSettings() : settings
        if sample { projectSettings.title = "Sample Film"; projectSettings.promise = "Try the native render pipeline." }
        let dataToCopy = sample ? nil : inventoryData
        begin("Preparing the native film project…") { [self] in
            try projectSettings.validate()
            try await helper(["init", "--output", folder.appendingPathComponent("NativeComposer").path])
            if let dataToCopy { try dataToCopy.write(to: folder.appendingPathComponent("app-inventory.json"), options: .atomic) }
            let document = FilmProject(settings: projectSettings, sourcePath: source?.path, isSample: sample)
            try document.save(to: folder)
            try brief(for: document, at: folder).write(to: folder.appendingPathComponent("film-brief.md"), atomically: true, encoding: .utf8)
            workspaceURL = folder; sourceURL = source; settings = projectSettings; isSample = sample
            movieURL = nil; posterURL = nil
            if sample { inventory = nil; inventoryData = nil }
            statusText = sample ? "Sample project ready. Render a preview to try it." : "Project ready. Copy the brief into Codex to adapt your app’s real components."
        }
    }

    func openProject() {
        guard !isBusy, let folder = pickDirectory(title: "Open a SwiftRender Studio project", message: "Select a workspace containing swift-render-studio.json.") else { return }
        do {
            let document = try FilmProject.load(from: folder)
            let storedInventory = try? Data(contentsOf: folder.appendingPathComponent("app-inventory.json"))
            workspaceURL = folder; sourceURL = document.sourcePath.map { URL(fileURLWithPath: $0) }
            settings = document.settings; isSample = document.isSample
            inventoryData = storedInventory
            inventory = storedInventory.flatMap { try? JSONDecoder().decode(SourceInventory.self, from: $0) }
            movieURL = document.lastMoviePath.flatMap { relative in
                let candidate = folder.appendingPathComponent(relative).standardizedFileURL
                guard candidate.path.hasPrefix(folder.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: candidate.path) else { return nil }
                return candidate
            }
            posterURL = movieURL?.deletingLastPathComponent().appendingPathComponent("poster.png")
            statusText = "Opened \(settings.title)."
            logText = ""
        } catch { errorMessage = error.localizedDescription }
    }

    func chooseAudio() {
        guard !isBusy else { return }
        let panel = NSOpenPanel(); panel.title = "Choose a soundtrack"
        panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.audioPath = url.path
    }
    func removeAudio() { if !isBusy { settings.audioPath = nil } }

    func copyCodexBrief() {
        guard let folder = workspaceURL else { return }
        do {
            try save()
            let document = FilmProject(settings: settings, sourcePath: sourceURL?.path, isSample: isSample)
            let text = brief(for: document, at: folder)
            try text.write(to: folder.appendingPathComponent("film-brief.md"), atomically: true, encoding: .utf8)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            statusText = "Brief copied. Paste it into a Codex chat with SwiftRender enabled."
        } catch { errorMessage = error.localizedDescription }
    }

    func showProject() { if let workspaceURL { NSWorkspace.shared.open(workspaceURL) } }
    func revealMovie() { if let movieURL { NSWorkspace.shared.activateFileViewerSelecting([movieURL]) } }
    func renderPreview() { render(preview: true) }
    func renderFinal() { render(preview: false) }

    private func render(preview: Bool) {
        guard canRender, let folder = workspaceURL else { return }
        let specification = settings
        let size = preview ? specification.aspect.previewSize : (specification.aspect.width, specification.aspect.height)
        let filename = "\(preview ? "preview" : "export")-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6))"
        let output = folder.appendingPathComponent("Exports").appendingPathComponent(filename)
        let composer = folder.appendingPathComponent("NativeComposer")
        begin(preview ? "Building and rendering the preview…" : "Building and exporting the film…") { [self] in
            try specification.validate()
            try save()
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let common = ["--width", "\(size.0)", "--height", "\(size.1)", "--duration", "\(specification.duration)", "--fps", "\(specification.fps)"]
            // Keep build state with the film instead of inheriting unrelated global
            // SwiftPM configuration and caches from the user's other projects.
            let cache = folder.appendingPathComponent(".studio-cache")
            let modules = cache.appendingPathComponent("modules")
            try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
            let environment = ["CLANG_MODULE_CACHE_PATH": modules.path]
            let prefix = ["swift", "run", "--package-path", composer.path,
                          "--cache-path", cache.appendingPathComponent("packages").path,
                          "--config-path", cache.appendingPathComponent("configuration").path,
                          "--security-path", cache.appendingPathComponent("security").path,
                          "-Xswiftc", "-module-cache-path", "-Xswiftc", modules.path,
                          "launch-film"]
            appendLog("Building the native composer. The first build may download its Swift packages.\n")
            let movie = output.appendingPathComponent("film.mp4")
            var renderArguments = prefix + ["render", "--output", movie.path] + common
            if let audio = specification.audioPath { renderArguments += ["--audio", audio] }
            _ = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: renderArguments, directory: composer, environment: environment, onOutput: outputHandler)
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: movie.path) else { throw StudioError.message("The renderer finished without creating the movie. See Activity for details.") }
            movieURL = movie; posterURL = nil
            try save()
            statusText = "Film exported. Preparing a poster…"
            do {
                let poster = output.appendingPathComponent("poster.png")
                _ = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: prefix + ["frame", "--output", poster.path, "--time", "\(Double(specification.duration) * 0.35)"] + common, directory: composer, environment: environment, onOutput: outputHandler)
                posterURL = poster
            } catch {
                if Task.isCancelled { throw CancellationError() }
                appendLog("Poster unavailable: \(error.localizedDescription)\n")
            }
            statusText = "\(preview ? "Preview" : "Film") ready · \(size.0) × \(size.1) · \(specification.duration) seconds"
        }
    }

    func cancel() {
        guard isBusy else { return }
        statusText = "Cancelling…"
        operation?.cancel(); runner.cancel()
    }

    func saveSettings() {
        guard workspaceURL != nil, !isBusy else { return }
        // Empty titles while typing are allowed in the editor; explicit actions validate.
        if (try? settings.validate()) != nil { try? save() }
    }

    private func save() throws {
        guard let folder = workspaceURL else { return }
        var document = FilmProject(settings: settings, sourcePath: sourceURL?.path, isSample: isSample)
        if let movieURL, movieURL.path.hasPrefix(folder.path + "/") { document.lastMoviePath = String(movieURL.path.dropFirst(folder.path.count + 1)) }
        try document.save(to: folder)
    }

    private func begin(_ message: String, action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true; statusText = message; logText = ""; errorMessage = nil
        operation = Task { [weak self] in
            defer { self?.isBusy = false; self?.operation = nil }
            do { try await action() }
            catch {
                if Task.isCancelled || error is CancellationError { self?.statusText = "Cancelled. Existing exports are preserved." }
                else { self?.statusText = "The operation could not finish."; self?.errorMessage = error.localizedDescription; self?.appendLog("\n\(error.localizedDescription)\n") }
            }
        }
    }

    private var outputHandler: @Sendable (String) -> Void {
        { [weak self] text in Task { @MainActor in self?.appendLog(text) } }
    }
    private func appendLog(_ text: String) {
        logText += text
        if logText.count > 65_536 { logText = String(logText.suffix(65_536)) }
    }
    private func helper(_ arguments: [String]) async throws {
        let script = try workflow.appendingPathComponent("scripts/launch.py")
        _ = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [script.path] + arguments, onOutput: outputHandler)
        try Task.checkCancellation()
    }
    private func pickDirectory(title: String, message: String) -> URL? {
        let panel = NSOpenPanel(); panel.title = title; panel.message = message
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func brief(for document: FilmProject, at folder: URL) -> String {
        """
        Use the SwiftRender app-launch-video plugin to create a launch film.

        Title: \(document.settings.title)
        Product promise: \(document.settings.promise.isEmpty ? "Understand the app and propose a concise product promise." : document.settings.promise)
        App codebase: \(document.sourcePath ?? "No app selected; this is a generic sample project.")
        Film workspace: \(folder.path)
        Native composer: \(folder.appendingPathComponent("NativeComposer").path)
        Format: \(document.settings.aspect.label), \(document.settings.aspect.width) × \(document.settings.aspect.height)
        Duration: \(document.settings.duration) seconds at \(document.settings.fps) fps
        Soundtrack: \(document.settings.audioPath ?? "Create a smooth, continuous musical direction appropriate to the app.")

        Read the product docs and real views, fonts, artwork, and Metal shaders. Reuse the actual components with deterministic film time and realistic demo data. Keep the source app intact. Save selected original hashes and document adaptations in this film workspace. The bundled composer currently contains generic sample content: replace it before treating this as an app launch film. Use an iOS/Catalyst/offscreen native harness where the real source needs one.

        Compose the product story, highlights, and brand reveal; coordinate motion and music on the same edit clock. Inspect key frames and audition a motion preview. Preserve the launch-film render/frame CLI interface so SwiftRender Studio can preview and export the adapted film. When finished, return to Studio and use Render Preview. Do not publish the film unless asked.
        """
    }
}

private enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
