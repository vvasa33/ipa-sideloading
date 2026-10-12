import AuthenticationServices
import CryptoKit
import OSLog
import SpotifyiOS
import UIKit

enum SpotifyConfig {
    static let clientID = "e1fd90a5f8fb4b959df641cbf195ce4e"
    static let redirectURI = "ipadcc://callback"
    static let callbackScheme = "ipadcc"
}

/// Talks to the Spotify app installed on this iPad. Playback stays inside Spotify.
@MainActor
final class SpotifyRemote: NSObject, ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isSignedIn = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var spotifyInstalled = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?

    private let nowPlaying: NowPlayingStore
    private let presenter = WebAuthPresenter()
    private var appRemote: SPTAppRemote?
    private var artworkURI: String?
    private var authSession: ASWebAuthenticationSession?
    private var codeVerifier: String?
    private var expectedState: String?
    private var redeemedCodes = Set<String>()

    init(nowPlaying: NowPlayingStore) {
        self.nowPlaying = nowPlaying
        super.init()
        isSignedIn = savedToken() != nil
        refreshInstallState()
    }

    func signIn() {
        guard !Runtime.isPreview else { return }
        lastError = nil
        let verifier = Self.randomVerifier()
        let state = UUID().uuidString
        codeVerifier = verifier
        expectedState = state
        UserDefaults.standard.set(verifier, forKey: Keys.verifier)
        UserDefaults.standard.set(state, forKey: Keys.state)
        guard let url = authorizeURL(verifier: verifier, state: state) else {
            lastError = "Could not open Spotify sign in."
            SpotifyLog.write("could not build authorize url")
            return
        }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: SpotifyConfig.callbackScheme) { [weak self] callback, error in
            Task { @MainActor in
                guard let self else { return }
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    SpotifyLog.write("web session canceled")
                    if self.authSession != nil, !self.isSignedIn {
                        self.isAuthorizing = false
                    }
                    return
                }
                if let error {
                    SpotifyLog.write("web session error: \(error.localizedDescription)")
                }
                guard let callback else {
                    self.isAuthorizing = false
                    if !self.isSignedIn {
                        self.lastError = "Spotify sign in did not finish."
                    }
                    return
                }
                self.consume(callback, source: "web session")
            }
        }
        session.presentationContextProvider = presenter
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        isAuthorizing = true
        SpotifyLog.write("sign-in started")
        if !session.start() {
            isAuthorizing = false
            lastError = "Could not open Spotify sign in."
            SpotifyLog.write("web session failed to start")
        }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: Keys.token)
        UserDefaults.standard.removeObject(forKey: Keys.refresh)
        UserDefaults.standard.removeObject(forKey: Keys.expiry)
        UserDefaults.standard.removeObject(forKey: Keys.verifier)
        UserDefaults.standard.removeObject(forKey: Keys.state)
        codeVerifier = nil
        expectedState = nil
        isSignedIn = false
        isAuthorizing = false
        lastError = nil
        disconnect()
        nowPlaying.clear()
        SpotifyLog.write("signed out")
    }

    func connectIfPossible() {
        guard !Runtime.isPreview else { return }
        refreshInstallState()
        guard SpotifyConfig.clientID.isEmpty == false else { return }
        guard let token = savedToken() else { return }
        let remote = ensureRemote()
        remote.connectionParameters.accessToken = token
        remote.delegate = self
        if !remote.isConnected {
            remote.connect()
        }
    }

    func disconnect() {
        artworkURI = nil
        if isConnected || appRemote?.isConnected == true {
            appRemote?.disconnect()
        }
        isConnected = false
    }

    func handleCallback(_ url: URL) {
        guard url.scheme == SpotifyConfig.callbackScheme else {
            SpotifyLog.write("ignored url scheme \(url.scheme ?? "none")")
            return
        }
        SpotifyLog.write("callback \(SpotifyLog.redacted(url))")
        if queryValue(named: "code", in: url) != nil {
            consume(url, source: "open url")
            return
        }
        let remote = ensureRemote()
        let parameters = remote.authorizationParameters(from: url)
        if let token = parameters?[SPTAppRemoteAccessTokenKey] {
            SpotifyLog.write("app remote returned a token")
            accept(token: token)
        } else if let message = parameters?[SPTAppRemoteErrorDescriptionKey] {
            lastError = message
            isAuthorizing = false
            SpotifyLog.write("app remote auth error: \(message)")
        } else if let error = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "error" })?.value {
            lastError = error
            isAuthorizing = false
            SpotifyLog.write("callback error: \(error)")
        } else {
            lastError = "Spotify sign in did not finish."
            isAuthorizing = false
            SpotifyLog.write("callback had no token and no error")
        }
    }

    func togglePlayback() {
        guard let api = connectedPlayerAPI() else {
            authorize()
            return
        }
        if nowPlaying.track?.isPlaying == true {
            api.pause(nil)
            nowPlaying.notePlayback(playing: false)
        } else {
            api.resume(nil)
            nowPlaying.notePlayback(playing: true)
        }
    }

    func next() {
        connectedPlayerAPI()?.skip(toNext: nil)
    }

    func previous() {
        connectedPlayerAPI()?.skip(toPrevious: nil)
    }

    private func authorize() {
        refreshInstallState()
        let remote = ensureRemote()
        remote.authorizeAndPlayURI("") { [weak self] installed in
            Task { @MainActor in
                self?.spotifyInstalled = installed
                if !installed {
                    self?.statusMessage = "Install Spotify on this iPad."
                }
            }
        }
    }

    private func refreshInstallState() {
        guard let url = URL(string: "spotify://") else {
            spotifyInstalled = false
            return
        }
        spotifyInstalled = UIApplication.shared.canOpenURL(url)
    }

    private func ensureRemote() -> SPTAppRemote {
        if let appRemote {
            return appRemote
        }
        let configuration = SPTConfiguration(
            clientID: SpotifyConfig.clientID,
            redirectURL: URL(string: SpotifyConfig.redirectURI)!
        )
        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        remote.delegate = self
        appRemote = remote
        return remote
    }

    private func connectedPlayerAPI() -> SPTAppRemotePlayerAPI? {
        guard appRemote?.isConnected == true else { return nil }
        return appRemote?.playerAPI
    }

    private func subscribe(_ remote: SPTAppRemote) {
        remote.playerAPI?.delegate = self
        remote.playerAPI?.subscribe(toPlayerState: { _, _ in })
        remote.playerAPI?.getPlayerState { [weak self] result, error in
            guard error == nil, let state = result as? SPTAppRemotePlayerState else { return }
            Task { @MainActor in
                self?.apply(state, from: remote)
            }
        }
    }

    private func apply(_ state: SPTAppRemotePlayerState, from remote: SPTAppRemote) {
        let track = state.track
        let uri = track.uri
        nowPlaying.applyRemote(
            name: track.name,
            artist: track.artist.name,
            album: track.album.name,
            uri: uri,
            durationMS: Int(track.duration),
            positionMS: Int(state.playbackPosition),
            isPaused: state.isPaused
        )
        guard uri != artworkURI else { return }
        artworkURI = uri
        remote.imageAPI?.fetchImage(forItem: track, with: CGSize(width: 640, height: 640)) { [weak self] image, error in
            guard error == nil, let image = image as? UIImage else { return }
            Task { @MainActor in
                guard self?.artworkURI == uri else { return }
                self?.nowPlaying.applyRemoteArtwork(image, uri: uri)
            }
        }
    }

    private func consume(_ url: URL, source: String) {
        let items = queryItems(in: url)
        if let error = items.first(where: { $0.name == "error" })?.value {
            isAuthorizing = false
            lastError = error == "access_denied" ? "Spotify sign in was denied." : error
            SpotifyLog.write("\(source) error \(error)")
            return
        }
        let state = items.first(where: { $0.name == "state" })?.value
        let expected = expectedState ?? UserDefaults.standard.string(forKey: Keys.state)
        let verifier = codeVerifier ?? UserDefaults.standard.string(forKey: Keys.verifier)
        guard
            let code = items.first(where: { $0.name == "code" })?.value,
            let state,
            state == expected,
            let verifier
        else {
            isAuthorizing = false
            if !isSignedIn {
                lastError = "Spotify sign in did not finish."
            }
            SpotifyLog.write("\(source) could not use callback. hasCode=\(items.contains { $0.name == "code" }) stateMatches=\(state == expected) hasVerifier=\(verifier != nil)")
            return
        }
        guard redeemedCodes.insert(code).inserted else {
            SpotifyLog.write("\(source) ignored duplicate callback")
            return
        }
        SpotifyLog.write("\(source) exchanging code")
        Task {
            await redeem(code: code, verifier: verifier)
            codeVerifier = nil
            expectedState = nil
            UserDefaults.standard.removeObject(forKey: Keys.verifier)
            UserDefaults.standard.removeObject(forKey: Keys.state)
            isAuthorizing = false
            authSession = nil
        }
    }

    private func redeem(code: String, verifier: String) async {
        let fields = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": verifier,
        ]
        await sendToken(fields, previousRefresh: nil)
    }

    @discardableResult
    private func sendToken(_ fields: [String: String], previousRefresh: String?) async -> String? {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(fields)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                let message = Self.spotifyError(from: data) ?? "Spotify sign in did not finish."
                SpotifyLog.write("token status \(status): \(message)")
                if previousRefresh != nil {
                    signOut()
                    lastError = "Sign in to Spotify again."
                } else if !isSignedIn {
                    lastError = message
                } else {
                    SpotifyLog.write("kept existing sign-in after token status \(status) \(body.prefix(180))")
                }
                return nil
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let token = try decoder.decode(TokenResponse.self, from: data)
            let refresh = token.refreshToken ?? previousRefresh
            guard let refresh, !refresh.isEmpty else {
                lastError = "Spotify sign in did not finish."
                SpotifyLog.write("token response had no refresh token")
                return nil
            }
            UserDefaults.standard.set(refresh, forKey: Keys.refresh)
            UserDefaults.standard.set(Date().addingTimeInterval(TimeInterval(token.expiresIn)).timeIntervalSince1970, forKey: Keys.expiry)
            accept(token: token.accessToken)
            SpotifyLog.write("signed in")
            return token.accessToken
        } catch {
            if !isSignedIn {
                lastError = "Spotify is not reachable"
            }
            SpotifyLog.write("token request failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func authorizeURL(verifier: String, state: String) -> URL? {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "user-read-currently-playing user-read-playback-state app-remote-control"),
        ]
        return components?.url
    }

    private func queryItems(in url: URL) -> [URLQueryItem] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        if items.isEmpty, let fragment = components?.fragment {
            items = URLComponents(string: "https://localhost/?\(fragment)")?.queryItems ?? []
        }
        return items
    }

    private func queryValue(named name: String, in url: URL) -> String? {
        queryItems(in: url).first(where: { $0.name == name })?.value
    }

    private func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = fields.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    private static func spotifyError(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let description = json["error_description"] as? String
        let code = json["error"] as? String
        return description ?? code
    }

    private func accept(token: String) {
        saveToken(token)
        isSignedIn = true
        isAuthorizing = false
        lastError = nil
        statusMessage = nil
        let remote = ensureRemote()
        remote.connectionParameters.accessToken = token
        remote.delegate = self
        remote.connect()
    }

    private func savedToken() -> String? {
        let token = UserDefaults.standard.string(forKey: Keys.token)
        guard let token, !token.isEmpty else { return nil }
        return token
    }

    private func saveToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: Keys.token)
    }

    private enum Keys {
        static let token = "ipadcc.appRemoteToken"
        static let refresh = "ipadcc.spotifyRefresh"
        static let expiry = "ipadcc.spotifyExpiry"
        static let verifier = "ipadcc.pkce.verifier"
        static let state = "ipadcc.pkce.state"
    }
}

