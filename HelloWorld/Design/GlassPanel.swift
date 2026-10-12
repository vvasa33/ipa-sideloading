import SwiftUI

enum Theme {
    /// Panels use 28. Buttons, fields, and artwork use 14.
    static let panelRadius: CGFloat = 28
    static let controlRadius: CGFloat = 14
    static let ink = Color(red: 0.08, green: 0.07, blue: 0.18)
}

/// Translucent color over the backdrop. No stroke, so the panel does not read as a bordered box.
struct GlassPanel<Content: View>: View {
    var tint: Color
    private let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if reduceTransparency {
                    shape.fill(tint.opacity(0.88))
                } else {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(tint.opacity(0.46))
                        shape.fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    }
                }
            }
            .clipShape(shape)
            .shadow(color: tint.opacity(0.38), radius: 28, y: 14)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SolidButton: View {
    var title: String
    var compact: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 15 : 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, compact ? 10 : 16)
                .padding(.vertical, compact ? 8 : 11)
                .frame(maxWidth: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

struct GhostButton: View {
    var title: String
    var compact: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 15 : 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, compact ? 10 : 16)
                .padding(.vertical, compact ? 8 : 11)
                .frame(maxWidth: .infinity)
                .background(
                    Color(red: 0.10, green: 0.11, blue: 0.13),
                    in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.42), lineWidth: 1)
                }
        }
        .buttonStyle(PressStyle())
    }
}

struct SkeletonBlock: View {
    var height: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(dim || reduceMotion ? 0.10 : 0.18))
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}
