import SwiftUI

struct FocusCell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var focus: FocusTimer
    @EnvironmentObject private var nowPlaying: NowPlayingStore
    @State private var pulsing = false

    var body: some View {
        GlassPanel(tint: nowPlaying.palette.tertiary) {
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                VStack(spacing: 10) {
                    ring(at: context.date)
                    controls
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .scaleEffect(pulsing ? 1.03 : 1)
        .onChange(of: focus.pulseToken) { _ in
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                pulsing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    pulsing = false
                }
            }
        }
    }

    private func ring(at date: Date) -> some View {
        let fraction = focus.fraction(at: date)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(fraction, focus.phase == .idle ? 0.08 : fraction))
                .stroke(
                    nowPlaying.palette.tertiary,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                if focus.phase == .idle {
                    Text("Focus")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                } else {
                    Text(focus.clockString(focus.remaining(at: date)))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                    Text(focus.phaseTitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(at: date))
    }

    @ViewBuilder
    private var controls: some View {
        switch focus.phase {
        case .idle:
            HStack(spacing: 8) {
                SolidButton(title: "25 / 5", compact: true) {
                    focus.start(focusMinutes: 25, breakMinutes: 5)
                }
                SolidButton(title: "50 / 10", compact: true) {
                    focus.start(focusMinutes: 50, breakMinutes: 10)
                }
            }
        case .focus, .rest:
            HStack(spacing: 8) {
                SolidButton(title: "Pause", compact: true) {
                    focus.pause()
                }
                GhostButton(title: "Stop", compact: true) {
                    focus.stop()
                }
            }
        case .pausedFocus, .pausedRest:
            HStack(spacing: 8) {
                SolidButton(title: "Resume", compact: true) {
                    focus.resume()
                }
                GhostButton(title: "Stop", compact: true) {
                    focus.stop()
                }
            }
        }
    }

    private func accessibilityText(at date: Date) -> String {
        if focus.phase == .idle {
            return "Focus timer"
        }
        return "\(focus.phaseTitle), \(focus.clockString(focus.remaining(at: date))) remaining"
    }
}
