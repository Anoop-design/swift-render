import SwiftUI
import AppKit

/// JETRAY — black & white military-demo cut. Real CFD flow-viz + real EO
/// seeker footage as the heroes, restrained instrument HUD, bold condensed
/// type. Reuses TrialData (defined in JETRAYIntercept.swift) for the track plot.
public struct JETRAYBW: PropsScene {
    public static let defaultDuration: Double = 22.0
    public static var ownsPostFX: Bool { false }
    public static var defaultProps: TrialData { JETRAYIntercept.defaultProps }

    static let base = "/Users/sky/swift-render/assets"
    static let white = Color.white
    static let grey  = Color(white: 0.62)

    // Nike-grade condensed type (falls back to system if unavailable)
    static func cond(_ s: CGFloat) -> Font { .custom("AvenirNextCondensed-Heavy", size: s) }
    static func condM(_ s: CGFloat) -> Font { .custom("AvenirNextCondensed-Medium", size: s) }
    static func mono(_ s: CGFloat) -> Font { .system(size: s, weight: .medium, design: .monospaced) }

    static func disk(_ path: String) -> Image {
        if let ns = NSImage(contentsOfFile: path) { return Image(nsImage: ns) }
        return Image(systemName: "square")
    }

    public static func soundtrack(duration: Double) -> Score? {
        let strikeT = 16.9
        return Score(duration: duration) {
            drone(.a1, from: 0.0, for: strikeT, amp: 0.15)
            drone(.e1, from: 3.0, for: strikeT - 3.0, amp: 0.075)
            drone(.a2, from: 6.9, for: strikeT - 6.9, amp: 0.045)
            hat(at: 8.0, pan: -0.3); hat(at: 10.0, pan: 0.3); hat(at: 12.0, pan: -0.3); hat(at: 14.0, pan: 0.3)
            riser(at: strikeT - 2.4, duration: 2.4, amp: 0.5)
            whoosh(at: strikeT - 0.4, rising: true, duration: 0.45)
            boom(at: strikeT, amp: 0.95, duration: 1.9)
            crash(at: strikeT, amp: 0.38)
            drone(.a1, from: strikeT + 0.6, for: duration - strikeT - 0.6, amp: 0.12)
        }
    }

