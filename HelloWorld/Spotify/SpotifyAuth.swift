import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum SpotifyConfig {
    static let redirectURI = "ipadcc://callback"
    static let callbackScheme = "ipadcc"
    static let scopes = "user-read-currently-playing user-read-playback-state"
}

@MainActor
final class SpotifyAuth: ObservableObject {
    @Published var isSignedIn: Bool
    @Published var isAuthorizing = false
    @Published var lastError: String?

    private let settings: AppSettings
    private let presenter = WebAuthPresenter()
    private var session: ASWebAuthenticationSession?
    private var codeVerifier: String?
    private var expectedState: String?
    private var exchangeInFlight = false

    init(settings: AppSettings) {
        self.settings = settings
        isSignedIn = KeychainStore.loadToken() != nil
    }

    func signIn() {
        let clientID = settings.trimmedClientID
        guard !clientID.isEmpty else {
            lastError = "Add a client ID first."
            return
        }
        lastError = nil
        let verifier = Self.randomVerifier()
        let state = UUID().uuidString
        codeVerifier = verifier
        expectedState = state
        guard let url = authorizeURL(clientID: clientID, verifier: verifier, state: state) else {
            lastError = "Could not open Spotify sign in."
            return
        }
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: SpotifyConfig.callbackScheme
        ) { [weak self] callback, error in
            Task { @MainActor in
                guard let self else { return }
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    self.isAuthorizing = false
                    return
                }
                guard let callback else {
                    self.isAuthorizing = false
                    if error != nil {
                        self.lastError = "Spotify sign in did not finish."
                    }
                    return
                }
                self.consume(callback)
            }
        }
        session.presentationContextProvider = presenter
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        isAuthorizing = true
        if !session.start() {
            isAuthorizing = false
            lastError = "Could not open Spotify sign in."
        }
    }

    func handleCallback(_ url: URL) {
        guard url.scheme == SpotifyConfig.callbackScheme else { return }
        consume(url)
    }

    func signOut() {
        KeychainStore.deleteToken()
        isSignedIn = false
        lastError = nil
        isAuthorizing = false
    }

    func validToken() async -> String? {
        guard let stored = KeychainStore.loadToken() else {
            isSignedIn = false
            return nil
        }
        if stored.expiry > Date() {
            return stored.access
        }
        return await refresh(stored)
    }

    func forceRefresh() async -> String? {
        guard let stored = KeychainStore.loadToken() else {
            isSignedIn = false
            return nil
        }
        return await refresh(stored)
    }

    private func consume(_ url: URL) {
        guard !exchangeInFlight else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            isAuthorizing = false
            lastError = error == "access_denied" ? "Spotify sign in was denied." : "Spotify sign in did not finish."
            return
        }
        guard
            let code = items.first(where: { $0.name == "code" })?.value,
            let state = items.first(where: { $0.name == "state" })?.value,
            state == expectedState,
            let verifier = codeVerifier
        else {
            isAuthorizing = false
            lastError = "Spotify sign in did not finish."
            return
        }
        exchangeInFlight = true
        Task {
            await redeem(code: code, verifier: verifier)
            exchangeInFlight = false
            codeVerifier = nil
            expectedState = nil
            isAuthorizing = false
        }
    }

    private func redeem(code: String, verifier: String) async {
        let fields = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": settings.trimmedClientID,
            "code_verifier": verifier,
        ]
        await sendToken(fields, previousRefresh: nil)
    }

    private func refresh(_ stored: StoredToken) async -> String? {
        let fields = [
            "grant_type": "refresh_token",
            "refresh_token": stored.refresh,
            "client_id": settings.trimmedClientID,
        ]
        return await sendToken(fields, previousRefresh: stored.refresh)
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
                if status == 400 || status == 401 {
                    signOut()
                    lastError = "Sign in to Spotify again."
                } else {
                    lastError = "Spotify sign in did not finish."
                }
                return nil
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let token = try decoder.decode(TokenResponse.self, from: data)
            let refresh = token.refreshToken ?? previousRefresh
            guard let refresh, !refresh.isEmpty else {
                lastError = "Spotify sign in did not finish."
                return nil
            }
            let stored = StoredToken(
                access: token.accessToken,
                refresh: refresh,
                expiry: Date().addingTimeInterval(TimeInterval(max(30, token.expiresIn - 60)))
            )
            KeychainStore.save(stored)
            isSignedIn = true
            lastError = nil
            return stored.access
        } catch {
            lastError = "Spotify is not reachable"
            return nil
        }
    }

    private func authorizeURL(clientID: String, verifier: String, state: String) -> URL? {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes),
        ]
        return components?.url
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
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }
}

private struct TokenResponse: Decodable {
    var accessToken: String
    var expiresIn: Int
    var refreshToken: String?
}

struct StoredToken: Codable {
    var access: String
    var refresh: String
    var expiry: Date
}

enum KeychainStore {
    private static let service = "ipadcc.spotify"
    private static let account = "token"

    static func save(_ token: StoredToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadToken() -> StoredToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(StoredToken.self, from: data)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
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
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        return UIWindow(frame: UIScreen.main.bounds)
    }
}
