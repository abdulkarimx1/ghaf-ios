import Foundation

public enum DelimitedImport {
    public static func date(_ value: String, timeZone: TimeZone = .current) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let parts = value.split(whereSeparator: { $0 == "/" || $0 == "-" }).compactMap { Int($0) }
        let dayFirst = parts.count == 3 && parts[0] > 12
        let monthFirst = parts.count == 3 && parts[1] > 12
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", monthFirst ? "MM/dd/yyyy" : "dd/MM/yyyy", dayFirst ? "dd/MM/yyyy" : "MM/dd/yyyy", "dd-MM-yyyy"]
        for format in formats {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone; formatter.isLenient = false; formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    public static func rows(_ text: String) throws -> [[String]] {
        let delimiter = [",", ";", "\t"].max { score(text, $0) < score(text, $1) } ?? ","
        var result: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted, i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == Character(delimiter), !quoted {
                row.append(field); field = ""
            } else if (c == "\n" || c == "\r"), !quoted {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { result.append(row) }
                row = []
            } else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw DelimitedImportError.unclosedQuote }
        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { result.append(row) }
        guard result.count > 1 else { throw DelimitedImportError.noRows }
        return result
    }

    private static func score(_ text: String, _ delimiter: String) -> Int {
        text.split(whereSeparator: \.isNewline).prefix(4).reduce(0) { $0 + $1.filter { String($0) == delimiter }.count }
    }
}

public enum DelimitedImportError: LocalizedError {
    case unclosedQuote, noRows
    public var errorDescription: String? {
        switch self {
        case .unclosedQuote: "A quoted value is missing its closing quotation mark."
        case .noRows: "The file has no data rows."
        }
    }
}
