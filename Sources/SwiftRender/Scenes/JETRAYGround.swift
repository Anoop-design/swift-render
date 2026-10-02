import SwiftUI

public struct DemoMeta: Codable {
    public var miss_m: Double; public var vc_max: Double; public var r0: Double
    public var n: Int; public var g_horizon: Double
}
public struct DemoData: Codable {
    public var meta: DemoMeta
    public var ix: [Double]; public var iy: [Double]; public var tx: [Double]; public var ty: [Double]
    public var isz: [Double]; public var tsz: [Double]
    public var fx: [Double]; public var fy: [Double]; public var fsz: [Double]
    public var fhy: [Double]; public var froll: [Double]
    public var R: [Double]; public var vc: [Double]; public var tgo: [Double]
}

/// JETRAY — ground-spotter view of the intercept with the EO seeker FPV in the
/// corner. Both views are the SAME real engagement; the strike syncs.
public struct JETRAYGround: PropsScene {
    public static let defaultDuration: Double = 18.0
    public static var ownsPostFX: Bool { false }
    public static var defaultProps: DemoData {
        DemoData(meta: .init(miss_m: 1.2, vc_max: 83, r0: 266, n: 2, g_horizon: -0.41),
                 ix: [-0.6, 0.1], iy: [0.2, 0.24], tx: [0.25, 0.12], ty: [0.22, 0.24],
                 isz: [0.01, 0.02], tsz: [0.01, 0.02], fx: [-0.1, 0], fy: [0.02, 0],
                 fsz: [0.05, 1.1], fhy: [0, 0], froll: [0, 0], R: [266, 2], vc: [0, 83], tgo: [8, 0.1])
    }
    static let white = Color.white
    static let grey  = Color(white: 0.66)
    static let body  = Color(white: 0.10)
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
    public static func body(at t: Double, duration: Double, props p: DemoData) -> some View {
        let n = max(p.meta.n, 2)
        let title = Ease.clip(t, 0.0, 1.9)
        let e0 = 1.7, e1 = 14.8
        let engP = Ease.easeInOut(Ease.clip(t, e0, e1))
        let f = engP * Double(n - 1); let idx = min(Int(f), n - 2); let frac = f - Double(idx)
        func L(_ a: [Double]) -> Double { let i = min(idx, a.count-1), j = min(idx+1, a.count-1); return frac.lerp(a[i], a[j]) }
        let flash = Ease.clip(t, e1 - 0.10, e1 + 0.5)
        let result = Ease.clip(t, e1 + 0.5, duration)
        let live = t > e0 - 0.2

        return Canvas { ctx, size in
            let W = size.width, H = size.height
            let c = ctx
            // --- MAIN ground-spotter view ---------------------------------
            c.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)),
                   with: .linearGradient(.init(colors: [Color(white: 0.58), Color(white: 0.44)]),
                                         startPoint: .zero, endPoint: .init(x: 0, y: H * 0.7)))
            let hzY = H / 2 - CGFloat(p.meta.g_horizon) * H / 2
            c.fill(Path(CGRect(x: 0, y: hzY, width: W, height: H - hzY)),
                   with: .linearGradient(.init(colors: [Color(white: 0.30), Color(white: 0.16)]),
                                         startPoint: .init(x: 0, y: hzY), endPoint: .init(x: 0, y: H)))
            var hz = Path(); hz.move(to: .init(x: 0, y: hzY)); hz.addLine(to: .init(x: W, y: hzY))
            c.stroke(hz, with: .color(.white.opacity(0.28)), lineWidth: 1)

            func PT(_ xs: [Double], _ ys: [Double], _ i: Int) -> CGPoint {
                .init(x: W/2 + CGFloat(xs[min(i, xs.count-1)]) * W/2, y: H/2 - CGFloat(ys[min(i, ys.count-1)]) * H/2)
            }
            func cur(_ xs: [Double], _ ys: [Double]) -> CGPoint {
                let a = PT(xs, ys, idx), b = PT(xs, ys, min(idx+1, xs.count-1))
                return .init(x: frac.lerp(a.x, b.x), y: frac.lerp(a.y, b.y))
            }

            if live && flash < 0.6 {
                // trails
                func trail(_ xs: [Double], _ ys: [Double], _ col: Color, _ w: CGFloat) {
                    guard idx >= 1 else { return }
                    var path = Path(); path.move(to: PT(xs, ys, 0))
                    for i in 1...idx { path.addLine(to: PT(xs, ys, i)) }
                    path.addLine(to: cur(xs, ys))
                    c.drawLayer { l in l.addFilter(.blur(radius: 4)); l.stroke(path, with: .color(col.opacity(0.5)), style: .init(lineWidth: w+3, lineCap: .round)) }
                    c.stroke(path, with: .color(col), style: .init(lineWidth: w, lineCap: .round, lineJoin: .round))
                }
                trail(p.tx, p.ty, grey, 1.4)
                trail(p.ix, p.iy, white, 2.0)
                let ip = cur(p.ix, p.iy), tp = cur(p.tx, p.ty)
                // LOS
                var los = Path(); los.move(to: ip); los.addLine(to: tp)
                c.stroke(los, with: .color(.white.opacity(0.4)), style: .init(lineWidth: 1, dash: [4, 4]))
                // marks
                mark(c, at: tp, hostile: true,  s: min(max(CGFloat(L(p.tsz))*H*0.5, 4), 7))
                mark(c, at: ip, hostile: false, s: min(max(CGFloat(L(p.isz))*H*0.5, 4), 8))
                if engP < 0.5 {
                    let la = (1 - Ease.clip(engP*2, 0, 1)) * 0.9
                    var cc = c; cc.opacity = la
                    cc.draw(Text("INTERCEPTOR").font(mono(11)).tracking(2).foregroundColor(white), at: .init(x: ip.x + 14, y: ip.y - 14), anchor: .leading)
                    cc.draw(Text("HOSTILE").font(mono(11)).tracking(2).foregroundColor(white), at: .init(x: tp.x + 12, y: tp.y - 14), anchor: .leading)
                }
            }

            let bar = H * 0.085
            if live && flash < 0.6 { drawHUD(c, W: W, H: H, bar: bar, rng: L(p.R), clv: L(p.vc), tgo: L(p.tgo), engP: engP) }

            // --- FPV inset (EO seeker) ------------------------------------
            if live {
                let iw = W * 0.30, ih = iw * 9 / 16
                let r = CGRect(x: W - iw - W*0.03, y: bar + H*0.04, width: iw, height: ih)
                drawFPV(c, rect: r, fx: L(p.fx), fy: L(p.fy), fsz: L(p.fsz), flash: flash, locked: engP > 0.12)
            }

            // letterbox
            c.fill(Path(CGRect(x: 0, y: 0, width: W, height: bar)), with: .color(.black))
            c.fill(Path(CGRect(x: 0, y: H - bar, width: W, height: bar)), with: .color(.black))

            // strike (main): ring + flash
            if flash > 0 {
                let ip = cur(p.ix, p.iy)
                var cc = c; cc.opacity = Double(1 - flash)
                let rad = CGFloat(Ease.easeOut(flash)) * 120
                cc.stroke(Path(ellipseIn: CGRect(x: ip.x-rad, y: ip.y-rad, width: rad*2, height: rad*2)), with: .color(.white), lineWidth: 2.5)
                var c2 = c; c2.opacity = Double(flash < 0.5 ? flash*2 : (1-flash)*2)
                c2.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(.white))
                if flash > 0.25 {
                    var c3 = c; c3.opacity = Ease.easeOut(Ease.clip(flash, 0.25, 0.55))
                    c3.draw(Text("INTERCEPT").font(cond(72)).tracking(4).foregroundColor(.black), at: .init(x: ip.x, y: ip.y - 70))
                }
            }

            // title
            if title > 0.01 && t < 2.0 {
                let a = Ease.easeOut(Ease.clip(t, 0.1, 0.7)) * (1 - Ease.easeIn(Ease.clip(t, 1.4, 1.9)))
                var cc = c; cc.opacity = a
                cc.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(.black.opacity(0.5)))
                cc.opacity = a
                cc.draw(Text("JETRAY").font(cond(120)).tracking(3).foregroundColor(white), at: .init(x: W/2, y: H*0.46))
                cc.draw(Text("COUNTER-UAS  INTERCEPT").font(mono(17)).tracking(7).foregroundColor(grey), at: .init(x: W/2, y: H*0.56))
            }
            // result
            if result > 0.01 {
                let a = Ease.easeOut(Ease.clip(t, e1+0.55, e1+1.2))
                var cc = c; cc.opacity = a
                cc.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(.black))
                cc.opacity = a
                cc.draw(Text("TARGET NEUTRALIZED").font(cond(76)).tracking(3).foregroundColor(white), at: .init(x: W/2, y: H*0.42))
                cc.draw(Text(String(format: "MISS  %.2f M       Pk  100%%       CLOSURE  %.0f M/S", p.meta.miss_m, p.meta.vc_max)).font(mono(16)).tracking(3).foregroundColor(grey), at: .init(x: W/2, y: H*0.515))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    static func mark(_ ctx: GraphicsContext, at pt: CGPoint, hostile: Bool, s: CGFloat) {
        let c = ctx
        c.drawLayer { l in l.addFilter(.blur(radius: 5)); l.fill(Path(ellipseIn: CGRect(x: pt.x-s, y: pt.y-s, width: s*2, height: s*2)), with: .color((hostile ? grey : white).opacity(0.6))) }
        var p = Path()
        if hostile {
            p.move(to: .init(x: pt.x, y: pt.y-s)); p.addLine(to: .init(x: pt.x+s, y: pt.y)); p.addLine(to: .init(x: pt.x, y: pt.y+s)); p.addLine(to: .init(x: pt.x-s, y: pt.y)); p.closeSubpath()
            c.fill(p, with: .color(grey)); c.stroke(p, with: .color(white), lineWidth: 1)
        } else {
            c.fill(Path(ellipseIn: CGRect(x: pt.x-s, y: pt.y-s, width: s*2, height: s*2)), with: .color(white))
        }
        c.stroke(Path(ellipseIn: CGRect(x: pt.x-s*2.2, y: pt.y-s*2.2, width: s*4.4, height: s*4.4)), with: .color((hostile ? white : white).opacity(0.4)), lineWidth: 1)
    }

    static func drawFPV(_ ctx: GraphicsContext, rect r: CGRect, fx: Double, fy: Double, fsz: Double, flash: Double, locked: Bool) {
        var c = ctx
        c.clip(to: Path(r))
        c.fill(Path(r), with: .linearGradient(.init(colors: [Color(white: 0.34), Color(white: 0.20)]), startPoint: .init(x: 0, y: r.minY), endPoint: .init(x: 0, y: r.maxY)))
        let tx = r.midX + CGFloat(fx) * r.width/2, ty = r.midY - CGFloat(fy) * r.height/2
        let s = CGFloat(fsz) * r.height * 0.5
        // drone glyph
        let angs = [Double.pi/4, 3*Double.pi/4, 5*Double.pi/4, 7*Double.pi/4]
        var arms = Path(); for a in angs { arms.move(to: .init(x: tx, y: ty)); arms.addLine(to: .init(x: tx+cos(a)*s, y: ty+sin(a)*s)) }
        c.stroke(arms, with: .color(body), lineWidth: max(1.2, s*0.12))
        for a in angs { let rr = s*0.42; c.fill(Path(ellipseIn: CGRect(x: tx+cos(a)*s-rr, y: ty+sin(a)*s-rr, width: rr*2, height: rr*2)), with: .color(body.opacity(0.92))) }
        // crosshair
        var ch = Path(); ch.move(to: .init(x: r.midX-22, y: r.midY)); ch.addLine(to: .init(x: r.midX-7, y: r.midY)); ch.move(to: .init(x: r.midX+7, y: r.midY)); ch.addLine(to: .init(x: r.midX+22, y: r.midY)); ch.move(to: .init(x: r.midX, y: r.midY-22)); ch.addLine(to: .init(x: r.midX, y: r.midY-7)); ch.move(to: .init(x: r.midX, y: r.midY+7)); ch.addLine(to: .init(x: r.midX, y: r.midY+22))
        c.stroke(ch, with: .color(white.opacity(0.5)), lineWidth: 1)
        // lock box
        let bs = max(s*1.3, 16)
        let b = CGRect(x: tx-bs, y: ty-bs, width: bs*2, height: bs*2); let cl: CGFloat = min(bs*0.4, 12)
        for (px, py, dx, dy) in [(b.minX,b.minY,1.0,1.0),(b.maxX,b.minY,-1.0,1.0),(b.minX,b.maxY,1.0,-1.0),(b.maxX,b.maxY,-1.0,-1.0)] {
            var br = Path(); br.move(to: .init(x: px+cl*dx, y: py)); br.addLine(to: .init(x: px, y: py)); br.addLine(to: .init(x: px, y: py+cl*dy)); c.stroke(br, with: .color(white), lineWidth: 1.5)
        }
        if flash > 0 { var cc = c; cc.opacity = Double(flash < 0.5 ? flash*2 : (1-flash)*2); cc.fill(Path(r), with: .color(.white)) }
        // border + label
        c.stroke(Path(r), with: .color(white.opacity(0.6)), lineWidth: 1.5)
        c.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 22)), with: .color(.black.opacity(0.55)))
        c.draw(Text("EO SEEKER  ·  \(locked ? "LOCK" : "ACQUIRE")").font(mono(11)).tracking(1).foregroundColor(white), at: .init(x: r.minX+8, y: r.minY+11), anchor: .leading)
    }

    static func drawHUD(_ ctx: GraphicsContext, W: CGFloat, H: CGFloat, bar: CGFloat, rng: Double, clv: Double, tgo: Double, engP: Double) {
        let c = ctx
        let m = W*0.045, top = bar+26, bot = H-bar-22
        c.fill(Path(CGRect(x: 0, y: H-bar-150, width: W, height: 150)), with: .linearGradient(.init(colors: [.clear, .black.opacity(0.8)]), startPoint: .init(x: 0, y: H-bar-150), endPoint: .init(x: 0, y: H-bar)))
        c.draw(Text("JETRAY  //  COUNTER-UAS INTERCEPT").font(mono(13)).tracking(2).foregroundColor(white), at: .init(x: m, y: top), anchor: .leading)
        c.draw(Text("GROUND TRACK  +  EO SEEKER").font(mono(12)).tracking(2).foregroundColor(grey), at: .init(x: m, y: top+20), anchor: .leading)
        func stat(_ k: String, _ v: String, _ x: CGFloat) {
            c.draw(Text(k).font(mono(11)).tracking(2).foregroundColor(grey), at: .init(x: x, y: bot-20), anchor: .leading)
            c.draw(Text(v).font(cond(36)).foregroundColor(white), at: .init(x: x, y: bot+7), anchor: .leading)
        }
        stat("RANGE", String(format: "%.0f M", rng), m)
        stat("CLOSURE", String(format: "%.0f M/S", clv), m + W*0.17)
        stat("T-IMPACT", String(format: "%.1f S", tgo), m + W*0.34)
    }
}
