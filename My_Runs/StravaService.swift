import Foundation
import AuthenticationServices
import Security
import UIKit

// MARK: - Strava API client + OAuth
//
// SETUP REQUIRED:
// 1. Register an API application at https://www.strava.com/settings/api
// 2. Set "Authorization Callback Domain" to:   myruns
// 3. Paste your Client ID and Client Secret below.
// 4. The custom URL scheme "myruns" is already registered in My-Runs-Info.plist.
//
// Tokens are stored in the iOS Keychain.

@MainActor
final class StravaService: NSObject {
    static let shared = StravaService()

    // MARK: Configuration
    // Default (bundled) credentials are used unless the user supplies their own
    // via the in-app Setup screen. User-supplied credentials are stored in Keychain.
    private static let defaultClientID     = "249214"
    private static let defaultClientSecret = "a9ac6b90213c44fe3946fcec4b9846d990429698"
    private static let redirectURI  = "myruns://myruns/strava-callback"
    private static let urlScheme    = "myruns"

    private static let authURL  = "https://www.strava.com/oauth/mobile/authorize"
    private static let tokenURL = "https://www.strava.com/oauth/token"
    private static let apiBase  = "https://www.strava.com/api/v3"

    private var authSession: ASWebAuthenticationSession?

    // Effective credentials: user-supplied (if set) or bundled defaults.
    private static var clientID: String {
        let custom = Keychain.read(key: "strava.client_id") ?? ""
        return custom.isEmpty ? defaultClientID : custom
    }
    private static var clientSecret: String {
        let custom = Keychain.read(key: "strava.client_secret") ?? ""
        return custom.isEmpty ? defaultClientSecret : custom
    }

    static var isConfigured: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    /// True when the user has supplied their own credentials (preferred — gives them their own rate-limit pool).
    static var hasCustomCredentials: Bool {
        let id = Keychain.read(key: "strava.client_id") ?? ""
        let secret = Keychain.read(key: "strava.client_secret") ?? ""
        return !id.isEmpty && !secret.isEmpty
    }

    static var customClientID: String { Keychain.read(key: "strava.client_id") ?? "" }
    static var customClientSecret: String { Keychain.read(key: "strava.client_secret") ?? "" }

    static func setCustomCredentials(clientID: String, clientSecret: String) {
        Keychain.write(key: "strava.client_id", value: clientID)
        Keychain.write(key: "strava.client_secret", value: clientSecret)
    }

    static func clearCustomCredentials() {
        Keychain.delete(key: "strava.client_id")
        Keychain.delete(key: "strava.client_secret")
    }

    var isConnected: Bool { Keychain.read(key: "strava.refresh_token") != nil }

    enum StravaError: LocalizedError {
        case notConfigured
        case authCancelled
        case authFailed(String)
        case tokenExchangeFailed(String)
        case requestFailed(Int, String)
        case decodeFailed
        case noStreams
        case rateLimited
        case needsReauth

        var errorDescription: String? {
            switch self {
            case .notConfigured:            return "Strava is not configured. Add your Client ID and Secret in the Setup screen."
            case .authCancelled:            return "Strava authorization was cancelled."
            case .authFailed(let s):        return "Strava authorization failed: \(s)"
            case .tokenExchangeFailed(let b):
                let snippet = b.isEmpty ? "" : " — \(b.prefix(200))"
                return "Could not exchange code for tokens\(snippet)"
            case .requestFailed(let c, let b):
                let snippet = b.isEmpty ? "" : " — \(b.prefix(200))"
                return "Strava request failed (HTTP \(c))\(snippet)"
            case .decodeFailed:             return "Could not parse Strava response."
            case .noStreams:                return "Activity has no GPS data."
            case .rateLimited:              return "Strava rate limit reached. Wait ~15 minutes or set up your own API credentials (Setup → Strava)."
            case .needsReauth:              return "Strava session expired. Tap Disconnect, then Connect again."
            }
        }
    }

    // MARK: - OAuth

