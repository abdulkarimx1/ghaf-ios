import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit

/// Google sign-in (OAuth 2 + PKCE) and Drive backups. Uses Drive's private appDataFolder. Needs `GHAF_GOOGLE_CLIENT_ID` (an iOS
/// OAuth client ID from Google Cloud Console) in Info.plist.
@MainActor
final class GhafGoogleDrive: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GhafGoogleDrive()

    enum DriveError: LocalizedError {
        case notConfigured, cancelled, noBackup, server(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Google sign-in isn't set up in this build yet."
            case .cancelled: "Sign-in was cancelled."
            case .noBackup: "No Ghaf backup was found in your Google Drive."
            case .server(let message): message
            }
        }
    }

    @Published private(set) var email: String? = UserDefaults.standard.string(forKey: "ghaf.drive.email")
    @Published private(set) var avatarURL: String? = UserDefaults.standard.string(forKey: "ghaf.drive.avatar")
    @Published private(set) var lastBackupDate: Date? = UserDefaults.standard.object(forKey: "ghaf.drive.lastBackup") as? Date
    @Published private(set) var isBusy = false

    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast
    private let refreshKey = "ghaf.drive.refresh"
    private let scope = "openid email https://www.googleapis.com/auth/drive.appdata"

    var clientID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "GHAF_GOOGLE_CLIENT_ID") as? String)?
            .trimmingCharacters(in: .whitespaces)
        return (value?.isEmpty ?? true) ? nil : value
    }

    var isConfigured: Bool { clientID != nil }
    var isConnected: Bool { email != nil && Keychain.read(refreshKey) != nil }

    /// "123-abc.apps.googleusercontent.com" -> "com.googleusercontent.apps.123-abc"
    private var redirectScheme: String? {
        guard let clientID else { return nil }
        return "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    // MARK: Sign in / out

    func signIn() async throws {
        guard let clientID, let scheme = redirectScheme else { throw DriveError.notConfigured }
        isBusy = true
        defer { isBusy = false }

        let verifier = Self.randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let redirect = "\(scheme):/oauth2redirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "consent"),
            .init(name: "access_type", value: "offline")
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: scheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin ? DriveError.cancelled : (error ?? DriveError.cancelled)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw DriveError.server("Google did not return a sign-in code.")
        }

        let tokens = try await tokenRequest([
            "client_id": clientID, "code": code, "code_verifier": verifier,
            "grant_type": "authorization_code", "redirect_uri": redirect
        ])
        if let refresh = tokens["refresh_token"] as? String { Keychain.save(refresh, for: refreshKey) }
        store(tokens)
        if let idToken = tokens["id_token"] as? String {
            let claims = Self.claims(fromIDToken: idToken)
            if let mail = claims["email"] as? String {
                email = mail
                UserDefaults.standard.set(mail, forKey: "ghaf.drive.email")
            }
            avatarURL = claims["picture"] as? String
            UserDefaults.standard.set(avatarURL, forKey: "ghaf.drive.avatar")
        }
    }

    func signOut() {
        Keychain.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: "ghaf.drive.email")
        UserDefaults.standard.removeObject(forKey: "ghaf.drive.avatar")
        email = nil
        avatarURL = nil
        accessToken = nil
    }

    // MARK: Backups

    func upload(fileAt url: URL) async throws {
        isBusy = true
        defer { isBusy = false }
        let token = try await validAccessToken()
        let boundary = "ghaf-\(UUID().uuidString)"
        let name = "Ghaf-backup-\(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))).json"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(#"{"name":"\#(name)","mimeType":"application/json","parents":["appDataFolder"]}"#)
        body.append("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n")
        body.append(try Data(contentsOf: url))
        body.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&spaces=appDataFolder")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try await send(request)
        lastBackupDate = .now
        UserDefaults.standard.set(lastBackupDate, forKey: "ghaf.drive.lastBackup")
    }

    /// Downloads the newest Ghaf backup to a temporary file.
    func downloadLatest() async throws -> URL {
        isBusy = true
        defer { isBusy = false }
        let token = try await validAccessToken()
        var list = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        list.queryItems = [
            .init(name: "q", value: "name contains 'Ghaf-backup' and trashed = false"),
            .init(name: "orderBy", value: "createdTime desc"),
            .init(name: "pageSize", value: "1"),
            .init(name: "spaces", value: "appDataFolder"),
            .init(name: "fields", value: "files(id,name,createdTime)")
        ]
        var request = URLRequest(url: list.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let json = try JSONSerialization.jsonObject(with: try await send(request)) as? [String: Any]
        guard let file = (json?["files"] as? [[String: Any]])?.first, let id = file["id"] as? String else {
            throw DriveError.noBackup
        }
        if let created = file["createdTime"] as? String, let date = ISO8601DateFormatter().date(from: created) {
            lastBackupDate = date
            UserDefaults.standard.set(date, forKey: "ghaf.drive.lastBackup")
        }

        var download = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(id)?alt=media")!)
        download.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await send(download)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent((file["name"] as? String) ?? "Ghaf-backup.json")
        try data.write(to: local, options: .atomic)
        return local
    }

    // MARK: Tokens

    private func validAccessToken() async throws -> String {
        if let accessToken, accessTokenExpiry > .now.addingTimeInterval(60) { return accessToken }
        guard let clientID, let refresh = Keychain.read(refreshKey) else { throw DriveError.notConfigured }
        let tokens = try await tokenRequest(["client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token"])
        store(tokens)
        guard let accessToken else { throw DriveError.server("Google did not return an access token.") }
        return accessToken
    }

    private func store(_ tokens: [String: Any]) {
        accessToken = tokens["access_token"] as? String
        accessTokenExpiry = .now.addingTimeInterval(TimeInterval((tokens["expires_in"] as? Int) ?? 3000))
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let data = try await send(request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error_description"] as? String) ?? (($0["error"] as? [String: Any])?["message"] as? String) }
            throw DriveError.server(detail ?? "Google Drive request failed.")
        }
        return data
    }

    // MARK: Helpers

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URL
    }

    private static func claims(fromIDToken token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return [:] }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }
}

/// Small generic-password store; also holds the optional cloud AI access token.
enum Keychain {
    static func save(_ value: String, for key: String) {
        delete(key)
        SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key,
                    kSecValueData: Data(value.utf8),
                    kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key,
                                          kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary)
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    mutating func append(_ string: String) { append(Data(string.utf8)) }
}
