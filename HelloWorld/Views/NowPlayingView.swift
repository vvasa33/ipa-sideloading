import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @EnvironmentObject private var nowPlaying: NowPlayingStore

    var body: some View {
        GlassPanel(tint: nowPlaying.palette.primary) {
            GeometryReader { geo in
                if let track = nowPlaying.track {
                    populated(track, in: geo)
                } else {
                    empty
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
    }

    private func populated(_ track: NowTrack, in geo: GeometryProxy) -> some View {
        let art = min(300, max(140, geo.size.height - 96))
        return HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                artView(side: art)
                    .opacity(track.isPlaying ? 1 : 0.55)
                Text(track.title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(track.artist)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
                if !track.isPlaying {
                    Text("Paused")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(width: art, alignment: .leading)
            LyricsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
    }

    private func artView(side: CGFloat) -> some View {
        Group {
            if let artwork = nowPlaying.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(nowPlaying.palette.primary.opacity(0.85))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .accessibilityLabel("Album artwork")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing playing")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
            if !auth.isSignedIn {
                Text("Long-press the clock, then sign in to Spotify.")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
            } else if let status = nowPlaying.statusMessage {
                Text(status)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(24)
    }
}
