import SwiftUI

struct LyricsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var nowPlaying: NowPlayingStore
    @EnvironmentObject private var lyrics: LyricsStore

    var body: some View {
        switch lyrics.state {
        case .idle:
            Color.clear
        case .loading:
            VStack(alignment: .leading, spacing: 14) {
                SkeletonBlock(height: 22)
                SkeletonBlock(height: 18).padding(.trailing, 48)
                SkeletonBlock(height: 18).padding(.trailing, 80)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .synced(let lines):
            synced(lines)
        case .plain(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        case .missing:
            message("No lyrics")
        case .failed:
            message("Lyrics are not reachable")
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func synced(_ lines: [LyricLine]) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let progress = nowPlaying.track?.liveProgressMS(at: context.date) ?? 0
            let active = lines.last(where: { $0.timeMS <= progress })?.id
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 18) {
                            ForEach(lines) { line in
                                let isActive = line.id == active
                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(.system(size: isActive ? 28 : 22, weight: isActive ? .medium : .regular, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(isActive ? 1 : 0.35))
                                    .scaleEffect(isActive ? 1 : 0.96)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 28)
                                    .id(line.id)
                            }
                        }
                        .padding(.vertical, geo.size.height * 0.36)
                        .padding(.horizontal, 8)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        if let active {
                            proxy.scrollTo(active, anchor: .center)
                        }
                    }
                    .onChange(of: active) { value in
                        guard let value else { return }
                        if reduceMotion {
                            proxy.scrollTo(value, anchor: .center)
                        } else {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                proxy.scrollTo(value, anchor: .center)
                            }
                        }
                    }
                }
            }
            .mask(fadeMask)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLine(lines, active: active))
        }
    }

    private func spokenLine(_ lines: [LyricLine], active: Int?) -> String {
        let text = lines.first(where: { $0.id == active })?.text ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Lyrics" : trimmed
    }

    private var fadeMask: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.18),
                .init(color: .white, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

