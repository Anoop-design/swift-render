import SwiftUI

/// PixelSonnet — an 8-bit self-portrait of Sonnet 5.5.
///
///   swift run swift-render render PixelSonnet --out out/pixel_sonnet.mp4
///
/// Everything is drawn into one Canvas on a 240x135 logical grid (x8 = 1080p)
/// with the PICO-8 palette, a hand-built 5x7 bitmap font and tiny sprites.
/// 128 BPM, ten bars:
///   bars 0-1  boot screen          bars 2-4  walk + dialogue
///   bars 5-6  boss fight (bug)     bars 7-8  skill tree     bar 9  credits
public struct PixelSonnet: RenderScene {
    public static let defaultDuration: Double = 18.75
    public static var ownsPostFX: Bool { true }

    static let beat = 60.0 / 128.0
    static let bar = beat * 4
    static let W = 240.0, H = 135.0
    static let cuts: [Double] = [2, 5, 7, 9].map { bar * Double($0) }   // 3.75 9.375 13.125 16.875
    static let groundY = 108.0

    // boss-fight timeline (local to bar 5)
    static let fire: [Double] = (0..<4).map { 0.7 + beat * Double($0) }
    static let flight = 0.6
    static let hitTimes: [Double] = fire.map { $0 + flight }
    static var killLocal: Double { hitTimes[3] }

    // MARK: palette (PICO-8)
    static let ink    = Color(red: 0.04, green: 0.04, blue: 0.09)
    static let indigo = Color(red: 0.11, green: 0.17, blue: 0.33)
    static let plum   = Color(red: 0.49, green: 0.15, blue: 0.33)
    static let red    = Color(red: 1.00, green: 0.00, blue: 0.30)
    static let orange = Color(red: 1.00, green: 0.64, blue: 0.00)
    static let yellow = Color(red: 1.00, green: 0.93, blue: 0.15)
    static let green  = Color(red: 0.00, green: 0.89, blue: 0.21)
    static let blue   = Color(red: 0.16, green: 0.68, blue: 1.00)
    static let lav    = Color(red: 0.51, green: 0.46, blue: 0.61)
    static let pink   = Color(red: 1.00, green: 0.47, blue: 0.66)
    static let peach  = Color(red: 1.00, green: 0.80, blue: 0.67)
    static let white  = Color(red: 1.00, green: 0.95, blue: 0.91)

    // MARK: soundtrack

    public static func soundtrack(duration: Double) -> Score? {
        Score(duration: duration) {
            // boot: ticking hats, blip on PRESS START
            every(beat, from: 0, to: bar * 2) { hat(at: $0, amp: 0.10) }
            bass(Note(880), at: 0.9, duration: 0.18, amp: 0.2)
            bass(Note(1320), at: 1.05, duration: 0.25, amp: 0.2)

            // groove from bar 2 → 9
            boom(at: bar * 2, amp: 0.8, duration: 1.4)
            fourOnFloor(from: bar * 2, to: bar * 9, bpm: 128)
            hatSixteenths(from: bar * 2, to: bar * 9, bpm: 128)
            bassline([.a1, .a1, .c2, .g1], from: bar * 2, to: bar * 9, bpm: 128)
            crashes(at: cuts)

            // chiptune arpeggio on sixteenths (Am – F – C – G)
            let chords: [[Double]] = [[220, 262, 330, 440], [175, 220, 262, 349],
                                      [262, 330, 392, 523], [196, 247, 294, 392]]
            every(beat / 4, from: bar * 2, to: bar * 9) { t in
                let step = Int((t - bar * 2) / (beat / 4))
                let chord = chords[(step / 16) % 4]
                return bass(Note(chord[step % 4]), at: t, duration: 0.11, amp: 0.10)
            }

            // boss fight: shots + hits + explosion
            let b = bar * 5
            for f in fire { bass(Note(1175), at: b + f, duration: 0.08, amp: 0.22) }
            for h in hitTimes { clap(at: b + h, amp: 0.5) }
            boom(at: b + killLocal, amp: 0.9, duration: 1.0)
            crash(at: b + killLocal, amp: 0.4)

            // skill tree ticks
            for i in 0..<5 { bass(Note(660 + Double(i) * 110), at: bar * 7 + 0.5 + beat * Double(i), duration: 0.12, amp: 0.2) }

            // credits: riser into a final hit
            riser(at: bar * 8, duration: bar, amp: 0.5)
            boom(at: bar * 9, amp: 1.0)
            drone(.a1, from: bar * 9, for: bar, amp: 0.14)
        }
    }

