import Foundation

enum LyricsState: Equatable {
    case idle
    case loading
    case synced([LyricLine])
    case plain(String)
    case missing
    case failed
}

@MainActor
final class LyricsStore: ObservableObject {
    @Published private(set) var state: LyricsState = .idle

    private var generation = 0

    func load(for track: NowTrack?) {
        generation += 1
        let token = generation
        guard let track else {
            state = .idle
            return
        }
        if let cached = readCache(id: track.id) {
            state = cached
            return
        }
        state = .loading
        Task {
            let result = await fetch(track)
            guard token == generation else { return }
            state = result
            if case .synced = result {
                writeCache(result, id: track.id)
            } else if case .plain = result {
                writeCache(result, id: track.id)
            }
        }
    }

    private func fetch(_ track: NowTrack) async -> LyricsState {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(max(1, track.durationMS / 1000))),
        ]
        guard let url = components?.url else { return .failed }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("iPadControlCenter/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                return .missing
            }
            guard status == 200 else { return .failed }
            let payload = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
            return classify(payload)
        } catch {
            return .failed
        }
    }

    private func classify(_ payload: LRCLIBResponse) -> LyricsState {
        if let synced = payload.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty {
                return .synced(lines)
            }
        }
        if let plain = payload.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return .plain(plain)
        }
        return .missing
    }

    private func readCache(id: String) -> LyricsState? {
        let url = cacheDirectory.appendingPathComponent("\(safeName(id)).json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data) else {
            return nil
        }
        switch file.kind {
        case "synced":
            return file.lines.isEmpty ? nil : .synced(file.lines)
        case "plain":
            guard let plain = file.plain, !plain.isEmpty else { return nil }
            return .plain(plain)
        default:
            return nil
        }
    }

    private func writeCache(_ state: LyricsState, id: String) {
        let file: CacheFile
        switch state {
        case .synced(let lines):
            file = CacheFile(kind: "synced", lines: lines, plain: nil)
        case .plain(let text):
            file = CacheFile(kind: "plain", lines: [], plain: text)
        default:
            return
        }
        let directory = cacheDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: directory.appendingPathComponent("\(safeName(id)).json"), options: .atomic)
    }

    private var cacheDirectory: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lyrics", isDirectory: true)
    }

    private func safeName(_ id: String) -> String {
        String(id.map { character in
            character.isLetter || character.isNumber || character == "-" ? character : "-"
        })
    }
}

private struct LRCLIBResponse: Decodable {
    var syncedLyrics: String?
    var plainLyrics: String?
    var instrumental: Bool?
}

private struct CacheFile: Codable {
    var kind: String
    var lines: [LyricLine]
    var plain: String?
}
