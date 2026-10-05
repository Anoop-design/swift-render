import SwiftUI

/// Original, generic fixture proving the render pipeline. This is not a source
/// adapter for an existing app. Replace this component with selected real app
/// views, their dependencies and assets, and record those sources in provenance.
/// Keep business services outside this target; inject deterministic fixture data.
struct AppContent: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: "square.stack.3d.up")
                Text("Sample app").fontWeight(.semibold)
                Spacer()
            }
            .font(.system(size: 17, design: .rounded))
            .foregroundStyle(.white.opacity(0.68))

            Text("Ideas worth\nkeeping.")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .tracking(-1.1)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                Text("PROJECT NOTES")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.5))
                ForEach(Array(["Collect the idea", "Make it tangible", "Share the result"].enumerated()), id: \.offset) { index, title in
                    let reveal = min(1, max(0, (progress - Double(index) * 0.12) / 0.35))
                    HStack(spacing: 12) {
                        Image(systemName: "circle.inset.filled")
                            .foregroundStyle(Color(red: 0.57, green: 0.76, blue: 0.72))
                        Text(title).font(.system(size: 17, weight: .medium, design: .rounded))
                    }
                    .opacity(reveal)
                    .offset(y: (1 - reveal) * 10)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("03")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 46, alignment: .leading)
                Text("ideas, one place")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(28)
        .frame(width: 350, height: 460, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(Color(white: 0.045), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.13), lineWidth: 1))
    }
}