    // MARK: body

    @MainActor
    public static func body(at t: Double, duration: Double) -> some View {
        // camera shake (integer logical pixels) on hits and cuts
        var sx = 0.0, sy = 0.0
        let b = bar * 5
        for h in hitTimes + [killLocal] where t >= b + h && t < b + h + 0.2 {
            let k = 1 - (t - b - h) / 0.2
            sx += (Int(t * 60) % 2 == 0 ? 1 : -1) * 2 * k
            sy += (Int(t * 60) % 3 == 0 ? 1 : -1) * 1 * k
        }
        let shake = (sx.rounded(), sy.rounded())

        return Canvas { ctx, size in
            let s = size.width / W
            var px = Pix(ctx: ctx, s: s, ox: shake.0, oy: shake.1)
            px.fillAll(ink)
            switch t {
            case ..<cuts[0]:  boot(&px, t)
            case ..<cuts[1]:  world(&px, t - cuts[0])
            case ..<cuts[2]:  boss(&px, t - cuts[1])
            case ..<cuts[3]:  skills(&px, t - cuts[2])
            default:          credits(&px, t - cuts[3])
            }
            px.ox = 0; px.oy = 0
            scanlines(&px)
            dissolve(&px, t: t, duration: duration)
        }
        .background(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: scenes

    @MainActor static func boot(_ p: inout Pix, _ t: Double) {
        stars(&p, t, count: 70, maxY: 135)
        let title = "SONNET 5.5"
        let shown = min(title.count, Int(t / 0.09))
        let x0 = 30.0
        for (i, ch) in title.prefix(shown).enumerated() {
            let fresh = t - Double(i) * 0.09 < 0.12
            p.text(String(ch), x0 + Double(i) * 18, 22 + (fresh ? -2 : 0), scale: 3,
                   fresh ? white : yellow, shadow: plum)
        }
        if t > 1.8 { p.text("A PIXEL ADVENTURE", 69, 52, scale: 1, lav) }
        // hero drops in
        let drop = Ease.bounce(Ease.clip(t, 0.9, 1.6))
        let hy = -50 + 50 * drop
        hero(&p, 102, 66 + hy, t: t, walking: false, scale: 3)
        p.rect(0, 112, W, 1, plum)
        if t > 2.0, Int(t / beat) % 2 == 0 { p.text("PRESS START", 87, 120, scale: 1, white) }
        if t > 2.0 { p.text("1 PLAYER", 6, 126, scale: 1, lav) }
    }

    @MainActor static func world(_ p: inout Pix, _ t: Double) {
        sky(&p, t)
        let scroll = t * 50
        hills(&p, offset: t * 8, base: 74, amp: 10, color: plum, seed: 0.0)
        hills(&p, offset: t * 20, base: 92, amp: 7, color: indigo, seed: 2.0)
        ground(&p, scroll)
        hero(&p, 50, 62, t: t, walking: true, scale: 3)
        // dialogue
        speech(&p, ["HI. I'M SONNET 5.5."], t: t, start: 0.4, end: 2.9, x: 92, y: 36)
        speech(&p, ["I WRITE CODE.", "I WRITE POEMS."], t: t, start: 3.1, end: 5.6, x: 92, y: 28)
    }

    @MainActor static func boss(_ p: inout Pix, _ t: Double) {
        sky(&p, t + 3.7)
        hills(&p, offset: 30 + t * 8, base: 74, amp: 10, color: plum, seed: 0.0)
        hills(&p, offset: 60 + t * 20, base: 92, amp: 7, color: indigo, seed: 2.0)
        ground(&p, 0)
        let kill = killLocal
        // hero recoil + celebration jump
        var recoil = 0.0
        for f in fire where t >= f && t < f + 0.1 { recoil = -1 }
        var jump = 0.0
        if t > kill + 0.5 { let u = (t - kill - 0.5); jump = -abs(sin(u * 6)) * 10 * exp(-u * 0.6) }
        hero(&p, 36 + recoil, 62 + jump.rounded(), t: t, walking: false, scale: 3)
        // bug
        let enter = Ease.easeOut(Ease.clip(t, 0, 0.6))
        let hitsSoFar = hitTimes.filter { t >= $0 }.count
        if t < kill {
            var bx = 270 - 100 * enter + Double(hitsSoFar) * 3
            var flashed = false
            for h in hitTimes where t >= h && t < h + 0.08 { flashed = true; bx += 2 }
            bx = bx.rounded()
            bug(&p, bx, 84, white: flashed, t: t)
            // bullets
            for f in fire where t >= f {
                let bxp = 78 + (t - f) * 140
                if bxp < bx + 2 { p.rect(bxp.rounded(), 82, 5, 2, yellow); p.rect(bxp.rounded() - 3, 82, 2, 2, orange) }
            }
        } else {
            explosion(&p, 190, 94, t: t - kill)
        }
        // HUD
        let score = hitsSoFar * 25 + (t >= kill ? 100 : 0)
        p.text(String(format: "SCORE %06d", score), 6, 6, scale: 1, white, shadow: ink)
        p.text("BUG", 176, 6, scale: 1, white, shadow: ink)
        for i in 0..<4 { p.rect(200 + Double(i) * 8, 6, 6, 7, i < 4 - hitsSoFar ? red : indigo) }
        if t > kill + 0.2 {
            let u = t - kill - 0.2
            p.text("BUG SQUASHED!", 48, 24 - min(u * 6, 6), scale: 2, yellow, shadow: plum)
            if u > 0.2 { p.text("+100", 100, 44 - min((u - 0.2) * 20, 10), scale: 2, green, shadow: ink) }
        }
    }

    @MainActor static func skills(_ p: inout Pix, _ t: Double) {
        p.fillAll(indigo)
        stars(&p, t, count: 40, maxY: 135)
        p.frame(8, 8, W - 16, H - 16, white)
        p.frame(11, 11, W - 22, H - 22, lav)
        p.text("SKILL TREE", 60, 20, scale: 2, yellow, shadow: plum)
        let rows: [(String, Int, String)] = [
            ("CODE", 10, "MAX"), ("PROSE", 10, "MAX"), ("MATH", 9, "LV 9"),
            ("CURIOSITY", 10, "MAX"), ("TOUCHING GRASS", 2, "NOOB"),
        ]
        for (i, r) in rows.enumerated() {
            let y = 44.0 + Double(i) * 14
            let start = 0.5 + beat * Double(i)
            let appear = Ease.clip(t, start - 0.2, start)
            if appear <= 0 { continue }
            p.text(r.0, 22, y, scale: 1, white)
            let filled = min(r.1, Int(max(0, t - start) / 0.06))
            for c in 0..<10 {
                let on = c < filled
                let col: Color = r.1 == 10 ? green : (r.1 <= 2 ? red : orange)
                p.rect(124 + Double(c) * 7, y, 5, 7, on ? col : plum)
            }
            if filled >= r.1 { p.text(r.2, 200, y, scale: 1, yellow) }
        }
    }

    @MainActor static func credits(_ p: inout Pix, _ t: Double) {
        sky(&p, t * 0.5)
        hills(&p, offset: 12, base: 74, amp: 10, color: plum, seed: 0.0)
        hills(&p, offset: 40, base: 92, amp: 7, color: indigo, seed: 2.0)
        ground(&p, 0)
        let pop = Ease.bounce(Ease.clip(t, 0, 0.5))
        p.text("THANKS FOR PLAYING", 12, 16 - 10 * (1 - pop), scale: 2, white, shadow: ink)
        p.text("SONNET 5.5", 30, 40 - 10 * (1 - pop), scale: 3, yellow, shadow: plum)
        hero(&p, 102, 62, t: t, walking: false, scale: 3)
        if Int(t / (beat / 2)) % 2 == 0 { p.text("INSERT COIN", 87, 120, scale: 1, white, shadow: ink) }
    }

    // MARK: world pieces

    static func h(_ n: Int) -> Double {
        let x = sin(Double(n) * 12.9898) * 43758.5453
        return x - floor(x)
    }

    @MainActor static func sky(_ p: inout Pix, _ t: Double) {
        let bands: [Color] = [indigo, indigo, plum, plum, red, pink, orange, orange]
        let bh = groundY / Double(bands.count)
        for (i, c) in bands.enumerated() { p.rect(0, (Double(i) * bh).rounded(), W, bh.rounded() + 1, c) }
        for i in 1..<bands.count {
            let yb = (Double(i) * bh).rounded()
            for r in 0..<3 {
                var x = Double(r % 2)
                while x < W { p.rect(x, yb - 1 + Double(r), 1, 1, bands[i]); x += 2 }
            }
        }
        stars(&p, t, count: 45, maxY: 50)
        // striped sun
        let cx = 176.0, cy = 86.0, r = 24.0
        for dy in stride(from: -r, through: 0, by: 1) {
            if dy > -10, Int(-dy) % 4 < 1 { continue }
            let w = (r * r - dy * dy).squareRoot()
            p.rect((cx - w).rounded(), cy + dy, (w * 2).rounded(), 1, dy < -12 ? yellow : orange)
        }
    }

    @MainActor static func stars(_ p: inout Pix, _ t: Double, count: Int, maxY: Double) {
        for i in 0..<count {
            let x = (h(i) * W).rounded(), y = (h(i + 100) * maxY).rounded()
            if (Int(t * 2.5) + i) % 5 == 0 { continue }
            p.rect(x, y, 1, 1, i % 3 == 0 ? white : lav)
            if i % 9 == 0 { p.rect(x - 1, y, 3, 1, white); p.rect(x, y - 1, 1, 3, white) }
        }
    }

    @MainActor static func hills(_ p: inout Pix, offset: Double, base: Double, amp: Double,
                                 color: Color, seed: Double) {
        for x in stride(from: 0.0, to: W, by: 1) {
            let u = x + offset
            let top = base - amp * (0.6 * sin(u * 0.035 + seed) + 0.4 * sin(u * 0.09 + seed * 2))
            let y = top.rounded()
            p.rect(x, y, 1, groundY - y, color)
        }
    }

    @MainActor static func ground(_ p: inout Pix, _ scroll: Double) {
        p.rect(0, groundY, W, H - groundY, green)
        p.rect(0, groundY + 3, W, H - groundY - 3, Color(red: 0.0, green: 0.53, blue: 0.32))
        p.rect(0, groundY + 12, W, H - groundY - 12, Color(red: 0.67, green: 0.32, blue: 0.21))
        // scrolling tufts + flowers
        for i in 0..<14 {
            let x = (Double(i) * 19 - scroll).truncatingRemainder(dividingBy: W + 20)
            let xx = (x < -10 ? x + W + 20 : x).rounded()
            p.rect(xx, groundY - 2, 1, 2, green); p.rect(xx + 2, groundY - 3, 1, 3, green)
            if i % 3 == 0 { p.rect(xx + 5, groundY - 4, 2, 2, i % 2 == 0 ? pink : yellow) }
        }
        // soil checker scrolls
        for i in 0..<20 {
            let x = (Double(i) * 14 - scroll * 1.0).truncatingRemainder(dividingBy: W + 14)
            let xx = (x < -6 ? x + W + 14 : x).rounded()
            p.rect(xx, groundY + 7, 4, 2, Color(red: 0.0, green: 0.53, blue: 0.32))
        }
    }

    // MARK: sprites

    static let heroRows: [String] = [
        ".....YY.....",
        ".....K......",
        "..KKKKKKKK..",
        ".KPPPPPPPPK.",
        ".KPKKPPKKPK.",
        ".KPKKPPKKPK.",
        ".KPKPPPPKPK.",
        ".KPPKKKKPPK.",
        "..KKKKKKKK..",
        "...KCCCCK...",
        "..KCCCCCCK..",
        "..KCCYYCCK..",
        "..KCCCCCCK..",
    ]
    static let legsA = ["...KK..KK...", "..KKK..KKK."]
    static let legsB = ["....KK.KK...", "....KKKKKK.."]
    static let heroPalette: [Character: Color] = [
        "K": ink, "P": peach, "C": blue, "Y": yellow,
    ]

    @MainActor static func hero(_ p: inout Pix, _ x: Double, _ y: Double, t: Double,
                                walking: Bool, scale: Double) {
        let phase = walking ? Int(t / 0.14) % 2 : 0
        let bob = walking && phase == 1 ? -1.0 : 0
        let idle = walking ? 0.0 : (Int(t / (beat)) % 2 == 0 ? 0.0 : -1.0)
        let ty = y + (bob + idle) * scale / 3 * 1
        p.sprite(heroRows, heroPalette, x, ty, scale)
        let legs = (walking && phase == 1) ? legsB : legsA
        p.sprite(legs, heroPalette, x, ty + Double(heroRows.count) * scale, scale)
        // blink
        if Int(t * 10) % 25 == 0 {
            p.rect(x + 3 * scale, ty + 4 * scale, 2 * scale, 2 * scale, peach)
            p.rect(x + 7 * scale, ty + 4 * scale, 2 * scale, 2 * scale, peach)
        }
    }

    static let bugRows: [String] = [
        "..K....K..",
        "...K..K...",
        "..KRRRRK..",
        ".KRWRRWRK.",
        "KRRRRRRRRK",
        ".KRRRRRRK.",
        "K.KK..KK.K",
        "..K....K..",
    ]

    @MainActor static func bug(_ p: inout Pix, _ x: Double, _ y: Double, white: Bool, t: Double) {
        let pal: [Character: Color] = white
            ? ["K": PixelSonnet.white, "R": PixelSonnet.white, "W": ink]
            : ["K": ink, "R": red, "W": PixelSonnet.white]
        let wig = Int(t / 0.12) % 2 == 0 ? 0.0 : -1.0
        p.sprite(bugRows, pal, x, y + wig, 3)
    }

    @MainActor static func explosion(_ p: inout Pix, _ cx: Double, _ cy: Double, t: Double) {
        if t < 0.12 { p.rect(cx - 18, cy - 12, 36, 24, white); return }
        let cols = [red, orange, yellow, white]
        for i in 0..<28 {
            let a = h(i) * .pi * 2
            let v = 25 + h(i + 50) * 55
            let life = 0.9
            if t > life { continue }
            let x = cx + cos(a) * v * t
            let y = cy + sin(a) * v * t + 0.5 * 140 * t * t
            let sz: Double = t < 0.4 ? 3 : 2
            p.rect(x.rounded(), y.rounded(), sz, sz, cols[i % 4])
        }
    }

    @MainActor static func speech(_ p: inout Pix, _ lines: [String], t: Double,
                                  start: Double, end: Double, x: Double, y: Double) {
        guard t >= start, t < end else { return }
        let total = lines.joined().count
        var left = max(0, Int((t - start) * 18))
        let w = Double(lines.map(\.count).max() ?? 1) * 6 + 7
        let hgt = Double(lines.count) * 9 + 5
        p.rect(x - 1, y - 1, w + 2, hgt + 2, ink)
        p.rect(x, y, w, hgt, white)
        // tail toward the hero
        p.rect(x + 2, y + hgt + 1, 5, 2, ink); p.rect(x + 3, y + hgt, 3, 2, white)
        p.rect(x + 1, y + hgt + 3, 3, 2, ink)
        for (i, line) in lines.enumerated() {
            let n = min(line.count, left); left = max(0, left - line.count)
            p.text(String(line.prefix(n)), x + 4, y + 3 + Double(i) * 9, scale: 1, ink)
        }
        if left == 0, total > 0, Int(t * 4) % 2 == 0 {
            p.rect(x + w - 6, y + hgt - 5, 3, 3, red)
        }
    }

    // MARK: post

    @MainActor static func scanlines(_ p: inout Pix) {
        var y = 1.0
        while y < H { p.rect(0, y, W, 1, Color.black.opacity(0.10)); y += 2 }
    }

    static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    @MainActor static func dissolve(_ p: inout Pix, t: Double, duration: Double) {
        var cover = cuts.map { max(0, 1 - abs(t - $0) / 0.22) }.max() ?? 0
        cover = max(cover, Ease.clip(t, duration - 0.7, duration))
        guard cover > 0 else { return }
        let cell = 3.0
        for cy in 0..<Int((H / cell).rounded(.up)) {
            for cx in 0..<Int((W / cell).rounded(.up)) {
                let thr = bayer[(cx % 4) + (cy % 4) * 4] / 16.0
                if cover > thr + 0.001 || cover >= 0.999 {
                    p.rect(Double(cx) * cell, Double(cy) * cell, cell, cell, ink)
                }
            }
        }
    }
}

// MARK: - Pixel canvas helper

struct Pix {
    let ctx: GraphicsContext
    let s: Double
    var ox = 0.0, oy = 0.0

    func fillAll(_ c: Color) { rawRect(0, 0, 240 * s, 135 * s, c) }

    func rawRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Color) {
        ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(c))
    }

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Color) {
        let x0 = ((x + ox) * s).rounded(), y0 = ((y + oy) * s).rounded()
        let x1 = ((x + ox + w) * s).rounded(), y1 = ((y + oy + h) * s).rounded()
        ctx.fill(Path(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)), with: .color(c))
    }

    func frame(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Color) {
        rect(x, y, w, 1, c); rect(x, y + h - 1, w, 1, c)
        rect(x, y, 1, h, c); rect(x + w - 1, y, 1, h, c)
    }

    func sprite(_ rows: [String], _ pal: [Character: Color], _ x: Double, _ y: Double, _ sc: Double) {
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                guard let col = pal[ch] else { continue }
                rect(x + Double(c) * sc, y + Double(r) * sc, sc, sc, col)
            }
        }
    }

    func text(_ str: String, _ x: Double, _ y: Double, scale: Double, _ c: Color, shadow: Color? = nil) {
        if let sh = shadow { glyphs(str, x + scale, y + scale, scale, sh) }
        glyphs(str, x, y, scale, c)
    }

    private func glyphs(_ str: String, _ x: Double, _ y: Double, _ sc: Double, _ c: Color) {
        var cx = x
        for ch in str {
            if let g = PixelFont.glyphs[ch] {
                for (r, row) in g.enumerated() {
                    for (col, v) in row.enumerated() where v == "X" {
                        rect(cx + Double(col) * sc, y + Double(r) * sc, sc, sc, c)
                    }
                }
            }
            cx += 6 * sc
        }
    }
}

