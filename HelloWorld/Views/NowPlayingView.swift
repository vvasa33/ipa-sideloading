import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var nowPlaying: NowPlayingStore
    @EnvironmentObject private var remote: SpotifyRemote

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
                transport
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

    private var transport: some View {
        HStack(spacing: 14) {
            transportButton("backward.fill", "Previous", enabled: remote.isConnected) {
                remote.previous()
            }
            transportButton(nowPlaying.track?.isPlaying == true ? "pause.fill" : "play.fill", nowPlaying.track?.isPlaying == true ? "Pause" : "Play", enabled: true) {
                remote.togglePlayback()
            }
            transportButton("forward.fill", "Next", enabled: remote.isConnected) {
                remote.next()
            }
        }
        .padding(.top, 6)
    }

    private func transportButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing playing")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
            Text(remote.isSignedIn ? "Signed in" : "Not signed in")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))
            Text(remote.lastError ?? remote.statusMessage ?? (remote.spotifyInstalled ? "Open Spotify and start a song." : "Install Spotify on this iPad."))
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
            if remote.spotifyInstalled {
                transport
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(24)
    }
}
