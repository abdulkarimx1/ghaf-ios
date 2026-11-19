enum GhafCurrencyDigits {
    static func fractionDigits(for code: String) -> Int {
        ["KWD", "BHD", "OMR", "JOD", "IQD", "LYD", "TND"].contains(code.uppercased()) ? 3 : 2
    }
}
