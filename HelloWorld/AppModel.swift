import SwiftUI

enum Runtime {
    static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

extension View {
    func environment(model: AppModel) -> some View {
        self
            .environmentObject(model.settings)
            .environmentObject(model.auth)
            .environmentObject(model.nowPlaying)
            .environmentObject(model.lyrics)
            .environmentObject(model.calendar)
            .environmentObject(model.stats)
            .environmentObject(model.focus)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var spotifyClientID: String {
        didSet { UserDefaults.standard.set(spotifyClientID, forKey: Keys.clientID) }
    }

    @Published var ubuntuHost: String {
        didSet { UserDefaults.standard.set(ubuntuHost, forKey: Keys.host) }
    }

    @Published var ubuntuPort: String {
        didSet { UserDefaults.standard.set(ubuntuPort, forKey: Keys.port) }
    }

    init() {
        let defaults = UserDefaults.standard
        spotifyClientID = defaults.string(forKey: Keys.clientID) ?? ""
        ubuntuHost = defaults.string(forKey: Keys.host) ?? ""
        ubuntuPort = defaults.string(forKey: Keys.port) ?? "8765"
    }

    var trimmedClientID: String {
        spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var statsURL: URL? {
        var host = ubuntuHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        if host.hasPrefix("https://") {
            host.removeFirst("https://".count)
        } else if host.hasPrefix("http://") {
            host.removeFirst("http://".count)
        }
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        if host.filter({ $0 == ":" }).count == 1, let colon = host.firstIndex(of: ":") {
            let suffix = host[host.index(after: colon)...]
            if Int(suffix) != nil {
                host = String(host[..<colon])
            }
        }
        guard !host.isEmpty else { return nil }
        let digits = ubuntuPort.filter(\.isNumber)
        let port = Int(digits) ?? 8765
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/stats"
        return components.url
    }

    private enum Keys {
        static let clientID = "ipadcc.spotifyClientID"
        static let host = "ipadcc.ubuntuHost"
        static let port = "ipadcc.ubuntuPort"
    }
}

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let auth: SpotifyAuth
    let nowPlaying: NowPlayingStore
    let lyrics: LyricsStore
    let calendar: CalendarStore
    let stats: StatsStore
    let focus: FocusTimer

    init() {
        let settings = AppSettings()
        let auth = SpotifyAuth(settings: settings)
        self.settings = settings
        self.auth = auth
        self.nowPlaying = NowPlayingStore(auth: auth)
        self.lyrics = LyricsStore()
        self.calendar = CalendarStore()
        self.stats = StatsStore(settings: settings)
        self.focus = FocusTimer()
    }
}
