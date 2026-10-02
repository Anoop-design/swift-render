import SwiftUI

public struct ChaseMeta: Codable { public var miss_m: Double; public var vc_max: Double; public var r0: Double; public var n: Int }
public struct ChaseData: Codable {
    public var meta: ChaseMeta
    public var sx: [Double]; public var sy: [Double]; public var size: [Double]
    public var hy: [Double]; public var roll: [Double]
    public var R: [Double]; public var vc: [Double]; public var tgo: [Double]
}

/// JETRAY — track & strike, B&W EO chase/gun-sight view. Camera trails the
/// interceptor; the target stays pinned (proportional navigation) and grows
/// into the lens until impact. Real engagement data via --props chase.json.
public struct JETRAYChase: PropsScene {
    public static let defaultDuration: Double = 18.0
    public static var ownsPostFX: Bool { false }
    public static var defaultProps: ChaseData {
        ChaseData(meta: .init(miss_m: 1.2, vc_max: 83, r0: 266, n: 2),
                  sx: [-0.1, 0], sy: [0.02, 0], size: [0.05, 1.1], hy: [0, 0],
                  roll: [0, 0], R: [266, 2], vc: [0, 83], tgo: [8, 0.1])
    }

    static let white = Color.white
    static let grey  = Color(white: 0.66)
    static let body  = Color(white: 0.10)            // dark drone silhouette
    static func cond(_ s: CGFloat) -> Font { .custom("AvenirNextCondensed-Heavy", size: s) }
    static func mono(_ s: CGFloat) -> Font { .system(size: s, weight: .medium, design: .monospaced) }

    public static func soundtrack(duration: Double) -> Score? {
        let s = 14.8
        return Score(duration: duration) {
            drone(.a1, from: 0, for: s, amp: 0.15)
            drone(.e1, from: 2.0, for: s - 2.0, amp: 0.07)
            hat(at: 4, pan: -0.3); hat(at: 6, pan: 0.3); hat(at: 8, pan: -0.3); hat(at: 10, pan: 0.3); hat(at: 12.3, pan: -0.3)
            riser(at: s - 2.2, duration: 2.2, amp: 0.55)
            whoosh(at: s - 0.4, rising: true, duration: 0.45)
            boom(at: s, amp: 0.97, duration: 1.9)
            crash(at: s, amp: 0.4)
            drone(.a1, from: s + 0.6, for: duration - s - 0.6, amp: 0.12)
        }
    }

