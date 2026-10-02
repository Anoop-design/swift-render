import AppKit
import SwiftUI

/// Load a PNG/JPEG resource bundled via SPM `.process("Resources")`.
/// Returns a SwiftUI Image, falling back to a placeholder if missing.
public func bundledImage(_ name: String, ext: String = "png") -> Image {
    if let url = Bundle.module.url(forResource: name, withExtension: ext),
       let nsImage = NSImage(contentsOf: url) {
        return Image(nsImage: nsImage)
    }
    fputs("[swift-render] WARN: missing asset \(name).\(ext) in Bundle.module\n", stderr)
    return Image(systemName: "questionmark.square")
}

/// Resolves file paths used by scenes (samples, video, images, voiceover caches).
///
/// Relative paths are tried against, in order: the working directory, `<cwd>/assets`,
/// the package root, `<root>/assets`, then `extraSearchPaths`. So a scene can say
/// `sample("openear-foley/click_1.wav", …)` or `VideoClip("clips/demo.mp4", …)`.
public enum AssetPaths {
    /// Package root of this checkout (derived from this source file's location).
    public static let packageRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SwiftRender
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // root

    nonisolated(unsafe) public static var extraSearchPaths: [URL] = []

    public static var searchPaths: [URL] {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return [cwd, cwd.appendingPathComponent("assets"),
                packageRoot, packageRoot.appendingPathComponent("assets")] + extraSearchPaths
    }

    /// The first existing file for `path`, or nil.
    public static func resolve(_ path: String) -> URL? {
        let fm = FileManager.default
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return fm.fileExists(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        for base in searchPaths {
            let url = base.appendingPathComponent(expanded)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

/// Small thread-safe memo used by the media caches.
final class LockedCache<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [Key: Value] = [:]
    private var order: [Key] = []
    private let limit: Int

    init(limit: Int = .max) { self.limit = limit }

    func value(_ key: Key, orInsert make: () throws -> Value) rethrows -> Value {
        lock.lock()
        if let v = store[key] { lock.unlock(); return v }
        lock.unlock()
        let v = try make()
        lock.lock()
        if store[key] == nil {
            store[key] = v
            order.append(key)
            if order.count > limit { store.removeValue(forKey: order.removeFirst()) }
        }
        lock.unlock()
        return v
    }
}

/// A box for handing a result out of a completion handler we block on.
final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}