private struct TokenResponse: Decodable {
    var accessToken: String
    var expiresIn: Int
    var refreshToken: String?
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
            return window
        }
        return scenes.first.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
    }
}

enum SpotifyLog {
    private static let logger = Logger(subsystem: "com.example.HelloWorld", category: "spotify")

    static func write(_ message: String) {
        logger.error("\(message, privacy: .public)")
        print("SPOTIFY \(message)")
        guard
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("spotify-auth.log")
        else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    static func redacted(_ url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = items.map { item -> String in
            let secret = item.name == "code" || item.name == "access_token"
            let value = secret ? "<redacted \(item.value?.count ?? 0)>" : (item.value ?? "")
            return "\(item.name)=\(value)"
        }.joined(separator: "&")
        return "\(url.scheme ?? "")://\(url.host ?? "")\(url.path)?\(query)"
    }
}

extension SpotifyRemote: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            self.isConnected = true
            self.statusMessage = nil
            self.subscribe(appRemote)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            if self.nowPlaying.track == nil {
                self.statusMessage = "Open Spotify and start a song."
            }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.artworkURI = nil
        }
    }
}

extension SpotifyRemote: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { @MainActor in
            guard let remote = self.appRemote, remote.isConnected else { return }
            self.apply(playerState, from: remote)
        }
    }
}
