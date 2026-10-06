import Foundation

public enum FilmAspect: String, Codable, CaseIterable, Identifiable, Sendable {
    case vertical, landscape, square, fourThree
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .vertical: return "Vertical · 9:16"
        case .landscape: return "Landscape · 16:9"
        case .square: return "Square · 1:1"
        case .fourThree: return "Classic · 4:3"
        }
    }
    public var width: Int {
        switch self { case .vertical, .square: return 1080; case .landscape: return 1920; case .fourThree: return 1536 }
    }
    public var height: Int {
        switch self { case .vertical: return 1920; case .landscape, .square: return 1080; case .fourThree: return 1152 }
    }
    public var previewSize: (width: Int, height: Int) {
        switch self {
        case .vertical: return (396, 704)
        case .landscape: return (704, 396)
        case .square: return (720, 720)
        case .fourThree: return (720, 540)
        }
    }
}

public struct FilmSettings: Codable, Equatable, Sendable {
    public var title: String = "Untitled film"
    public var promise: String = ""
    public var aspect: FilmAspect = .vertical
    public var duration: Int = 15
    public var fps: Int = 30
    public var audioPath: String?
    public init() {}

    public func validate() throws {
        guard (5...60).contains(duration), [24, 30, 60].contains(fps), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectError.invalidSettings
        }
    }
}

public struct SourceFile: Codable, Identifiable, Sendable {
    public let path: String
    public let kind: String
    public var id: String { path }
}

public struct SourceInventory: Codable, Sendable {
    public let counts: [String: Int]
    public let files: [SourceFile]
    public let coverage: Coverage?
    public struct Coverage: Codable, Sendable {
        public let limitReached: Bool?
        public let errors: [String]?
    }
}

public enum ProjectError: LocalizedError {
    case invalidSettings, unsupportedVersion, missingComposer, nestedInSource, alreadyExists
    public var errorDescription: String? {
        switch self {
        case .invalidSettings: return "Enter a title, a duration from 5–60 seconds, and 24, 30, or 60 fps."
        case .unsupportedVersion: return "This project was saved by an unsupported version of SwiftRender Studio."
        case .missingComposer: return "This folder needs a NativeComposer/Package.swift film project."
        case .nestedInSource: return "Choose a film workspace outside the source app folder."
        case .alreadyExists: return "A folder already exists at that location. Choose a new workspace name."
        }
    }
}

public struct FilmProject: Codable, Sendable {
    public var formatVersion: Int = 1
    public var settings: FilmSettings
    public var sourcePath: String?
    public var isSample: Bool
    public var lastMoviePath: String?
    public init(settings: FilmSettings, sourcePath: String?, isSample: Bool) {
        self.settings = settings; self.sourcePath = sourcePath; self.isSample = isSample
    }
    public static let filename = "swift-render-studio.json"

    public static func load(from directory: URL) throws -> FilmProject {
        let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.appendingPathComponent(filename)))
        guard result.formatVersion == 1 else { throw ProjectError.unsupportedVersion }
        try result.settings.validate()
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("NativeComposer/Package.swift").path) else {
            throw ProjectError.missingComposer
        }
        return result
    }

    public func save(to directory: URL) throws {
        try settings.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: directory.appendingPathComponent(Self.filename), options: .atomic)
    }

    public static func checkNewWorkspace(_ workspace: URL, source: URL?) throws {
        // Foundation may leave an entire nonexistent URL unresolved. Resolve its
        // closest existing ancestor first so a symlinked parent cannot bypass this check.
        var existing = workspace.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: existing.path)) != nil { throw ProjectError.alreadyExists }
            missing.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath().standardizedFileURL
        for component in missing.reversed() { resolved.appendPathComponent(component) }
        let output = resolved.path
        if let source {
            let app = source.resolvingSymlinksInPath().standardizedFileURL.path
            guard output != app, !output.hasPrefix(app + "/") else { throw ProjectError.nestedInSource }
        }
        guard !FileManager.default.fileExists(atPath: output) else { throw ProjectError.alreadyExists }
    }
}
