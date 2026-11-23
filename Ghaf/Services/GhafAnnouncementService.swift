import Foundation

struct GhafAnnouncement: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let minVersion: String?
    let code: String?
    let expires: Date

    init(id: String, title: String, body: String, minVersion: String? = nil, code: String? = nil, expires: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.minVersion = minVersion
        self.code = code
        self.expires = expires
    }

    private enum CodingKeys: String, CodingKey { case id, title, body, minVersion, code, expires }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        body = try values.decode(String.self, forKey: .body)
        minVersion = try values.decodeIfPresent(String.self, forKey: .minVersion)
        code = try values.decodeIfPresent(String.self, forKey: .code)
        let raw = try values.decode(String.self, forKey: .expires)
        let formatter = ISO8601DateFormatter()
        expires = formatter.date(from: raw) ?? {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: raw)
        }() ?? .distantPast
    }
}

enum GhafAnnouncementService {
    private static let endpoint = URL(string: "https://ghaf-ai.ghafapp.workers.dev/announcement")!
    private static let dismissedKey = "ghaf.announcement.dismissedID"
    private static func checkedKey(language: String) -> String { "ghaf.announcement.checked.\(language)" }
    private static let interval: TimeInterval = 6 * 60 * 60

    static func check(language: String, now: Date = .now) async -> GhafAnnouncement? {
        let defaults = UserDefaults.standard
        let key = checkedKey(language: language)
        guard now.timeIntervalSince(defaults.object(forKey: key) as? Date ?? .distantPast) >= interval else { return nil }
        defaults.set(now, forKey: key)
        var request = URLRequest(url: endpoint, timeoutInterval: 8)
        request.setValue(language, forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let announcement = try? JSONDecoder().decode(GhafAnnouncement.self, from: data),
              announcement.expires > now,
              announcement.id != defaults.string(forKey: dismissedKey),
              isSupported(minVersion: announcement.minVersion) else { return nil }
        return announcement
    }

    static func dismiss(_ announcement: GhafAnnouncement) {
        UserDefaults.standard.set(announcement.id, forKey: dismissedKey)
    }

    private static func isSupported(minVersion: String?) -> Bool {
        guard let minVersion else { return true }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return version(current, isAtLeast: minVersion)
    }

    private static func version(_ current: String, isAtLeast minimum: String) -> Bool {
        let left = current.split(separator: ".").compactMap { Int($0) }
        let right = minimum.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return true
    }
}
