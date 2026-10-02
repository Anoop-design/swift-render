import SwiftUI

/// Sizzle — a 15-second, beat-synced showcase of swift-render itself.
///
///   swift run swift-render render Sizzle --out out/sizzle.mp4
///
/// Eight bars at 128 BPM (1.875s each). Every cut sits on the beat grid and
/// the soundtrack is declared below from the SAME `chapters` array that drives
/// the Timeline, so the crashes land on the cuts by construction. The scene is
/// audio-reactive to its own synthesized score — `audio.band(.bass, at: t)` is
/// reading the kicks this file wrote.
///
///   bar 0   0.00  hook — typewriter: "every frame is a pure function of t."
///   bar 1   1.88  SWIFT / RENDER slam (two kicks, two slams)
///   bar 2   3.75  REAL METAL — raymarched `metaballs` shader, bass-pumped type
///   bar 3   5.63  ANALYTIC SPRINGS — four easings race
///   bar 4   7.50  3D — rotation3DEffect cards over the `monoTunnel` shader
///   bar 5   9.38  IT HEARS ITS OWN BEAT — FFT bars + bass ring
///   bar 6  11.25  3,450 frames in 29s — odometer under a riser
///   bar 7  13.13  lockup + URL, fade to black
public struct Sizzle: AudioReactiveScene {
    public static let defaultDuration: Double = 15.0
    public static var ownsPostFX: Bool { true }

    static let volt = Color(red: 0.78, green: 1.0, blue: 0.10)
    static let bpm: Double = 128
    static let beat: Double = 60.0 / bpm                       // 0.46875s
    static let bar: Double = beat * 4                          // 1.875s — one chapter
    static let chapters: [Double] = (0...8).map { bar * Double($0) }   // 0 … 15.0

    // MARK: - Soundtrack — same constants as the Timeline, so nothing can drift.

    public static func soundtrack(duration: Double) -> Score? {
        Score(duration: duration) {
            // bar 0: ticking hats under the typewriter, a whoosh into the drop
            every(beat, from: 0, to: chapters[1]) { hat(at: $0, amp: 0.13) }
            every(beat, from: beat / 2, to: chapters[1]) { hat(at: $0, amp: 0.06, pan: 0.5) }
            whoosh(at: chapters[1] - 0.5, rising: true, amp: 0.6, duration: 0.5)

            // bars 1–6: the groove
            boom(at: chapters[1], amp: 0.9, duration: 1.6)
            fourOnFloor(from: chapters[1], to: chapters[7], bpm: bpm)
            hatSixteenths(from: chapters[1], to: chapters[7], bpm: bpm)
            bassline([.a1, .a1, .c2, .g1], from: chapters[1], to: chapters[7], bpm: bpm)
            crashes(at: Array(chapters[1...6]))

            // bar 6 → 7: riser + kick fill into the lockup
            riser(at: chapters[6], duration: bar, amp: 0.6)
            kicks(at: [chapters[7] - beat * 0.75, chapters[7] - beat * 0.5, chapters[7] - beat * 0.25], amp: 0.8)

            // bar 7: the 808 hit and a drone to fade on
            boom(at: chapters[7])
            crash(at: chapters[7], amp: 0.36)
            drone(.a1, from: chapters[7], for: bar, amp: 0.14)
        }
    }

    // MARK: - Body

