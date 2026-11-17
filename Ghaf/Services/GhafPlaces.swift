import Foundation
import MapKit
import CoreLocation
import GhafCore

/// Where a transaction happened. Bank messages only carry a name, unlike Apple Wallet, which gets the
/// merchant and location from the card network. So Ghaf: uses a place the user chose before, then
/// searches Apple Maps only for business-like names, near the user when location is allowed.
@MainActor
enum GhafPlaces {
    struct Saved: Codable {
        let name: String
        let latitude: Double
        let longitude: Double
        let address: String?
        let phone: String?
    }

    private static let merchantKey = "ghaf.places.byMerchant"
    private static let transactionKey = "ghaf.places.byTransaction"

    /// Descriptions people type or import ("Lunch", "Groceries") are not places to look up.
    private static let genericWords: Set<String> = [
        "lunch", "dinner", "breakfast", "brunch", "snack", "coffee", "tea", "food", "grocery", "groceries",
        "fuel", "petrol", "taxi", "parking", "rent", "salary", "transfer", "cash", "atm", "gift", "fine",
        "shopping", "pharmacy", "medicine", "bills", "internet", "electricity", "water", "gym", "car",
        "غداء", "عشاء", "فطور", "قهوة", "بقالة", "بنزين", "تاكسي", "موقف", "إيجار", "راتب", "تحويل"
    ]

    static func isGeneric(_ merchant: String) -> Bool {
        let words = CategoryMatcher.normalize(merchant).split(separator: " ").map(String.init)
        return words.isEmpty || words.allSatisfy { genericWords.contains($0) || $0.count < 2 }
    }

    // MARK: Memory

    private static func load(_ key: String) -> [String: Saved] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Saved].self, from: data)) ?? [:]
    }

    private static func store(_ value: [String: Saved], _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    /// The user's choice: for a named merchant it applies to all its transactions, for a description
    /// ("Lunch") only to this transaction.
    static func remember(_ item: MKMapItem, merchant: String, transactionID: UUID) {
        let saved = Saved(name: item.name ?? merchant, latitude: item.placemark.coordinate.latitude,
                          longitude: item.placemark.coordinate.longitude, address: item.placemark.title, phone: item.phoneNumber)
        if isGeneric(merchant) {
            var map = load(transactionKey); map[transactionID.uuidString] = saved; store(map, transactionKey)
        } else {
            var map = load(merchantKey); map[SubscriptionDetector.normalize(merchant)] = saved; store(map, merchantKey)
        }
        cache[SubscriptionDetector.normalize(merchant)] = nil
    }

    /// Where the phone was when the purchase was reported (passed by the Shortcut): the closest branch
    /// of this merchant within 2 km, else the spot itself. Saved for this transaction only, since chains
    /// have many branches.
    static func rememberPurchaseSpot(_ location: CLLocation, merchant: String, transactionID: UUID) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = merchant
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 4_000, longitudinalMeters: 4_000)
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        let nearest = items
            .filter { ($0.placemark.location?.distance(from: location) ?? .infinity) < 2_000 }
            .min { ($0.placemark.location?.distance(from: location) ?? .infinity) < ($1.placemark.location?.distance(from: location) ?? .infinity) }
        let saved = Saved(name: nearest?.name ?? merchant,
                          latitude: nearest?.placemark.coordinate.latitude ?? location.coordinate.latitude,
                          longitude: nearest?.placemark.coordinate.longitude ?? location.coordinate.longitude,
                          address: nearest?.placemark.title, phone: nearest?.phoneNumber)
        var map = load(transactionKey); map[transactionID.uuidString] = saved; store(map, transactionKey)
    }

    static func saved(merchant: String, transactionID: UUID) -> MKMapItem? {
        let saved = load(transactionKey)[transactionID.uuidString] ?? load(merchantKey)[SubscriptionDetector.normalize(merchant)]
        guard let saved else { return nil }
        let placemark = MKPlacemark(coordinate: .init(latitude: saved.latitude, longitude: saved.longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = saved.name
        item.phoneNumber = saved.phone
        return item
    }

    // MARK: Search

    private static var cache: [String: MKMapItem?] = [:]
    private static let locationManager = CLLocationManager()

    /// Near the user when location is allowed; otherwise the UAE. Never asks for location by itself.
    static var searchRegion: MKCoordinateRegion {
        let status = locationManager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways, let location = locationManager.location {
            return MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        }
        return MKCoordinateRegion(center: .init(latitude: 24.6, longitude: 54.8), span: .init(latitudeDelta: 8, longitudeDelta: 10))
    }

    static func requestLocationIfUndecided() {
        if locationManager.authorizationStatus == .notDetermined { locationManager.requestWhenInUseAuthorization() }
    }

    /// Best automatic match: the user's saved place, else a search for business-like names whose
    /// result starts like the merchant ("Samuel Claude" is not "Claude"), closest to the user.
    static func place(for merchant: String, transactionID: UUID) async -> MKMapItem? {
        if let saved = saved(merchant: merchant, transactionID: transactionID) { return saved }
        guard !isGeneric(merchant) else { return nil }
        let key = SubscriptionDetector.normalize(merchant)
        if let cached = cache[key] { return cached }
        let first = key.split(separator: " ").first.map(String.init) ?? key
        let items = (try? await search(merchant)) ?? []
        let matching = items.filter { candidate in
            let name = SubscriptionDetector.normalize(candidate.name ?? "")
            return !first.isEmpty && (name.hasPrefix(first) || key.hasPrefix(name.split(separator: " ").first.map(String.init) ?? "\u{0}"))
        }
        let here = locationManager.location
        let best = here.map { location in
            matching.min { ($0.placemark.location?.distance(from: location) ?? .infinity) < ($1.placemark.location?.distance(from: location) ?? .infinity) }
        } ?? matching.first
        cache[key] = best
        return best
    }

    static func distance(to item: MKMapItem) -> CLLocationDistance? {
        guard let here = locationManager.location, let there = item.placemark.location else { return nil }
        return here.distance(from: there)
    }

    /// Places first, then any match (addresses, areas) when no place has that name; nearest first.
    static func searchNearestFirst(_ text: String) async -> [MKMapItem] {
        var items = (try? await search(text)) ?? []
        if items.isEmpty {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.region = searchRegion
            items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        }
        return items.sorted { (distance(to: $0) ?? .infinity) < (distance(to: $1) ?? .infinity) }
    }

    static func search(_ text: String) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .pointOfInterest
        request.region = searchRegion
        return try await MKLocalSearch(request: request).start().mapItems
    }
}
