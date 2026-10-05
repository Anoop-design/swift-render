import SwiftUI
import SwiftRender

/// Film time is the sole animation clock. Adapt layout per format instead of
/// cropping a portrait movie. Replace this fixture's editorial copy and timing
/// with a storyboard derived from the app's actual value and visual language.
struct FilmScene: View {
    let time: Double
    let duration: Double
    @Environment(\.renderContext) private var context

    var body: some View {
        let phase = time / duration
        let entrance = Ease.easeOut(Ease.clip(phase, 0, 0.12))
        let ending = Ease.easeOut(Ease.clip(phase, 0.73, 0.88))
        let content = AppContent(progress: Ease.clip(phase, 0.12, 0.52))
            .scaleEffect(0.94 + entrance * 0.06)
            .opacity(entrance * (1 - ending))
        let referenceSize = context.isVertical ? CGSize(width: 430, height: 760) : CGSize(width: 980, height: 735)
        let scale = min(context.width / referenceSize.width, context.height / referenceSize.height)

        ZStack {
            Color.black
            ZStack {
                if context.isVertical {
                    VStack(spacing: 38) {
                        headline.opacity(entrance * (1 - ending))
                        content
                    }
                } else {
                    HStack(spacing: 76) {
                        headline.frame(width: 330).opacity(entrance * (1 - ending))
                        content
                    }
                }
                VStack(spacing: 18) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 54, weight: .light))
                    Text("Sample app")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                    Text("Replace with your app’s closing message.")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .opacity(ending)
                .offset(y: (1 - ending) * 14)
            }
            .frame(width: referenceSize.width, height: referenceSize.height)
            .scaleEffect(scale)
        }
        .foregroundStyle(.white)
        .frame(width: context.width, height: context.height)
        .clipped()
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Your app,\nin motion.")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .tracking(-1.5)
            Text("A native rendering starter")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
