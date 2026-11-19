import Foundation
import GhafCore

/// Market rates from open.er-api.com (free, no key; only the base currency is sent).
/// Cached on the device so an automation can convert a foreign purchase offline with the last known rates.
enum GhafExchangeRates {
    private static let key = "ghaf.fx.rates"
    static let sourceName = "ExchangeRate-API"

    static var cached: ExchangeRates? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(ExchangeRates.self, from: $0) }
    }

    /// Fetches new rates when the cache is older than `maxAge`. Never throws: conversion falls back to the cache.
    /// For automations: waits (briefly) only when no rates are cached at all, so a stale cache never delays a save.
    static func prepareForIngestion() async {
        if cached == nil { await refreshIfStale(timeout: 2) } else { Task.detached { await refreshIfStale() } }
    }

    static func refreshIfStale(maxAge: TimeInterval = 6 * 3600, timeout: TimeInterval = 5) async {
        if let cached, Date.now.timeIntervalSince(cached.updated) < maxAge { return }
        var request = URLRequest(url: URL(string: "https://open.er-api.com/v6/latest/USD")!)
        request.timeoutInterval = timeout
        struct Response: Decodable { let result: String; let time_last_update_unix: TimeInterval; let rates: [String: Decimal] }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONDecoder().decode(Response.self, from: data), body.result == "success",
              body.rates["AED"] != nil else { return }
        let rates = ExchangeRates(base: "USD", rates: body.rates, updated: Date(timeIntervalSince1970: body.time_last_update_unix))
        if let data = try? JSONEncoder().encode(rates) { UserDefaults.standard.set(data, forKey: key) }
    }
}