    @MainActor
    public static func body(at t: Double, duration: Double, props p: TrialData) -> some View {
        // phase windows
        let intro  = Ease.clip(t, 0.0, 2.7)
        let plateW = Ease.clip(t, 2.7, 6.9)
        let seekW0 = 6.9, seekW1 = 16.9
        let seekP  = Ease.clip(t, seekW0, seekW1)
        let flash  = Ease.clip(t, seekW1 - 0.12, seekW1 + 0.5)
        let result = Ease.clip(t, seekW1 + 0.5, duration)

        // synth telemetry consistent with the looming footage
        let rng = 250.0 * pow(1.0 - seekP, 1.25) + 3.0
        let clv = 62.0 + 24.0 * seekP
        let tgo = max(0.0, rng / max(clv, 1))

        return Canvas { ctx, size in
            let W = size.width, H = size.height
            let c = ctx
            c.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(.black))

            // ---- HERO IMAGERY (drawn first, behind HUD) --------------------
            // P2 platform: CFD flow-viz, slow push
            if plateW > 0 && seekP <= 0 {
                let a = Ease.easeOut(Ease.clip(t, 2.7, 3.6)) * (1 - Ease.easeIn(Ease.clip(t, 6.4, 6.9)))
                let sc = 1.02 + 0.06 * plateW
                let img = disk(base + "/plate/hero.png")
                var ci = c; ci.opacity = a * 0.95
                let iw = W * sc, ih = iw * 0.5
                ci.draw(ci.resolve(img), in: CGRect(x: (W-iw)/2, y: H*0.40 - ih/2, width: iw, height: ih))
            }
            // P3-5 seeker footage: drone far -> close
            if seekP > 0 {
                let n = 480
                let fi = max(1, min(n, Int(seekP * Double(n - 1)) + 1))
                let img = disk(String(format: "%@/seeker/%04d.png", base, fi))
                var ci = c
                ci.opacity = (1 - flash) * Ease.easeOut(Ease.clip(t, seekW0, seekW0 + 0.5))
                let iw = W, ih = iw * 624.0 / 1280.0
                ci.draw(ci.resolve(img), in: CGRect(x: 0, y: (H - ih)/2, width: iw, height: ih))
            }

            // ---- LETTERBOX (always) ---------------------------------------
            let bar = H * 0.085
            c.fill(Path(CGRect(x: 0, y: 0, width: W, height: bar)), with: .color(.black))
            c.fill(Path(CGRect(x: 0, y: H - bar, width: W, height: bar)), with: .color(.black))

            // ---- HUD over seeker -------------------------------------------
            if seekP > 0.01 && flash < 0.5 {
                drawSeekerHUD(c, W: W, H: H, bar: bar, rng: rng, clv: clv, tgo: tgo,
                              seekP: seekP, t: t, p: p)
            }

            // ---- platform caption ------------------------------------------
            if plateW > 0.05 && seekP <= 0 {
                let a = Ease.easeOut(Ease.clip(t, 3.3, 4.0)) * (1 - Ease.easeIn(Ease.clip(t, 6.3, 6.8)))
                var cc = c; cc.opacity = a
                cc.draw(Text("JETRAY").font(cond(38)).tracking(2).foregroundColor(white),
                        at: .init(x: W*0.06, y: H*0.80), anchor: .leading)
                cc.draw(Text("THRUST-BORNE INTERCEPTOR — 65 M/S — CFD VALIDATED")
                        .font(mono(13)).tracking(2).foregroundColor(grey),
                        at: .init(x: W*0.06, y: H*0.845), anchor: .leading)
            }

            // ---- intro title ------------------------------------------------
            if intro > 0.01 && plateW < 0.3 {
                let a = Ease.easeOut(Ease.clip(t, 0.15, 0.9)) * (1 - Ease.easeIn(Ease.clip(t, 2.3, 2.7)))
                var cc = c; cc.opacity = a
                cc.draw(Text("JETRAY").font(cond(150)).tracking(4).foregroundColor(white),
                        at: .init(x: W/2, y: H*0.46))
                cc.draw(Text("AUTONOMOUS  COUNTER-UAS  INTERCEPTOR")
                        .font(mono(16)).tracking(6).foregroundColor(grey),
                        at: .init(x: W/2, y: H*0.57))
            }

            // ---- strike flash ----------------------------------------------
            if flash > 0 {
                var cc = c
                cc.opacity = Double(flash < 0.5 ? flash * 2 : (1 - flash) * 2)
                cc.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(.white))
            }