    @MainActor
    public static func body(at t: Double, duration: Double, props p: ChaseData) -> some View {
        let n = max(p.meta.n, 2)
        let title = Ease.clip(t, 0.0, 1.9)
        let e0 = 1.7, e1 = 14.8
        let engP = Ease.easeInOut(Ease.clip(t, e0, e1))
        let f = engP * Double(n - 1)
        let idx = min(Int(f), n - 2)
        let frac = f - Double(idx)
        func L(_ a: [Double]) -> Double {
            let i = min(idx, a.count - 1), j = min(idx + 1, a.count - 1)
            return frac.lerp(a[i], a[j])
        }
        let sx = L(p.sx), sy = L(p.sy), sz = L(p.size)
        let hy = L(p.hy), roll = L(p.roll)
        let rng = L(p.R), clv = L(p.vc), tgo = L(p.tgo)
        let flash  = Ease.clip(t, e1 - 0.10, e1 + 0.5)
        let result = Ease.clip(t, e1 + 0.5, duration)
        let live = t > e0 - 0.2 && flash < 0.5

        return Canvas { ctx, size in
            let W = size.width, H = size.height
            var c = ctx
            // ---- EO sky/ground ----------------------------------------------
            c.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)),
                   with: .linearGradient(.init(colors: [Color(white: 0.60), Color(white: 0.40), Color(white: 0.30)]),
                                         startPoint: .zero, endPoint: .init(x: 0, y: H)))
            if t > e0 - 0.2 {
                // banking horizon (tilts with interceptor roll, pitches with hy)
                c.drawLayer { l in
                    l.translateBy(x: W / 2, y: H / 2 + CGFloat(hy) * H * 0.5)
                    l.rotate(by: .radians(roll))
                    l.fill(Path(CGRect(x: -W, y: 0, width: 2 * W, height: H)), with: .color(.black.opacity(0.22)))
                    var hz = Path(); hz.move(to: .init(x: -W, y: 0)); hz.addLine(to: .init(x: W, y: 0))
                    l.stroke(hz, with: .color(.white.opacity(0.32)), lineWidth: 1.5)
                }
            }

            let bar = H * 0.085
            if live {
                // target screen position + the drone silhouette
                let tx = W / 2 + CGFloat(sx) * W / 2
                let ty = H / 2 - CGFloat(sy) * H / 2
                let s = CGFloat(sz) * H * 0.5            // half-span px
                drawDrone(c, at: .init(x: tx, y: ty), s: s)
                // fixed gun-sight crosshair (bore)
                drawBore(c, W: W, H: H)
                // tracking lock box on the target
                drawLock(c, at: .init(x: tx, y: ty), s: max(s * 1.35, 26))
                // HUD
                drawHUD(c, W: W, H: H, bar: bar, rng: rng, clv: clv, tgo: tgo, locked: engP > 0.12)
            }

            // letterbox
            c.fill(Path(CGRect(x: 0, y: 0, width: W, height: bar)), with: .color(.black))
            c.fill(Path(CGRect(x: 0, y: H - bar, width: W, height: bar)), with: .color(.black))

            // ---- title ------------------------------------------------------
            if title > 0.01 && t < 2.0 {
                let a = Ease.easeOut(Ease.clip(t, 0.1, 0.7)) * (1 - Ease.easeIn(Ease.clip(t, 1.4, 1.9)))
                var cc = c; cc.opacity = a
                cc.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(.black.opacity(0.55)))
                cc.opacity = a
                cc.draw(Text("JETRAY").font(cond(120)).tracking(3).foregroundColor(white), at: .init(x: W / 2, y: H * 0.46))
                cc.draw(Text("TRACK   &   STRIKE").font(mono(18)).tracking(8).foregroundColor(grey), at: .init(x: W / 2, y: H * 0.56))
            }

            // ---- strike flash ----------------------------------------------
            if flash > 0 {
                var cc = c
                cc.opacity = Double(flash < 0.5 ? flash * 2 : (1 - flash) * 2)
                cc.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(.white))
            }

            // ---- result -----------------------------------------------------
            if result > 0.01 {
                let a = Ease.easeOut(Ease.clip(t, e1 + 0.55, e1 + 1.2))
                var cc = c; cc.opacity = a
                cc.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(.black))
                cc.opacity = a
                cc.draw(Text("TARGET NEUTRALIZED").font(cond(76)).tracking(3).foregroundColor(white), at: .init(x: W / 2, y: H * 0.42))
                cc.draw(Text(String(format: "MISS  %.2f M       Pk  100%%       CLOSURE  %.0f M/S", p.meta.miss_m, p.meta.vc_max))
                        .font(mono(16)).tracking(3).foregroundColor(grey), at: .init(x: W / 2, y: H * 0.515))
                var rule = Path(); rule.move(to: .init(x: W * 0.37, y: H * 0.475)); rule.addLine(to: .init(x: W * 0.63, y: H * 0.475))
                cc.opacity = a * 0.5; cc.stroke(rule, with: .color(white), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // dark quad-drone silhouette (X config), grows with `s`
    static func drawDrone(_ ctx: GraphicsContext, at cpt: CGPoint, s: CGFloat) {
        var c = ctx
        let angs = [Double.pi / 4, 3 * .pi / 4, 5 * .pi / 4, 7 * .pi / 4]
        var arms = Path()
        for a in angs { arms.move(to: cpt); arms.addLine(to: .init(x: cpt.x + cos(a) * s, y: cpt.y + sin(a) * s)) }
        c.stroke(arms, with: .color(body), lineWidth: max(1.5, s * 0.12))
        let rr = s * 0.42
        for a in angs {
            let rc = CGPoint(x: cpt.x + cos(a) * s, y: cpt.y + sin(a) * s)
            c.fill(Path(ellipseIn: CGRect(x: rc.x - rr, y: rc.y - rr, width: rr * 2, height: rr * 2)), with: .color(body.opacity(0.92)))
            c.stroke(Path(ellipseIn: CGRect(x: rc.x - rr, y: rc.y - rr, width: rr * 2, height: rr * 2)), with: .color(.black.opacity(0.5)), lineWidth: 1)
        }
        c.fill(Path(ellipseIn: CGRect(x: cpt.x - s * 0.32, y: cpt.y - s * 0.32, width: s * 0.64, height: s * 0.64)), with: .color(body))
    }

    static func drawBore(_ ctx: GraphicsContext, W: CGFloat, H: CGFloat) {
        var c = ctx; c.opacity = 0.5
        let cx = W / 2, cy = H / 2
        var p = Path()
        p.move(to: .init(x: cx - 54, y: cy)); p.addLine(to: .init(x: cx - 18, y: cy))
        p.move(to: .init(x: cx + 18, y: cy)); p.addLine(to: .init(x: cx + 54, y: cy))
        p.move(to: .init(x: cx, y: cy - 54)); p.addLine(to: .init(x: cx, y: cy - 18))
        p.move(to: .init(x: cx, y: cy + 18)); p.addLine(to: .init(x: cx, y: cy + 54))
        c.stroke(p, with: .color(white), lineWidth: 1.2)
    }

    static func drawLock(_ ctx: GraphicsContext, at cpt: CGPoint, s: CGFloat) {
        var c = ctx
        let b = CGRect(x: cpt.x - s, y: cpt.y - s, width: s * 2, height: s * 2)
        let cl = min(s * 0.4, 22)
        for (px, py, dx, dy) in [(b.minX, b.minY, 1.0, 1.0), (b.maxX, b.minY, -1.0, 1.0), (b.minX, b.maxY, 1.0, -1.0), (b.maxX, b.maxY, -1.0, -1.0)] {
            var br = Path(); br.move(to: .init(x: px + cl * dx, y: py)); br.addLine(to: .init(x: px, y: py)); br.addLine(to: .init(x: px, y: py + cl * dy))
            c.stroke(br, with: .color(white), lineWidth: 2)
        }
        c.draw(Text("HOSTILE  ·  LOCK").font(mono(11)).tracking(1).foregroundColor(white), at: .init(x: b.minX, y: b.minY - 10), anchor: .leading)
    }

    static func drawHUD(_ ctx: GraphicsContext, W: CGFloat, H: CGFloat, bar: CGFloat,
                        rng: Double, clv: Double, tgo: Double, locked: Bool) {
        var c = ctx
        let m = W * 0.045, top = bar + 26, bot = H - bar - 22
        c.fill(Path(CGRect(x: 0, y: bar, width: W, height: 150)),
               with: .linearGradient(.init(colors: [.black.opacity(0.72), .clear]), startPoint: .init(x: 0, y: bar), endPoint: .init(x: 0, y: bar + 150)))
        c.fill(Path(CGRect(x: 0, y: H - bar - 165, width: W, height: 165)),
               with: .linearGradient(.init(colors: [.clear, .black.opacity(0.85)]), startPoint: .init(x: 0, y: H - bar - 165), endPoint: .init(x: 0, y: H - bar)))
        c.draw(Text("EO SEEKER  //  TRACK & STRIKE").font(mono(13)).tracking(2).foregroundColor(white), at: .init(x: m, y: top), anchor: .leading)
        c.draw(Text(locked ? "● LOCK" : "◇ ACQUIRE").font(mono(13)).foregroundColor(white), at: .init(x: W - m, y: top), anchor: .trailing)
        func stat(_ k: String, _ v: String, _ x: CGFloat) {
            c.draw(Text(k).font(mono(11)).tracking(2).foregroundColor(grey), at: .init(x: x, y: bot - 20), anchor: .leading)
            c.draw(Text(v).font(cond(36)).foregroundColor(white), at: .init(x: x, y: bot + 7), anchor: .leading)
        }
        stat("RANGE", String(format: "%.0f M", rng), m)
        stat("CLOSURE", String(format: "%.0f M/S", clv), m + W * 0.17)
        stat("T-IMPACT", String(format: "%.1f S", tgo), m + W * 0.34)
    }
}
