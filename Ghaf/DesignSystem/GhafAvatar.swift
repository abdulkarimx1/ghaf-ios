import SwiftUI
import UIKit

/// The profile photo, kept as a small JPEG in Application Support (not in backups).
enum GhafProfilePhoto {
    static let versionKey = "ghaf.profile.photoVersion"
    static let bannerVersionKey = "ghaf.profile.bannerVersion"

    private static var url: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("profile-photo.jpg")
    }
    private static var bannerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile-banner.jpg")
    }

    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }
    static func loadBanner() -> UIImage? { UIImage(contentsOfFile: bannerURL.path) }
    static func loadBannerData() -> Data? { try? Data(contentsOf: bannerURL) }

    /// Square-cropped to 512 px so it stays small and sharp in every circle it fills.
    static func save(_ image: UIImage) throws {
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * 512 / side, y: -crop.minY * 512 / side,
                                  width: image.size.width * 512 / side, height: image.size.height * 512 / side))
        }
        guard let data = square.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        bump()
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
        bump()
    }

    static func saveBanner(_ image: UIImage) throws {
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / longSide)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = stride(from: 0.82, through: 0.22, by: -0.1)
            .compactMap({ resized.jpegData(compressionQuality: $0) })
            .first(where: { $0.count <= 1_000_000 }) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: bannerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: bannerURL, options: [.atomic, .completeFileProtection])
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: bannerVersionKey) + 1, forKey: bannerVersionKey)
    }

    static func saveBannerData(_ data: Data?) throws {
        guard let data else { removeBanner(); return }
        guard data.count <= 1_000_000, UIImage(data: data) != nil else { throw CocoaError(.fileWriteCorruptFile) }
        try FileManager.default.createDirectory(at: bannerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: bannerURL, options: [.atomic, .completeFileProtection])
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: bannerVersionKey) + 1, forKey: bannerVersionKey)
    }

    static func removeBanner() {
        try? FileManager.default.removeItem(at: bannerURL)
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: bannerVersionKey) + 1, forKey: bannerVersionKey)
    }

    private static func bump() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: versionKey) + 1, forKey: versionKey)
    }
}

/// Profile photo, or initials on the theme's gradient when there is none.
struct GhafAvatar: View {
    let initials: String
    let theme: GhafTheme
    let languageCode: String
    var size: CGFloat = 88
    @AppStorage(GhafProfilePhoto.versionKey) private var version = 0

    var body: some View {
        Group {
            if let photo = GhafProfilePhoto.load() {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(GhafTypography.display(size * 0.36, languageCode: languageCode))
                    .foregroundStyle(theme.accentContrast)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [theme.accent, theme.glow], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: theme.accent.opacity(0.3), radius: 14, y: 6)
        .id(version)
        .accessibilityHidden(true)
    }
}
