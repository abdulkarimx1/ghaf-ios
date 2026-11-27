import Foundation

public enum ImportFileSizeError: Error {
    case tooLarge
    case unavailable
}

public enum ImportFileSizeLimit {
    public static let maximumBytes: Int64 = 25 * 1024 * 1024

    public static func check(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else { throw ImportFileSizeError.unavailable }
        guard Int64(fileSize) <= maximumBytes else { throw ImportFileSizeError.tooLarge }
    }
}
