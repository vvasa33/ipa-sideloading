import Foundation
import UIKit

struct NowTrack: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var durationMS: Int
    var isPlaying: Bool
    var progressMS: Int
    var fetchedAt: Date

    func liveProgressMS(at date: Date) -> Int {
        let duration = max(durationMS, 1)
        guard isPlaying else { return min(max(0, progressMS), duration) }
        let extra = Int(date.timeIntervalSince(fetchedAt) * 1000)
        return min(duration, max(0, progressMS + extra))
    }
}

@MainActor
final class NowPlayingStore: ObservableObject {
    static let idleCollapseInterval: TimeInterval = 10 * 60

    @Published var track: NowTrack?
    @Published var artwork: UIImage?
    @Published var backdrop: UIImage?
    @Published var backdropToken = "none"
    @Published var palette: AlbumPalette = .fallback
    @Published var idleSince: Date?

    func clear() {
        track = nil
        artwork = nil
        backdrop = nil
        backdropToken = "none"
        palette = .fallback
        idleSince = nil
    }

    func isCollapsed(at date: Date) -> Bool {
        guard track != nil, track?.isPlaying == false, let idleSince else { return false }
        return date.timeIntervalSince(idleSince) >= Self.idleCollapseInterval
    }

    func applyRemote(
        name: String,
        artist: String,
        album: String,
        uri: String,
        durationMS: Int,
        positionMS: Int,
        isPaused: Bool
    ) {
        let identity = uri.isEmpty ? "\(name)-\(artist)" : uri
        let changed = track?.id != identity
        track = NowTrack(
            id: identity,
            title: name,
            artist: artist.isEmpty ? "Unknown artist" : artist,
            album: album,
            durationMS: max(durationMS, 1),
            isPlaying: !isPaused,
            progressMS: max(0, positionMS),
            fetchedAt: Date()
        )
        if isPaused {
            if changed || idleSince == nil {
                idleSince = Date()
            }
        } else {
            idleSince = nil
        }
        if changed {
            artwork = nil
        }
    }

    func applyRemoteArtwork(_ image: UIImage, uri: String) {
        let identity = uri.isEmpty ? track?.id : uri
        guard track?.id == identity else { return }
        let display = ImageSizing.fitted(image, maxPixel: 640)
        let small = ImageSizing.fitted(image, maxPixel: 64)
        artwork = display
        backdrop = ImageSizing.blurredBackdrop(from: small)
        backdropToken = identity ?? uri
        palette = PaletteExtractor.extract(from: small)
    }

    func notePlayback(playing: Bool) {
        guard var current = track else { return }
        current.isPlaying = playing
        current.fetchedAt = Date()
        track = current
        if playing {
            idleSince = nil
        } else if idleSince == nil {
            idleSince = Date()
        }
    }
}
