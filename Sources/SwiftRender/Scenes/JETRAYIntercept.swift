import SwiftUI

// MARK: - Data (decoded from render/export_intercept.py via --props)
public struct TrialMeta: Codable {
    public var trial: String; public var maneuver: String
    public var miss_m: Double; public var hit: Bool
    public var vc_max: Double; public var r0: Double; public var n: Int
}
public struct TrialData: Codable {
    public var meta: TrialMeta
    public var iE: [Double]; public var iN: [Double]
    public var tE: [Double]; public var tN: [Double]
    public var R: [Double]; public var vc: [Double]
    public var tgo: [Double]; public var omega: [Double]
    public var az: [Double]; public var el: [Double]
    public var fsize: [Double]; public var locked: [Int]
}

/// JETRAY // COUNTER-UAS INTERCEPT — tactical trajectory-trial render.
public struct JETRAYIntercept: PropsScene {
    public static let defaultDuration: Double = 20.0
    public static var ownsPostFX: Bool { false }

    // palette (Anduril-ish: near-black, cyan friendly, amber hostile)
    static let bg     = Color(red: 0.027, green: 0.043, blue: 0.067)
    static let cyan   = Color(red: 0.30, green: 0.84, blue: 1.00)
    static let amber  = Color(red: 1.00, green: 0.46, blue: 0.13)
    static let green  = Color(red: 0.24, green: 1.00, blue: 0.53)
    static let white  = Color(red: 0.90, green: 0.95, blue: 1.00)

    static func mono(_ s: Double, _ w: Font.Weight = .regular) -> Font {
        .system(size: s, weight: w, design: .monospaced)
    }

    public static var defaultProps: TrialData {
        TrialData(meta: .init(trial: "01", maneuver: "WEAVE", miss_m: 1.1, hit: true,
                              vc_max: 83, r0: 266, n: 2),
                  iE: [0.10, 0.62], iN: [0.55, 0.50], tE: [0.90, 0.63], tN: [0.40, 0.49],
                  R: [266, 2], vc: [0, 83], tgo: [8, 0.1], omega: [0, 0.18],
                  az: [0, 2], el: [0, -1], fsize: [0.03, 0.55], locked: [1, 1])
    }

    // Tactical sound design — low tension drone, a riser into the strike, an
    // impact boom at intercept, then resolve. Timed to the scene's key beats.
    public static func soundtrack(duration: Double) -> Score? {
        let strikeT = 16.2
        return Score(duration: duration) {
            drone(.a1, from: 0.0, for: strikeT, amp: 0.14)            // sub-bass tension
            drone(.e1, from: 2.8, for: strikeT - 2.8, amp: 0.07)     // fifth as engagement opens
            drone(.a2, from: 3.0, for: strikeT - 3.0, amp: 0.04)     // octave pad layer
            // sparse radar-pulse ticks while tracking
            hat(at: 4.5, pan: -0.3); hat(at: 6.5, pan: 0.3); hat(at: 8.5, pan: -0.3)
            hat(at: 10.5, pan: 0.3); hat(at: 12.5, pan: -0.3); hat(at: 14.0, pan: 0.3)
            riser(at: strikeT - 2.3, duration: 2.3, amp: 0.5)        // tension into impact
            whoosh(at: strikeT - 0.45, rising: true, duration: 0.5)
            boom(at: strikeT, amp: 0.95, duration: 1.8)              // IMPACT
            crash(at: strikeT, amp: 0.4)
            drone(.a1, from: strikeT + 0.6, for: duration - strikeT - 0.6, amp: 0.12)
            drone(.a2, from: strikeT + 0.7, for: duration - strikeT - 0.7, amp: 0.045)
        }
    }

