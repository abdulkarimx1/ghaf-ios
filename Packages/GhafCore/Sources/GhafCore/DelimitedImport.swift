import Foundation

public enum DelimitedImport {
    public static func date(_ value: String, timeZone: TimeZone = .current) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let parts = value.split(whereSeparator: { $0 == "/" || $0 == "-" }).compactMap { Int($0) }
        let dayFirst = parts.count == 3 && parts[0] > 12
        let monthFirst = parts.count == 3 && parts[1] > 12
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd", monthFirst ? "MM/dd/yyyy" : "dd/MM/yyyy", dayFirst ? "dd/MM/yyyy" : "MM/dd/yyyy", "dd-MM-yyyy"]
        for format in formats {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone; formatter.isLenient = false; formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    public static func dictionary(headers: [String], values: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            let key = normalizeHeader(header)
            guard !key.isEmpty, result[key] == nil else { continue }
            result[key] = index < values.count ? values[index] : ""
        }
        return result
    }

    public static func value(_ row: [String: String], aliases: [String]) -> String? {
        for alias in aliases {
            if let value = row[normalizeHeader(alias)] { return value }
        }
        return nil
    }

    public static func decimal(_ value: String) -> Decimal? {
        let normalizedDigits = value.unicodeScalars.map { scalar -> String in
            if let number = scalar.properties.numericValue, (0...9).contains(number), scalar.properties.generalCategory == .decimalNumber { return String(Int(number)) }
            return String(scalar)
        }.joined().replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: "٬", with: ",")
        var text = String(normalizedDigits.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" || $0 == "+" })
        guard !text.isEmpty, text.filter({ $0 == "-" || $0 == "+" }).count <= 1,
              !(text.contains("-") && text.contains("+")) else { return nil }
        let decimalSeparator: Character?
        if text.contains(".") && text.contains(",") {
            guard let dot = text.lastIndex(of: "."), let comma = text.lastIndex(of: ",") else { return nil }
            decimalSeparator = dot < comma ? "," : "."
            let grouping: Character = decimalSeparator == "," ? "." : ","
            let pieces = text.split(separator: decimalSeparator!, omittingEmptySubsequences: false)
            guard pieces.count == 2, !pieces[1].isEmpty else { return nil }
            let groups = pieces[0].split(separator: grouping, omittingEmptySubsequences: false)
            guard !groups[0].isEmpty, groups[0].count <= 3,
                  groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
            text = groups.joined() + "." + pieces[1]
        } else if text.contains(",") {
            let groups = text.split(separator: ",", omittingEmptySubsequences: false)
            if groups.count > 1, (1...3).contains(groups[0].filter(\.isNumber).count), groups.dropFirst().allSatisfy({ $0.count == 3 }) {
                text.removeAll(where: { $0 == "," })
            } else if groups.count == 2, groups[1].count > 0, groups[1].count != 3 {
                text = text.replacingOccurrences(of: ",", with: ".")
            } else { return nil }
        } else if text.filter({ $0 == "." }).count > 1 {
            let groups = text.split(separator: ".", omittingEmptySubsequences: false)
            guard groups.dropFirst().allSatisfy({ $0.count == 3 }), (1...3).contains(groups[0].filter(\.isNumber).count) else { return nil }
            text.removeAll(where: { $0 == "." })
        }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func direction(amount: Decimal? = nil, debit: String? = nil, credit: String? = nil) -> TransactionDirection? {
        if debit != nil || credit != nil {
            let parsedDebit = debit.flatMap(decimal), parsedCredit = credit.flatMap(decimal)
            guard (debit == nil || parsedDebit != nil), (credit == nil || parsedCredit != nil) else { return nil }
            let debitValue = parsedDebit.map(abs) ?? 0
            let creditValue = parsedCredit.map(abs) ?? 0
            guard (debitValue > 0) != (creditValue > 0) else { return nil }
            return debitValue > 0 ? .debit : .credit
        }
        guard let amount, amount != 0 else { return nil }
        return amount > 0 ? .credit : .debit
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func rows(_ text: String) throws -> [[String]] {
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let delimiter = [",", ";", "\t"].max { score(normalizedText, $0) < score(normalizedText, $1) } ?? ","
        var result: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        let chars = Array(normalizedText)
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