            // ---- result card -----------------------------------------------
            if result > 0.01 {
                let a = Ease.easeOut(Ease.clip(t, seekW1 + 0.55, seekW1 + 1.2))
                var cc = c; cc.opacity = a
                cc.draw(Text("TARGET NEUTRALIZED").font(cond(78)).tracking(3).foregroundColor(white),
                        at: .init(x: W/2, y: H*0.42))
                cc.draw(Text(String(format: "MISS  %.2f M      Pk  100%%      CLOSURE  %.0f M/S", p.meta.miss_m, p.meta.vc_max))
                        .font(mono(16)).tracking(3).foregroundColor(grey),
                        at: .init(x: W/2, y: H*0.515))
                // thin rule
                var rule = Path(); rule.move(to: .init(x: W*0.36, y: H*0.475)); rule.addLine(to: .init(x: W*0.64, y: H*0.475))
                cc.opacity = a * 0.5
                cc.stroke(rule, with: .color(white), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: seeker HUD (restrained, instrument-like)
    static func drawSeekerHUD(_ ctx: GraphicsContext, W: CGFloat, H: CGFloat, bar: CGFloat,
                              rng: Double, clv: Double, tgo: Double, seekP: Double,
                              t: Double, p: TrialData) {
        var c = ctx
        let m: CGFloat = W * 0.045
        let top = bar + 26, bot = H - bar - 22
        // dark scrims so the HUD stays legible over a bright EO sky
        c.fill(Path(CGRect(x: 0, y: bar, width: W, height: 160)),
               with: .linearGradient(.init(colors: [.black.opacity(0.82), .clear]),
                                     startPoint: .init(x: 0, y: bar), endPoint: .init(x: 0, y: bar + 160)))
        c.fill(Path(CGRect(x: 0, y: H - bar - 170, width: W, height: 170)),
               with: .linearGradient(.init(colors: [.clear, .black.opacity(0.9)]),
                                     startPoint: .init(x: 0, y: H - bar - 170), endPoint: .init(x: 0, y: H - bar)))
        c.opacity = 0.9
        // top-left / top-right labels
        c.draw(Text("EO SEEKER  //  STRAPDOWN").font(mono(13)).tracking(2).foregroundColor(white),
               at: .init(x: m, y: top), anchor: .leading)
        let locked = seekP > 0.18
        c.draw(Text(locked ? "● LOCK" : "◇ ACQUIRE").font(mono(13)).foregroundColor(white),
               at: .init(x: W - m, y: top), anchor: .trailing)
        // REC + running clock
        c.draw(Text(String(format: "REC  %02d:%05.2f", 0, t)).font(mono(12)).tracking(1).foregroundColor(grey),
               at: .init(x: W - m, y: top + 22), anchor: .trailing)

        // center reticle (drone sits near center in the footage)
        let cx = W*0.5, cy = H*0.5
        var rt = Path()
        rt.move(to: .init(x: cx-46, y: cy)); rt.addLine(to: .init(x: cx-14, y: cy))
        rt.move(to: .init(x: cx+14, y: cy)); rt.addLine(to: .init(x: cx+46, y: cy))
        rt.move(to: .init(x: cx, y: cy-46)); rt.addLine(to: .init(x: cx, y: cy-14))
        rt.move(to: .init(x: cx, y: cy+14)); rt.addLine(to: .init(x: cx, y: cy+46))
        c.opacity = 0.55
        c.stroke(rt, with: .color(white), lineWidth: 1.2)
        // lock brackets that tighten as range closes
        if locked {
            let s = CGFloat(70.0 - 26.0 * seekP)
            let b = CGRect(x: cx - s, y: cy - s, width: s*2, height: s*2)
            let cl: CGFloat = 16
            c.opacity = 0.95
            for (px, py, dx, dy) in [(b.minX,b.minY,1.0,1.0),(b.maxX,b.minY,-1.0,1.0),(b.minX,b.maxY,1.0,-1.0),(b.maxX,b.maxY,-1.0,-1.0)] {
                var br = Path(); br.move(to: .init(x: px+cl*dx, y: py)); br.addLine(to: .init(x: px, y: py)); br.addLine(to: .init(x: px, y: py+cl*dy))
                c.stroke(br, with: .color(white), lineWidth: 2)
            }
            c.draw(Text("HOSTILE").font(mono(11)).tracking(2).foregroundColor(white),
                   at: .init(x: b.minX, y: b.minY - 10), anchor: .leading)
        }

        // bottom telemetry strip
        c.opacity = 0.95
        func stat(_ k: String, _ v: String, _ x: CGFloat) {
            let cc = c
            cc.draw(Text(k).font(mono(11)).tracking(2).foregroundColor(grey), at: .init(x: x, y: bot - 20), anchor: .leading)
            cc.draw(Text(v).font(cond(34)).foregroundColor(white), at: .init(x: x, y: bot + 6), anchor: .leading)
        }
        stat("RANGE", String(format: "%.0f M", rng), m)
        stat("CLOSURE", String(format: "%.0f M/S", clv), m + W*0.16)
        stat("T-IMPACT", String(format: "%.1f S", tgo), m + W*0.32)

        // minimal track-plot inset (thin, bottom-right)
        if seekP > 0.1 {
            let r = CGRect(x: W - m - W*0.20, y: bot - 96, width: W*0.20, height: 84)
            var cc = c; cc.opacity = 0.85
            cc.stroke(Path(r), with: .color(white.opacity(0.3)), lineWidth: 1)
            cc.draw(Text("ENGAGEMENT TRACK").font(mono(9)).tracking(1).foregroundColor(grey),
                    at: .init(x: r.minX + 4, y: r.minY - 7), anchor: .leading)
            let up = min(p.iE.count - 1, Int(seekP * Double(p.iE.count - 1)))
            func poly(_ xs: [Double], _ ys: [Double], _ w: CGFloat) {
                guard up >= 1 else { return }
                var path = Path()
                func pt(_ i: Int) -> CGPoint { .init(x: r.minX + CGFloat(xs[i]) * r.width, y: r.minY + CGFloat(ys[i]) * r.height) }
                path.move(to: pt(0)); for i in 1...up { path.addLine(to: pt(i)) }
                cc.stroke(path, with: .color(white.opacity(w)), lineWidth: 1.3)
            }
            poly(p.tE, p.tN, 0.45)
            poly(p.iE, p.iN, 0.95)
        }
    }
}