    @MainActor
    public static func body(at t: Double, duration: Double, props p: TrialData) -> some View {
        let n = max(p.meta.n, 2)
        let intro = Ease.easeOut(Ease.clip(t, 0.2, 1.9))
        let tE0 = 3.0, tE1 = 16.2
        let engP = Ease.easeInOut(Ease.clip(t, tE0, tE1))
        let f = engP * Double(n - 1)
        let idx = min(Int(f), n - 2)
        let frac = f - Double(idx)
        func L(_ a: [Double]) -> Double {
            if a.isEmpty { return 0 }
            let i = min(idx, a.count - 1), j = min(idx + 1, a.count - 1)
            return frac.lerp(a[i], a[j])
        }
        let curR = L(p.R), curVc = L(p.vc), curTgo = L(p.tgo), curOm = L(p.omega)
        let lockedNow = p.locked[min(idx, p.locked.count - 1)] == 1
        let started = t > tE0 - 0.4
        let strike = Ease.clip(t, tE1 - 0.18, tE1 + 0.55)
        let outro = Ease.easeOut(Ease.clip(t, tE1 + 0.7, tE1 + 1.8))
        let titleFade = intro * (1.0 - Ease.clip(t, tE0 - 0.3, tE0 + 0.3))

        return Canvas { ctx, size in
            let W = size.width, H = size.height
            let eye = CGRect(x: W * 0.035, y: H * 0.150, width: W * 0.605, height: H * 0.79)
            let fpv = CGRect(x: W * 0.665, y: H * 0.150, width: W * 0.300, height: H * 0.350)
            let hud = CGRect(x: W * 0.665, y: H * 0.540, width: W * 0.300, height: H * 0.400)

            drawBackground(ctx, W: W, H: H, t: t, vis: intro)
            drawPanel(ctx, eye, label: "TACTICAL // GOD'S-EYE", vis: intro)
            drawPanel(ctx, fpv, label: "SEEKER // EO", vis: intro)
            drawPanel(ctx, hud, label: "FIRE CONTROL", vis: intro)

            if started {
                drawGodsEye(ctx, rect: eye, p: p, upto: idx, frac: frac)
                drawFPV(ctx, rect: fpv, az: L(p.az), el: L(p.el),
                        fsize: L(p.fsize), locked: lockedNow, strike: strike)
                drawHUD(ctx, rect: hud, R: curR, vc: curVc, tgo: curTgo, om: curOm,
                        r0: p.meta.r0, locked: lockedNow, terminal: strike > 0)
            }
            drawChrome(ctx, W: W, H: H, meta: p.meta, vis: intro, engP: engP)
            drawStrike(ctx, rect: eye, fpv: fpv, p: p, k: strike)
            drawTitle(ctx, W: W, H: H, vis: titleFade)
            drawOutro(ctx, W: W, H: H, meta: p.meta, vis: outro)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
    }

    // MARK: background grid + scan
    static func drawBackground(_ ctx: GraphicsContext, W: CGFloat, H: CGFloat,
                               t: Double, vis: Double) {
        var c = ctx
        c.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(bg))
        c.opacity = 0.06 * vis
        let g = 64.0
        var grid = Path()
        var x = 0.0; while x < W { grid.move(to: .init(x: x, y: 0)); grid.addLine(to: .init(x: x, y: H)); x += g }
        var y = 0.0; while y < H { grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: W, y: y)); y += g }
        c.stroke(grid, with: .color(cyan), lineWidth: 1)
        // slow scan sweep
        let sweep = (t.truncatingRemainder(dividingBy: 6.0)) / 6.0
        c.opacity = 0.05 * vis
        let sx = CGFloat(sweep) * W
        c.fill(Path(CGRect(x: sx - 80, y: 0, width: 160, height: H)),
               with: .linearGradient(.init(colors: [.clear, cyan.opacity(0.5), .clear]),
                                     startPoint: .init(x: sx - 80, y: 0),
                                     endPoint: .init(x: sx + 80, y: 0)))
    }

    // MARK: panel chrome (border + corner brackets + label)
    static func drawPanel(_ ctx: GraphicsContext, _ r: CGRect, label: String, vis: Double) {
        var c = ctx
        c.opacity = 0.5 * vis
        c.stroke(Path(r), with: .color(cyan.opacity(0.25)), lineWidth: 1)
        c.opacity = vis
        let L: CGFloat = 16
        for (cx, cy, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0),
                                 (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            var b = Path()
            b.move(to: .init(x: cx + L * dx, y: cy)); b.addLine(to: .init(x: cx, y: cy))
            b.addLine(to: .init(x: cx, y: cy + L * dy))
            c.stroke(b, with: .color(cyan), lineWidth: 1.5)
        }
        c.draw(Text(label).font(mono(11, .semibold)).foregroundColor(cyan.opacity(0.8)),
               at: .init(x: r.minX + 22, y: r.minY - 11), anchor: .leading)
    }

    // MARK: god's-eye trajectories + markers + LOS
    static func drawGodsEye(_ ctx: GraphicsContext, rect r: CGRect, p: TrialData,
                            upto: Int, frac: Double) {
        var c = ctx
        c.clip(to: Path(r))
        func ipt(_ xs: [Double], _ ys: [Double], _ i: Int) -> CGPoint {
            .init(x: r.minX + CGFloat(xs[min(i, xs.count-1)]) * r.width,
                  y: r.minY + CGFloat(ys[min(i, ys.count-1)]) * r.height)
        }
        func curPt(_ xs: [Double], _ ys: [Double]) -> CGPoint {
            let a = ipt(xs, ys, upto), b = ipt(xs, ys, min(upto + 1, xs.count - 1))
            return .init(x: a.x + (b.x - a.x) * frac, y: a.y + (b.y - a.y) * frac)
        }
        func trail(_ xs: [Double], _ ys: [Double], _ col: Color) {
            guard upto >= 1 else { return }
            var path = Path(); path.move(to: ipt(xs, ys, 0))
            for i in 1...upto { path.addLine(to: ipt(xs, ys, i)) }
            path.addLine(to: curPt(xs, ys))
            c.drawLayer { l in
                l.addFilter(.blur(radius: 7))
                l.stroke(path, with: .color(col.opacity(0.6)),
                         style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            c.stroke(path, with: .color(col),
                     style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        // faint range rings around current target
        let ip = curPt(p.iE, p.iN), tp = curPt(p.tE, p.tN)
        c.opacity = 0.5
        // LOS line (dashed)
        var los = Path(); los.move(to: ip); los.addLine(to: tp)
        c.stroke(los, with: .color(white.opacity(0.55)),
                 style: .init(lineWidth: 1, dash: [5, 5]))
        c.opacity = 1
        trail(p.tE, p.tN, amber)
        trail(p.iE, p.iN, cyan)
        // markers
        marker(c, at: tp, color: amber, diamond: true)
        marker(c, at: ip, color: cyan, diamond: false,
               heading: angle(curPt(p.iE, p.iN), ipt(p.iE, p.iN, max(upto - 2, 0))))
        // range tag on LOS midpoint
        let mid = CGPoint(x: (ip.x + tp.x)/2, y: (ip.y + tp.y)/2 - 12)
        c.draw(Text(String(format: "%.0f m", p.R[min(upto, p.R.count-1)]))
                .font(mono(11)).foregroundColor(white.opacity(0.7)), at: mid)
    }

    static func angle(_ a: CGPoint, _ b: CGPoint) -> Double { atan2(a.y - b.y, a.x - b.x) }

    static func marker(_ ctx: GraphicsContext, at pt: CGPoint, color: Color,
                       diamond: Bool, heading: Double = 0) {
        let c = ctx
        c.drawLayer { l in
            l.addFilter(.blur(radius: 6))
            l.fill(Path(ellipseIn: CGRect(x: pt.x-7, y: pt.y-7, width: 14, height: 14)),
                   with: .color(color.opacity(0.7)))
        }
        var s = Path()
        if diamond {
            s.move(to: .init(x: pt.x, y: pt.y-8)); s.addLine(to: .init(x: pt.x+8, y: pt.y))
            s.addLine(to: .init(x: pt.x, y: pt.y+8)); s.addLine(to: .init(x: pt.x-8, y: pt.y)); s.closeSubpath()
        } else {
            // triangle pointing along heading
            for (i, ang) in [0.0, 2.4, -2.4].enumerated() {
                let a = heading + ang
                let pt2 = CGPoint(x: pt.x + cos(a) * (i == 0 ? 11 : 8), y: pt.y + sin(a) * (i == 0 ? 11 : 8))
                if i == 0 { s.move(to: pt2) } else { s.addLine(to: pt2) }
            }
            s.closeSubpath()
        }
        c.fill(s, with: .color(color))
        c.stroke(Path(ellipseIn: CGRect(x: pt.x-13, y: pt.y-13, width: 26, height: 26)),
                 with: .color(color.opacity(0.5)), lineWidth: 1)
    }

    // MARK: seeker FPV
    static func drawFPV(_ ctx: GraphicsContext, rect r: CGRect, az: Double, el: Double,
                        fsize: Double, locked: Bool, strike: Double) {
        var c = ctx
        c.clip(to: Path(r))
        c.fill(Path(r), with: .color(Color(red: 0.03, green: 0.06, blue: 0.09)))
        // scanlines
        c.opacity = 0.10
        var sl = Path(); var y = r.minY; while y < r.maxY { sl.move(to: .init(x: r.minX, y: y)); sl.addLine(to: .init(x: r.maxX, y: y)); y += 3 }
        c.stroke(sl, with: .color(cyan), lineWidth: 0.5)
        c.opacity = 1
        let cx = r.midX, cy = r.midY
        // crosshair
        var cross = Path()
        cross.move(to: .init(x: cx-40, y: cy)); cross.addLine(to: .init(x: cx-8, y: cy))
        cross.move(to: .init(x: cx+8, y: cy)); cross.addLine(to: .init(x: cx+40, y: cy))
        cross.move(to: .init(x: cx, y: cy-40)); cross.addLine(to: .init(x: cx, y: cy-8))
        cross.move(to: .init(x: cx, y: cy+8)); cross.addLine(to: .init(x: cx, y: cy+40))
        c.stroke(cross, with: .color(cyan.opacity(0.4)), lineWidth: 1)
        // target position from bearing (stylized scale)
        let tx = cx + CGFloat(az / 25.0) * r.width * 0.42
        let ty = cy - CGFloat(el / 18.0) * r.height * 0.42
        let half = CGFloat(max(fsize, 0.04)) * r.height * 0.55
        let boxColor = locked ? green : amber
        // target body
        c.drawLayer { l in
            l.addFilter(.blur(radius: 3))
            l.fill(Path(ellipseIn: CGRect(x: tx-half*0.4, y: ty-half*0.4, width: half*0.8, height: half*0.8)),
                   with: .color(amber.opacity(0.55)))
        }
        // lock box corners
        let bx = CGRect(x: tx-half, y: ty-half, width: half*2, height: half*2)
        let cl: CGFloat = max(6, half*0.4)
        for (px, py, dx, dy) in [(bx.minX, bx.minY, 1.0, 1.0), (bx.maxX, bx.minY, -1.0, 1.0),
                                 (bx.minX, bx.maxY, 1.0, -1.0), (bx.maxX, bx.maxY, -1.0, -1.0)] {
            var br = Path()
            br.move(to: .init(x: px + cl*dx, y: py)); br.addLine(to: .init(x: px, y: py))
            br.addLine(to: .init(x: px, y: py + cl*dy))
            c.stroke(br, with: .color(boxColor), lineWidth: 2)
        }
        c.draw(Text(locked ? "● LOCK" : "◇ TRACK").font(mono(11, .bold)).foregroundColor(boxColor),
               at: .init(x: bx.minX, y: bx.minY - 9), anchor: .leading)
        // white-out on strike
        if strike > 0 {
            c.opacity = min(1, strike * 1.6)
            c.fill(Path(r), with: .color(.white))
        }
    }

    // MARK: fire-control HUD
    static func drawHUD(_ ctx: GraphicsContext, rect r: CGRect, R: Double, vc: Double,
                        tgo: Double, om: Double, r0: Double, locked: Bool, terminal: Bool) {
        let c = ctx
        let rows: [(String, String, Color)] = [
            ("RANGE", String(format: "%.0f", R) + " m", white),
            ("CLOSING VEL", String(format: "%.0f", vc) + " m/s", cyan),
            ("T-INTERCEPT", String(format: "%.2f", tgo) + " s", cyan),
            ("LOS RATE", String(format: "%.3f", om) + " rad/s", white),
        ]
        var y = r.minY + 34
        for (k, v, col) in rows {
            c.draw(Text(k).font(mono(11)).foregroundColor(cyan.opacity(0.6)),
                   at: .init(x: r.minX + 18, y: y), anchor: .leading)
            c.draw(Text(v).font(mono(26, .semibold)).foregroundColor(col),
                   at: .init(x: r.minX + 18, y: y + 22), anchor: .leading)
            y += 64
        }
        // status
        let st = terminal ? "INTERCEPT" : (locked ? "LOCK" : "TRACK")
        let sc = terminal ? green : (locked ? green : amber)
        let sr = CGRect(x: r.minX + 16, y: r.maxY - 46, width: r.width - 32, height: 30)
        c.fill(Path(roundedRect: sr, cornerRadius: 3), with: .color(sc.opacity(0.15)))
        c.stroke(Path(roundedRect: sr, cornerRadius: 3), with: .color(sc), lineWidth: 1)
        c.draw(Text("STATUS  " + st).font(mono(15, .bold)).foregroundColor(sc),
               at: .init(x: sr.midX, y: sr.midY))
        // range bar
        let frac = max(0, min(1, R / max(r0, 1)))
        let barY = r.minY + 4 + 64 * 4 + 6
        let bw = r.width - 36
        c.fill(Path(roundedRect: CGRect(x: r.minX+18, y: barY, width: bw, height: 4), cornerRadius: 2),
               with: .color(cyan.opacity(0.15)))
        c.fill(Path(roundedRect: CGRect(x: r.minX+18, y: barY, width: bw*CGFloat(frac), height: 4), cornerRadius: 2),
               with: .color(cyan))
    }

    // MARK: top/bottom chrome
    static func drawChrome(_ ctx: GraphicsContext, W: CGFloat, H: CGFloat,
                           meta: TrialMeta, vis: Double, engP: Double) {
        var c = ctx; c.opacity = vis
        c.draw(Text("JETRAY").font(mono(20, .heavy)).foregroundColor(white),
               at: .init(x: W*0.035, y: H*0.075), anchor: .leading)
        c.draw(Text("// COUNTER-UAS INTERCEPT").font(mono(14, .medium)).foregroundColor(cyan.opacity(0.8)),
               at: .init(x: W*0.035 + 96, y: H*0.077), anchor: .leading)
        c.draw(Text("TRAJECTORY TRIAL " + meta.trial + "  ·  " + meta.maneuver + "  ·  EO/IR SEEKER")
                .font(mono(12)).foregroundColor(cyan.opacity(0.6)),
               at: .init(x: W*0.965, y: H*0.077), anchor: .trailing)
        // bottom line
        var bl = Path(); bl.move(to: .init(x: W*0.035, y: H*0.955)); bl.addLine(to: .init(x: W*0.965, y: H*0.955))
        c.opacity = 0.3 * vis
        c.stroke(bl, with: .color(cyan), lineWidth: 1)
        c.opacity = 0.55 * vis
        c.draw(Text("PROPORTIONAL NAVIGATION  ·  STRAPDOWN LOS-RATE SEEKER  ·  PX4 OFFBOARD")
                .font(mono(11)).foregroundColor(cyan), at: .init(x: W*0.035, y: H*0.975), anchor: .leading)
        c.draw(Text(String(format: "T %+05.1f", engP * 4.0)).font(mono(11)).foregroundColor(cyan),
               at: .init(x: W*0.965, y: H*0.975), anchor: .trailing)
    }

    // MARK: strike flash + stamp
    static func drawStrike(_ ctx: GraphicsContext, rect eye: CGRect, fpv: CGRect,
                           p: TrialData, k: Double) {
        guard k > 0 else { return }
        var c = ctx
        let ix = eye.minX + CGFloat(p.iE.last ?? 0.6) * eye.width
        let iy = eye.minY + CGFloat(p.iN.last ?? 0.5) * eye.height
        let rad = CGFloat(Ease.easeOut(k)) * 90
        c.opacity = Double(1 - k)
        c.stroke(Path(ellipseIn: CGRect(x: ix-rad, y: iy-rad, width: rad*2, height: rad*2)),
                 with: .color(.white), lineWidth: 3)
        c.opacity = Double(max(0, 1 - k*1.4))
        c.drawLayer { l in
            l.addFilter(.blur(radius: 12))
            l.fill(Path(ellipseIn: CGRect(x: ix-22, y: iy-22, width: 44, height: 44)), with: .color(.white))
        }
        // INTERCEPT stamp
        if k > 0.25 {
            let a = Ease.easeOut(Ease.clip(k, 0.25, 0.55))
            var cc = ctx; cc.opacity = a
            let bx = CGRect(x: eye.midX-150, y: eye.midY-32, width: 300, height: 64)
            cc.fill(Path(roundedRect: bx, cornerRadius: 4), with: .color(green.opacity(0.12)))
            cc.stroke(Path(roundedRect: bx, cornerRadius: 4), with: .color(green), lineWidth: 1.5)
            cc.draw(Text("INTERCEPT").font(mono(30, .heavy)).foregroundColor(green), at: .init(x: eye.midX, y: eye.midY))
        }
    }

    // MARK: opening title
    static func drawTitle(_ ctx: GraphicsContext, W: CGFloat, H: CGFloat, vis: Double) {
        guard vis > 0.01 else { return }
        var c = ctx; c.opacity = vis
        c.draw(Text("JETRAY").font(.system(size: 92, weight: .heavy, design: .monospaced)).foregroundColor(white),
               at: .init(x: W/2, y: H*0.46))
        c.draw(Text("COUNTER-UAS  INTERCEPT").font(mono(22, .medium)).foregroundColor(cyan),
               at: .init(x: W/2, y: H*0.555))
        c.draw(Text("TRAJECTORY TRIAL 01  ·  WEAVE  ·  HIT-TO-KILL").font(mono(13)).foregroundColor(cyan.opacity(0.6)),
               at: .init(x: W/2, y: H*0.60))
    }

    // MARK: outro stats
    static func drawOutro(_ ctx: GraphicsContext, W: CGFloat, H: CGFloat, meta: TrialMeta, vis: Double) {
        guard vis > 0.01 else { return }
        var c = ctx
        c.opacity = vis * 0.82
        c.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(bg))
        c.opacity = vis
        c.draw(Text(meta.hit ? "TARGET NEUTRALIZED" : "MISS").font(.system(size: 56, weight: .heavy, design: .monospaced))
                .foregroundColor(meta.hit ? green : amber), at: .init(x: W/2, y: H*0.42))
        let stats = String(format: "MISS DISTANCE  %.2f m      CLOSING  %.0f m/s      ENGAGEMENT  %.0f m → 0",
                           meta.miss_m, meta.vc_max, meta.r0)
        c.draw(Text(stats).font(mono(16)).foregroundColor(white.opacity(0.85)), at: .init(x: W/2, y: H*0.52))
        c.draw(Text("JETRAY  //  PROPORTIONAL-NAVIGATION SEEKER").font(mono(12)).foregroundColor(cyan.opacity(0.6)),
               at: .init(x: W/2, y: H*0.58))
    }
}