    @MainActor
    public static func body(at t: Double, duration: Double, audio: AudioTrack) -> some View {
        let bass = audio.band(.bass, at: t)
        let fade = Ease.easeIn(Ease.clip(t, duration - 0.6, duration))

        // Impact shake on every cut + the second title slam; a heavy one on the 808.
        let slams = Array(chapters[1...7]) + [chapters[1] + beat * 2]
        var jolt = JustRenderIt.shake(t, impacts: slams, amp: 12)
        let big = JustRenderIt.shake(t, impacts: [chapters[7]], amp: 28)
        jolt.width += big.width
        jolt.height += big.height

        return ZStack {
            Color.black.ignoresSafeArea()
            Timeline(t) {
                Clip(bar) { l in hook(l) }
                Clip(bar) { l in title(l) }
                Clip(bar) { l in metal(l, bass: bass) }
                Clip(bar) { l in springs(l) }
                Clip(bar) { l in threeD(l) }
                Clip(bar) { l in reactive(l, audio: audio, global: t) }
                Clip(bar) { l in speed(l) }
                Clip(bar) { l in lockup(l) }
                Clip(at: 0, for: duration) { l in hud(l, total: duration) }
            }
            .offset(jolt)
            flash(t)
        }
        .opacity(1 - fade)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PostFX(time: t, grainAmount: 0.10, vignetteAmount: 0.42))
    }

    // MARK: bar 0 · hook

    @ViewBuilder @MainActor
    static func hook(_ t: Double) -> some View {
        let line = "every frame is a pure function of t."
        let typed = Int(Ease.clip(t, 0.1, 1.25) * Double(line.count))
        let cursorOn = Int(t * 6) % 2 == 0
        let lift = Ease.easeIn(Ease.clip(t, 1.45, bar))
        HStack(spacing: 0) {
            Text(String(line.prefix(typed)))
            Text("▌").foregroundStyle(volt).opacity(cursorOn ? 1 : 0)
        }
        .font(.system(size: 56, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.92))
        .scaleEffect(1 + 0.35 * lift)
        .opacity(1 - lift)
        .blur(radius: lift * 12)
    }

    // MARK: bar 1 · title slam

    @ViewBuilder @MainActor
    static func title(_ t: Double) -> some View {
        let s1 = Ease.spring(t, from: 1.7, to: 1.0, response: 0.32, dampingFraction: 0.62)
        let s2 = Ease.spring(max(0, t - beat * 2), from: 1.7, to: 1.0, response: 0.32, dampingFraction: 0.62)
        let show2 = t >= beat * 2
        let rule = Ease.easeOut(Ease.clip(t, beat * 2 + 0.15, beat * 2 + 0.6))
        let tag = Ease.easeOut(Ease.clip(t, beat * 3, beat * 3 + 0.4))
        VStack(alignment: .leading, spacing: -40) {
            Text("SWIFT")
                .font(.system(size: 300, weight: .black)).fontWidth(.condensed)
                .foregroundStyle(.white)
                .scaleEffect(s1, anchor: .leading)
            Text("RENDER")
                .font(.system(size: 300, weight: .black)).fontWidth(.condensed)
                .foregroundStyle(volt)
                .scaleEffect(s2, anchor: .leading)
                .opacity(show2 ? 1 : 0)
            Rectangle().fill(.white)
                .frame(width: 1100 * rule, height: 10)
                .padding(.top, 50)
            Text("SwiftUI scenes + real Metal shaders → MP4")
                .font(.system(size: 40, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .opacity(tag)
                .offset(y: (1 - tag) * 14)
                .padding(.top, 60)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 160)
    }

    // MARK: bar 2 · real metal

    @ViewBuilder @MainActor
    static func metal(_ t: Double, bass: Double) -> some View {
        let inP = Ease.easeOut(Ease.clip(t, 0, 0.35))
        let sub = Ease.easeOut(Ease.clip(t, 0.3, 0.7))
        ZStack {
            Rectangle().fill(.black)
                .colorEffect(ShaderLibrary.bundle(.module).metaballs(
                    .float2(1920, 1080), .float(Float(t * 0.9 + 3.0))))
                .opacity(inP)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Text("REAL METAL.")
                    .font(.system(size: 210, weight: .black)).fontWidth(.condensed)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.85), radius: 30)
                    .scaleEffect(1 + 0.07 * bass)
                Text("18 shaders · .colorEffect · compiled by a SwiftPM plugin")
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
                    .foregroundStyle(volt)
                    .opacity(sub)
            }
        }
    }

    // MARK: bar 3 · springs

    @ViewBuilder @MainActor
    static func springs(_ t: Double) -> some View {
        let curves: [(String, (Double) -> Double)] = [
            ("spring 0.45 / 0.55", { Ease.spring($0, from: 0, to: 1, response: 0.45, dampingFraction: 0.55) }),
            ("easeOutBack",        { Ease.easeOutBack(Ease.clip($0, 0, 0.8)) }),
            ("bounce",             { Ease.bounce(Ease.clip($0, 0, 1.0)) }),
            ("elastic",            { Ease.elastic(Ease.clip($0, 0, 1.1)) }),
        ]
        let head = Ease.easeOut(Ease.clip(t, 0, 0.3))
        VStack(alignment: .leading, spacing: 48) {
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                Text("ANALYTIC SPRINGS")
                    .font(.system(size: 80, weight: .black)).fontWidth(.condensed)
                    .foregroundStyle(.white)
                Text("closed-form · scrub-safe · byte-identical")
                    .font(.system(size: 28, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .opacity(head)
            .offset(x: (1 - head) * -40)
            VStack(spacing: 36) {
                ForEach(0..<curves.count, id: \.self) { i in
                    let v = curves[i].1(max(0, t - 0.2 - Double(i) * 0.1))
                    HStack(spacing: 28) {
                        Text(curves[i].0)
                            .font(.system(size: 24, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 340, alignment: .trailing)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12)).frame(width: 1100, height: 6)
                            Circle().fill(i == 0 ? volt : .white)
                                .frame(width: 36, height: 36)
                                .offset(x: v * 1064)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 160)
    }

    // MARK: bar 4 · 3D

    @ViewBuilder @MainActor
    static func threeD(_ t: Double) -> some View {
        let inP = Ease.easeOut(Ease.clip(t, 0, 0.4))
        let labels = ["t", "→", "View", "→", "MP4"]
        ZStack {
            Rectangle().fill(.black)
                .colorEffect(ShaderLibrary.bundle(.module).monoTunnel(
                    .float2(1920, 1080), .float(Float(t + 1.0))))
                .opacity(0.8 * inP)
                .ignoresSafeArea()
            HStack(spacing: -30) {
                ForEach(0..<5, id: \.self) { i in
                    let p = Ease.spring(max(0, t - 0.1 - Double(i) * 0.08),
                                        from: 0, to: 1, response: 0.55, dampingFraction: 0.7)
                    let angle = (1 - p) * 95 + sin(t * 1.6 + Double(i)) * 8 * p
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.5), lineWidth: 2))
                        .overlay(
                            Text(labels[i])
                                .font(.system(size: 72, weight: .black)).fontWidth(.condensed)
                                .foregroundStyle(i == 4 ? volt : .white)
                        )
                        .frame(width: 300, height: 400)
                        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .opacity(p)
                }
            }
            .rotation3DEffect(.degrees(8), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .offset(y: -40)
            VStack {
                Spacer()
                Text("3D. NO BROWSER. NO CHROMIUM.")
                    .font(.system(size: 56, weight: .black)).fontWidth(.condensed)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.9), radius: 20)
                    .opacity(Ease.easeOut(Ease.clip(t, 0.6, 1.0)))
                    .padding(.bottom, 120)
            }
        }
    }

    // MARK: bar 5 · audio-reactive (reads the scene's own synthesized score)

    @ViewBuilder @MainActor
    static func reactive(_ l: Double, audio: AudioTrack, global t: Double) -> some View {
        let bass = audio.band(.bass, at: t)
        let high = audio.band(.high, at: t)
        let inP = Ease.easeOut(Ease.clip(l, 0, 0.3))
        let text = Ease.easeOut(Ease.clip(l, 0.25, 0.65))
        ZStack {
            Circle()
                .stroke(volt.opacity(0.35 + 0.5 * bass), lineWidth: 3 + 10 * bass)
                .frame(width: 520 + 260 * bass, height: 520 + 260 * bass)
                .blur(radius: 2 + 10 * bass)
                .opacity(inP)
            HStack(alignment: .center, spacing: 14) {
                ForEach(0..<32, id: \.self) { i in
                    let phase = Double(abs(i - 16)) * 0.035
                    let v = audio.level(at: max(0, t - phase))
                    Capsule().fill(i % 4 == 0 ? volt : .white)
                        .frame(width: 26, height: 40 + 560 * v)
                }
            }
            .opacity(0.9 * inP)
            VStack(spacing: 16) {
                Text("IT HEARS ITS OWN BEAT.")
                    .font(.system(size: 96, weight: .black)).fontWidth(.condensed)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.9), radius: 24)
                    .scaleEffect(1 + 0.05 * high)
                Text("audio.band(.bass, at: t)   // FFT once, pure lookup forever")
                    .font(.system(size: 28, design: .monospaced))
                    .foregroundStyle(volt)
                    .shadow(color: .black.opacity(0.9), radius: 12)
            }
            .opacity(text)
        }
    }

    // MARK: bar 6 · speed

    @ViewBuilder @MainActor
    static func speed(_ t: Double) -> some View {
        let p = Ease.easeOut(Ease.clip(t, 0.05, 1.3))
        let frames = Int(p * 3450)
        let secs = p * 29
        let swell = 1 + 0.06 * Ease.clip(t, 0, bar)        // grows under the riser
        let foot = Ease.easeOut(Ease.clip(t, 0.8, 1.2))
        ZStack {
            Rectangle().fill(.black)
                .colorEffect(ShaderLibrary.bundle(.module).neonGrid(
                    .float2(1920, 1080), .float(Float(t * 0.7 + 2.0))))
                .opacity(0.5)
                .ignoresSafeArea()
            HStack(alignment: .firstTextBaseline, spacing: 60) {
                stat(frames.formatted(), "FRAMES")
                Text("in")
                    .font(.system(size: 90, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
                stat(String(format: "%.0fs", secs), "ON A MACBOOK")
            }
            .scaleEffect(swell)
            VStack {
                Spacer()
                Text("1080p60 · ~120 fps · zero dependencies · one Swift file")
                    .font(.system(size: 30, design: .monospaced))
                    .foregroundStyle(volt)
                    .opacity(foot)
                    .padding(.bottom, 130)
            }
        }
    }

    @ViewBuilder @MainActor
    static func stat(_ big: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(big)
                .font(.system(size: 260, weight: .black)).fontWidth(.condensed)
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 20)
            Text(label)
                .font(.system(size: 34, weight: .bold))
                .tracking(8)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: bar 7 · lockup

    @ViewBuilder @MainActor
    static func lockup(_ t: Double) -> some View {
        let s = Ease.spring(t, from: 1.25, to: 1.0, response: 0.4, dampingFraction: 0.6)
        let sub = Ease.easeOut(Ease.clip(t, 0.35, 0.8))
        let foot = Ease.easeOut(Ease.clip(t, 0.7, 1.1))
        VStack(spacing: 26) {
            Text("swift-render")
                .font(.system(size: 170, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(s)
            Text("SwiftUI + Metal  →  MP4")
                .font(.system(size: 40, weight: .medium, design: .monospaced))
                .foregroundStyle(volt)
                .opacity(sub)
                .offset(y: (1 - sub) * 14)
            Text("MIT · zero dependencies · this reel is one Swift file")
                .font(.system(size: 28, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .opacity(foot)
            Text("github.com/skyblanket/swift-render")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .opacity(foot)
                .padding(.top, 20)
        }
    }

    // MARK: pinned HUD + cut flash

    @ViewBuilder @MainActor
    static func hud(_ t: Double, total: Double) -> some View {
        VStack {
            Spacer()
            HStack {
                Text("SIZZLE · 128 BPM · 8 BARS")
                Spacer()
                Text(String(format: "%05.2fs / %04.1fs", t, total))
            }
            .font(.system(size: 17, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 44)
            .padding(.bottom, 16)
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.10)).frame(height: 5)
                Rectangle().fill(volt).frame(width: t / total * 1920, height: 5)
                ForEach(1..<8, id: \.self) { i in
                    Rectangle().fill(.white.opacity(0.5))
                        .frame(width: 2, height: 12)
                        .offset(x: chapters[i] / total * 1920, y: -4)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Two-ish-frame white burst on every cut — the visual side of `crashes(at:)`.
    @MainActor
    static func flash(_ t: Double) -> some View {
        let hit = chapters[1...7].map { max(0, 1 - abs(t - $0) / 0.07) }.max() ?? 0
        return Color.white.opacity(hit * 0.75).ignoresSafeArea()
    }
}
