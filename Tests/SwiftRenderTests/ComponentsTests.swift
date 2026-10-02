import SwiftUI
import XCTest
@testable import SwiftRender

final class MusicTests: XCTestCase {
    func testMidiPitch() {
        XCTAssertEqual(Note.midi(69).hz, 440, accuracy: 1e-9)
        XCTAssertEqual(Note.midi(57).hz, 220, accuracy: 1e-9)
        XCTAssertEqual(Note.a4.transposed(12).hz, 880, accuracy: 1e-9)
    }

    func testChordAndScale() {
        let c = Chord.minor7(.a3)
        XCTAssertEqual(c.notes.map { ($0.hz * 100).rounded() / 100 }, [220, 261.63, 329.63, 392])
        XCTAssertEqual(Scale.minorPentatonic.degree(5, root: .a3).hz, Note.a4.hz, accuracy: 1e-9)
        XCTAssertEqual(Scale.major.degree(-1, root: .c4).hz, Note.b3.hz, accuracy: 1e-9)
    }

    func testPhraseHelpersPlaceEvents() {
        XCTAssertEqual(chordPad(.major7(.c4), at: 1, duration: 2).count, 4)
        let arp = arpeggio(.minor(.a4), from: 0, to: 1, step: 0.25)
        XCTAssertEqual(arp.map(\.time), [0, 0.25, 0.5, 0.75])
        XCTAssertEqual(melody([(0, .a4), (2, .c5)], start: 1, bpm: 120).map(\.time), [1, 2])
    }

    func testMelodicVoicesAreDeterministicAndAudible() {
        let score = Score(duration: 2) {
            pluck(.a4, at: 0.1); bell(.e5, at: 0.4); chip(.c5, at: 0.8)
            pad(.a3, at: 0, duration: 1.5); triBass(.a2, at: 0.2); laser(at: 1.2)
        }
        let a = ScoreSynth.render(score), b = ScoreSynth.render(score)
        XCTAssertEqual(a.left, b.left)
        XCTAssertGreaterThan(a.left.map(abs).max() ?? 0, 0.5)   // master normalizes to ~0.92
    }
}

final class DitherTests: XCTestCase {
    func testBayerIsAPermutation() {
        let ranks = Dither.bayer8.map { Int($0 * 64 - 0.5 + 0.001) }
        XCTAssertEqual(Set(ranks), Set(0..<64))
    }

    func testRampMapsToPaletteAndKeepsTone() throws {
        // horizontal gray ramp 64×8 → 2-colour dither: left mostly dark, right mostly light
        let w = 64, h = 8
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let v = UInt8(x * 255 / (w - 1)); let i = (y * w + x) * 4; px[i] = v; px[i + 1] = v; px[i + 2] = v } }
        let cg = try XCTUnwrap(px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        })
        let out = try XCTUnwrap(Dither.apply(cg, palette: [.black, .white]))
        let data = try XCTUnwrap(out.dataProvider?.data as Data?)
        func lightFraction(_ x0: Int, _ x1: Int) -> Double {
            var lit = 0, n = 0
            for y in 0..<h { for x in x0..<x1 { lit += data[y * out.bytesPerRow + x * 4] > 127 ? 1 : 0; n += 1 } }
            return Double(lit) / Double(n)
        }
        XCTAssertLessThan(lightFraction(0, 8), 0.15)
        XCTAssertGreaterThan(lightFraction(56, 64), 0.85)
        XCTAssertEqual(lightFraction(24, 40), 0.5, accuracy: 0.15)
    }
}

final class PixelFontTests: XCTestCase {
    func testGlyphsAreFiveBySeven() {
        for (ch, rows) in PixelFont.glyphs {
            XCTAssertEqual(rows.count, 7, "\(ch)")
            XCTAssertTrue(rows.allSatisfy { $0.count == 5 }, "\(ch)")
        }
        XCTAssertEqual(PixelFont.width("HI", scale: 2), 22)
    }
}
