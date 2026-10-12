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
    var artURL: URL?

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
    @Published var statusMessage: String?

    private let auth: SpotifyAuth
    private var artTask: Task<Void, Never>?
    private var loadedArtURL: URL?
    private let endpoint = URL(string: "https://api.spotify.com/v1/me/player/currently-playing?additional_types=track")!

    init(auth: SpotifyAuth) {
        self.auth = auth
    }

    func run() async {
        guard !Runtime.isPreview else { return }
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    func clear() {
        artTask?.cancel()
        track = nil
        artwork = nil
        backdrop = nil
        backdropToken = "none"
        palette = .fallback
        idleSince = nil
        statusMessage = nil
        loadedArtURL = nil
    }

    func isCollapsed(at date: Date) -> Bool {
        guard track != nil, track?.isPlaying == false, let idleSince else { return false }
        return date.timeIntervalSince(idleSince) >= Self.idleCollapseInterval
    }

    private func refresh(allowRefresh: Bool = true) async {
        guard let token = await auth.validToken() else {
            if !auth.isSignedIn {
                clear()
            }
            return
        }
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, allowRefresh {
                if await auth.forceRefresh() != nil {
                    await refresh(allowRefresh: false)
                }
                return
            }
            if status == 429 {
                let retry = (response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init) ?? 10
                try? await Task.sleep(nanoseconds: UInt64(max(1, retry) * 1_000_000_000))
                return
            }
            if status == 204 {
                markNotPlaying()
                statusMessage = nil
                return
            }
            guard status == 200 else {
                if track == nil {
                    statusMessage = "Spotify did not answer"
                }
                return
            }
            apply(data)
        } catch {
            if track == nil {
                statusMessage = "Spotify is not reachable"
            }
        }
    }

    private func apply(_ data: Data) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(CurrentlyPlayingPayload.self, from: data) else {
            if track == nil {
                statusMessage = "Spotify did not answer"
            }
            return
        }
        if let kind = payload.currentlyPlayingType, kind != "track" {
            markNotPlaying()
            return
        }
        guard let item = payload.item else {
            markNotPlaying()
            statusMessage = nil
            return
        }
        let artist = item.artists.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
        let identity = item.id ?? "local-\(item.name)-\(artist)"
        let next = NowTrack(
            id: identity,
            title: item.name,
            artist: artist.isEmpty ? "Unknown artist" : artist,
            album: item.album.name,
            durationMS: max(item.durationMs, 1),
            isPlaying: payload.isPlaying,
            progressMS: payload.progressMs ?? 0,
            fetchedAt: Date(),
            artURL: artworkURL(from: item.album.images)
        )
        let changed = track?.id != next.id
        track = next
        statusMessage = nil
        if next.isPlaying {
            idleSince = nil
        } else if changed || idleSince == nil {
            idleSince = Date()
        }
        if changed {
            artwork = nil
            loadedArtURL = nil
        }
        if let url = next.artURL, url != loadedArtURL {
            downloadArt(url: url, trackID: next.id)
        }
    }

    private func markNotPlaying() {
        guard var current = track else { return }
        current.isPlaying = false
        track = current
        if idleSince == nil {
            idleSince = Date()
        }
    }

    private func artworkURL(from images: [SpotifyImage]) -> URL? {
        let parsed: [(Int, URL)] = images.compactMap { image in
            guard let url = URL(string: image.url) else { return nil }
            return (image.width ?? 300, url)
        }
        return parsed.min(by: { abs($0.0 - 320) < abs($1.0 - 320) })?.1
    }

    private func downloadArt(url: URL, trackID: String) {
        artTask?.cancel()
        artTask = Task { @MainActor [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let self else { return }
                guard !Task.isCancelled, self.track?.id == trackID, let image = UIImage(data: data) else {
                    return
                }
                let display = ImageSizing.fitted(image, maxPixel: 640)
                let small = ImageSizing.fitted(image, maxPixel: 64)
                self.artwork = display
                self.backdrop = ImageSizing.blurredBackdrop(from: small)
                self.backdropToken = trackID
                self.palette = PaletteExtractor.extract(from: small)
                self.loadedArtURL = url
            } catch {
                return
            }
        }
    }
}

private struct CurrentlyPlayingPayload: Decodable {
    var isPlaying: Bool
    var progressMs: Int?
    var currentlyPlayingType: String?
    var item: SpotifyItem?
}

private struct SpotifyItem: Decodable {
    var id: String?
    var name: String
    var durationMs: Int
    var artists: [SpotifyArtist]
    var album: SpotifyAlbum
}

private struct SpotifyArtist: Decodable {
    var name: String
}

private struct SpotifyAlbum: Decodable {
    var name: String
    var images: [SpotifyImage]
}

private struct SpotifyImage: Decodable {
    var url: String
    var width: Int?
}
