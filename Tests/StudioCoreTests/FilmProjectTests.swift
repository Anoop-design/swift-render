import Foundation
import XCTest
@testable import StudioCore

final class FilmProjectTests: XCTestCase {
    func testAspectPreservesProportionsAtEvenPreviewSize() {
        for aspect in FilmAspect.allCases {
            let size = aspect.previewSize
            XCTAssertEqual(size.width % 2, 0)
            XCTAssertEqual(size.height % 2, 0)
            XCTAssertLessThanOrEqual(max(size.width, size.height), 720)
            XCTAssertEqual(Double(size.width) / Double(size.height), Double(aspect.width) / Double(aspect.height), accuracy: 0.003)
        }
    }

    func testProjectRoundTripAndMissingComposer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("NativeComposer"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("NativeComposer/Package.swift")
        try "// fixture".write(to: package, atomically: true, encoding: .utf8)
        var settings = FilmSettings(); settings.title = "Pocket Atlas"; settings.aspect = .fourThree; settings.duration = 12
        let original = FilmProject(settings: settings, sourcePath: "/tmp/App With Spaces", isSample: false)
        try original.save(to: root)
        let loaded = try FilmProject.load(from: root)
        XCTAssertEqual(loaded.settings, settings)
        XCTAssertEqual(loaded.sourcePath, original.sourcePath)
        XCTAssertFalse(loaded.isSample)
        try FileManager.default.removeItem(at: package)
        XCTAssertThrowsError(try FilmProject.load(from: root))
    }

    func testRejectsInvalidSettingsAndUnknownProjectVersion() throws {
        var settings = FilmSettings(); settings.duration = 0
        XCTAssertThrowsError(try settings.validate())
        settings.duration = 12; settings.fps = 29
        XCTAssertThrowsError(try settings.validate())
        settings.fps = 30; settings.title = " \n"
        XCTAssertThrowsError(try settings.validate())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var document = FilmProject(settings: FilmSettings(), sourcePath: nil, isSample: true)
        document.formatVersion = 999
        try document.save(to: root)
        XCTAssertThrowsError(try FilmProject.load(from: root))
    }

    func testWorkspaceCannotBeCreatedInsideSourceOrThroughSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("App")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try FilmProject.checkNewWorkspace(source.appendingPathComponent("Film"), source: source))
        let alias = root.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        XCTAssertThrowsError(try FilmProject.checkNewWorkspace(alias.appendingPathComponent("Film"), source: source))
        XCTAssertNoThrow(try FilmProject.checkNewWorkspace(root.appendingPathComponent("App Film"), source: source))
        XCTAssertThrowsError(try FilmProject.checkNewWorkspace(source, source: nil))
    }
}