enum PixelFont {
    static let glyphs: [Character: [String]] = {
        let raw: [Character: String] = [
            "A": ".XXX./X...X/X...X/XXXXX/X...X/X...X/X...X",
            "B": "XXXX./X...X/X...X/XXXX./X...X/X...X/XXXX.",
            "C": ".XXXX/X..../X..../X..../X..../X..../.XXXX",
            "D": "XXXX./X...X/X...X/X...X/X...X/X...X/XXXX.",
            "E": "XXXXX/X..../X..../XXXX./X..../X..../XXXXX",
            "F": "XXXXX/X..../X..../XXXX./X..../X..../X....",
            "G": ".XXXX/X..../X..../X.XXX/X...X/X...X/.XXXX",
            "H": "X...X/X...X/X...X/XXXXX/X...X/X...X/X...X",
            "I": "XXXXX/..X../..X../..X../..X../..X../XXXXX",
            "J": "..XXX/...X./...X./...X./...X./X..X./.XX..",
            "K": "X...X/X..X./X.X../XX.../X.X../X..X./X...X",
            "L": "X..../X..../X..../X..../X..../X..../XXXXX",
            "M": "X...X/XX.XX/X.X.X/X.X.X/X...X/X...X/X...X",
            "N": "X...X/XX..X/X.X.X/X..XX/X...X/X...X/X...X",
            "O": ".XXX./X...X/X...X/X...X/X...X/X...X/.XXX.",
            "P": "XXXX./X...X/X...X/XXXX./X..../X..../X....",
            "Q": ".XXX./X...X/X...X/X...X/X.X.X/X..X./.XX.X",
            "R": "XXXX./X...X/X...X/XXXX./X.X../X..X./X...X",
            "S": ".XXXX/X..../X..../.XXX./....X/....X/XXXX.",
            "T": "XXXXX/..X../..X../..X../..X../..X../..X..",
            "U": "X...X/X...X/X...X/X...X/X...X/X...X/.XXX.",
            "V": "X...X/X...X/X...X/X...X/X...X/.X.X./..X..",
            "W": "X...X/X...X/X...X/X.X.X/X.X.X/XX.XX/X...X",
            "X": "X...X/X...X/.X.X./..X../.X.X./X...X/X...X",
            "Y": "X...X/X...X/.X.X./..X../..X../..X../..X..",
            "Z": "XXXXX/....X/...X./..X../.X.../X..../XXXXX",
            "0": ".XXX./X...X/X..XX/X.X.X/XX..X/X...X/.XXX.",
            "1": "..X../.XX../..X../..X../..X../..X../.XXX.",
            "2": ".XXX./X...X/....X/...X./..X../.X.../XXXXX",
            "3": "XXXX./....X/....X/.XXX./....X/....X/XXXX.",
            "4": "...X./..XX./.X.X./X..X./XXXXX/...X./...X.",
            "5": "XXXXX/X..../XXXX./....X/....X/X...X/.XXX.",
            "6": ".XXX./X..../X..../XXXX./X...X/X...X/.XXX.",
            "7": "XXXXX/....X/...X./..X../.X.../.X.../.X...",
            "8": ".XXX./X...X/X...X/.XXX./X...X/X...X/.XXX.",
            "9": ".XXX./X...X/X...X/.XXXX/....X/....X/.XXX.",
            ".": "...../...../...../...../...../.XX../.XX..",
            ",": "...../...../...../...../.XX../..X../.X...",
            "!": "..X../..X../..X../..X../..X../...../..X..",
            "?": ".XXX./X...X/....X/...X./..X../...../..X..",
            ":": "...../.XX../.XX../...../.XX../.XX../.....",
            "-": "...../...../...../XXXXX/...../...../.....",
            "+": "...../..X../..X../XXXXX/..X../..X../.....",
            "'": "..X../..X../.X.../...../...../...../.....",
        ]
        return raw.mapValues { $0.split(separator: "/").map(String.init) }
    }()
}