    func connect() async throws {
        guard Self.isConfigured else { throw StravaError.notConfigured }

        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id",       value: Self.clientID),
            URLQueryItem(name: "redirect_uri",    value: Self.redirectURI),
            URLQueryItem(name: "response_type",   value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope",           value: "read,activity:read_all")
        ]
        guard let url = components.url else { throw StravaError.authFailed("bad URL") }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(Self.urlScheme)
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let asError = error as? ASWebAuthenticationSessionError,
                          asError.code == .canceledLogin {
                    continuation.resume(throwing: StravaError.authCancelled)
                } else {
                    continuation.resume(throwing: StravaError.authFailed(error?.localizedDescription ?? "unknown"))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }

        guard let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code  = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw StravaError.authFailed("missing code in callback")
        }
        try await exchangeCodeForToken(code: code)
    }

    func disconnect() {
        Keychain.delete(key: "strava.access_token")
        Keychain.delete(key: "strava.refresh_token")
        Keychain.delete(key: "strava.expires_at")
    }

    private func exchangeCodeForToken(code: String) async throws {
        let body = [
            "client_id=\(Self.clientID)",
            "client_secret=\(Self.clientSecret)",
            "code=\(code)",
            "grant_type=authorization_code"
        ].joined(separator: "&")

        let data = try await postForm(url: Self.tokenURL, body: body)
        try saveTokens(from: data)
    }

    private func refreshAccessTokenIfNeeded() async throws {
        guard let expiresAtStr = Keychain.read(key: "strava.expires_at"),
              let expiresAt    = TimeInterval(expiresAtStr) else {
            throw StravaError.authFailed("not connected")
        }
        if Date().timeIntervalSince1970 < expiresAt - 60 { return }

        guard let refreshToken = Keychain.read(key: "strava.refresh_token") else {
            throw StravaError.authFailed("missing refresh token")
        }
        let body = [
            "client_id=\(Self.clientID)",
            "client_secret=\(Self.clientSecret)",
            "refresh_token=\(refreshToken)",
            "grant_type=refresh_token"
        ].joined(separator: "&")
        let data = try await postForm(url: Self.tokenURL, body: body)
        try saveTokens(from: data)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_at: TimeInterval
    }

    private func saveTokens(from data: Data) throws {
        do {
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            Keychain.write(key: "strava.access_token",  value: decoded.access_token)
            Keychain.write(key: "strava.refresh_token", value: decoded.refresh_token)
            Keychain.write(key: "strava.expires_at",    value: String(decoded.expires_at))
        } catch {
            throw StravaError.tokenExchangeFailed("")
        }
    }

    private func accessToken() async throws -> String {
        try await refreshAccessTokenIfNeeded()
        guard let token = Keychain.read(key: "strava.access_token") else {
            throw StravaError.authFailed("missing access token")
        }
        return token
    }

    // MARK: - HTTP helpers

    private func postForm(url: String, body: String) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            print("[Strava] POST \(url) failed: HTTP \(code) body=\(bodyStr)")
            throw StravaError.tokenExchangeFailed(bodyStr)
        }
        return data
    }

    private func authorizedGET(_ urlString: String) async throws -> Data {
        let token = try await accessToken()
        var req = URLRequest(url: URL(string: urlString)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            print("[Strava] GET \(urlString) failed: HTTP \(code) body=\(bodyStr)")
            switch code {
            case 401: throw StravaError.needsReauth
            case 429: throw StravaError.rateLimited
            default:  throw StravaError.requestFailed(code, bodyStr)
            }
        }
        return data
    }

    // MARK: - Activities

    struct ActivitySummary: Decodable, Sendable {
        let id: Int64
        let name: String
        let sport_type: String
        let start_date: String
        let distance: Double
        let moving_time: Double
        let elapsed_time: Double
        let total_elevation_gain: Double?
        let max_speed: Double?
        let average_heartrate: Double?
        let max_heartrate: Double?
        let calories: Double?
        let start_latlng: [Double]?
    }

    private static let stravaDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func startDate(for activity: ActivitySummary) -> Date {
        Self.stravaDateFormatter.date(from: activity.start_date) ?? Date()
    }

    /// Returns only Run-type activities. Strava sport_type values for runs:
    /// "Run", "TrailRun", "VirtualRun".
    func fetchAllRunActivities(progress: @MainActor (Int) -> Void = { _ in }) async throws -> [ActivitySummary] {
        var results: [ActivitySummary] = []
        var page = 1
        let perPage = 100

        while true {
            let batch = try await fetchActivitiesPage(page: page, perPage: perPage)
            if batch.isEmpty { break }
            let runs = batch.filter { isRunType($0.sport_type) }
            results.append(contentsOf: runs)
            progress(results.count)
            if batch.count < perPage { break }
            page += 1
        }
        return results
    }

    private func isRunType(_ s: String) -> Bool {
        s == "Run" || s == "TrailRun" || s == "VirtualRun"
    }

    private func fetchActivitiesPage(page: Int, perPage: Int) async throws -> [ActivitySummary] {
        var components = URLComponents(string: "\(Self.apiBase)/athlete/activities")!
        components.queryItems = [
            URLQueryItem(name: "page",     value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        let data = try await authorizedGET(components.url!.absoluteString)
        do {
            return try JSONDecoder().decode([ActivitySummary].self, from: data)
        } catch {
            throw StravaError.decodeFailed
        }
    }

    // MARK: - Streams → Trackpoints

    private struct StreamResponse: Decodable {
        struct IntStream: Decodable     { let data: [Int] }
        struct DoubleStream: Decodable  { let data: [Double] }
        struct LatLngStream: Decodable  { let data: [[Double]] }

        let time: IntStream?
        let latlng: LatLngStream?
        let distance: DoubleStream?
        let altitude: DoubleStream?
        let heartrate: IntStream?
        let velocity_smooth: DoubleStream?
    }

    /// Fetches GPS streams for an activity and converts them to TrackpointData.
    /// Returns the points plus computed elevation loss.
    func fetchTrackpoints(activityId: Int64, startTime: Date) async throws -> (points: [TrackpointData], elevationLossM: Double) {
        var components = URLComponents(string: "\(Self.apiBase)/activities/\(activityId)/streams")!
        components.queryItems = [
            URLQueryItem(name: "keys",        value: "time,latlng,distance,altitude,heartrate,velocity_smooth"),
            URLQueryItem(name: "key_by_type", value: "true")
        ]
        let data = try await authorizedGET(components.url!.absoluteString)
        let decoded: StreamResponse
        do {
            decoded = try JSONDecoder().decode(StreamResponse.self, from: data)
        } catch {
            throw StravaError.decodeFailed
        }

        guard let times  = decoded.time?.data, !times.isEmpty,
              let latlng = decoded.latlng?.data, latlng.count == times.count else {
            throw StravaError.noStreams
        }
        let distances  = decoded.distance?.data ?? []
        let altitudes  = decoded.altitude?.data ?? []
        let heartrates = decoded.heartrate?.data ?? []
        let speeds     = decoded.velocity_smooth?.data ?? []

        var points: [TrackpointData] = []
        points.reserveCapacity(times.count)
        var elevLoss = 0.0
        var lastAlt: Double?

        for i in 0..<times.count {
            guard latlng[i].count == 2 else { continue }
            let t   = startTime.addingTimeInterval(TimeInterval(times[i]))
            let lat = latlng[i][0]
            let lng = latlng[i][1]
            let dist: Double = i < distances.count ? distances[i] : 0
            let alt: Double  = i < altitudes.count ? altitudes[i] : 0
            let hr: Int?     = i < heartrates.count ? heartrates[i] : nil
            let sp: Double?  = i < speeds.count ? speeds[i] : nil

            if i < altitudes.count {
                if let prev = lastAlt {
                    let diff = alt - prev
                    if diff < 0 { elevLoss += -diff }
                }
                lastAlt = alt
            }

            points.append(TrackpointData(
                time: t, lat: lat, lng: lng, altitudeM: alt,
                distanceM: dist, heartRate: hr, speedMps: sp
            ))
        }
        return (points, elevLoss)
    }
}

// MARK: - ASWebAuthentication presentation context

extension StravaService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Keychain

private enum Keychain {
    private static let service = "Max-Leclercq.My-Runs"

    static func write(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String]      = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
