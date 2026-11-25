import Foundation
import MapKit
import CoreLocation
import GhafCore

/// Where a transaction happened. Bank messages only carry a name, unlike Apple Wallet, which gets the
/// merchant and location from the card network. So Ghaf: uses a place the user chose before, then
/// searches Apple Maps only for business-like names, near the user when location is allowed.
@MainActor
enum GhafPlaces {
    @MainActor
    private final class LocationDelegate: NSObject, @preconcurrency CLLocationManagerDelegate {
        var continuations: [CheckedContinuation<CLLocation?, Never>] = []
        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            let pending = continuations
            continuations.removeAll()
            pending.forEach { $0.resume(returning: locations.last) }
        }
        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            let pending = continuations
            continuations.removeAll()
            pending.forEach { $0.resume(returning: nil) }
        }
    }

    struct Saved: Codable {
        let name: String
        let latitude: Double
        let longitude: Double
        let address: String?
        let phone: String?
        var isUserChosen: Bool? = false
        var isSuppressed: Bool? = false
        var isArea: Bool? = false
        var horizontalAccuracy: Double? = nil
    }

    private static let merchantKey = "ghaf.places.byMerchant"
    private static let transactionKey = "ghaf.places.byTransaction"
    /// Automatic search hits, kept across launches so a relaunch doesn't search Apple Maps again (V5).
    private static let searchKey = "ghaf.places.searchHits"

    /// Descriptions people type or import ("Lunch", "Groceries") are not places to look up.
    private static let genericWords: Set<String> = [
        "lunch", "dinner", "breakfast", "brunch", "snack", "coffee", "tea", "food", "grocery", "groceries",
        "fuel", "petrol", "taxi", "parking", "rent", "salary", "transfer", "cash", "atm", "gift", "fine",
        "shopping", "pharmacy", "medicine", "bills", "internet", "electricity", "water", "gym", "car",
        "غداء", "عشاء", "فطور", "قهوة", "بقالة", "بنزين", "تاكسي", "موقف", "إيجار", "راتب", "تحويل"
    ]

    static func isGeneric(_ merchant: String) -> Bool {
        let words = MerchantName.key(merchant).split(separator: " ").map(String.init)
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

    /// Area name for each transaction (by id) that has a saved place; read-only, no search or location.
    /// Same area rule as the Places card in More: the address's second-to-last part, else the place name.
    static func savedAreasByTransaction() -> [String: String] {
        load(transactionKey).mapValues { place in
            let address = place.address?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            return address.count > 1 ? address[address.count - 2] : place.name
        }
    }

    /// The user's choice: for a named merchant it applies to all its transactions, for a description
    /// ("Lunch") only to this transaction.
    static func remember(_ item: MKMapItem, merchant: String, transactionID: UUID) {
        let saved = Saved(name: item.name ?? merchant, latitude: item.placemark.coordinate.latitude,
                          longitude: item.placemark.coordinate.longitude, address: item.placemark.title, phone: item.phoneNumber,
                          isUserChosen: true)
        if isGeneric(merchant) {
            var map = load(transactionKey); map[transactionID.uuidString] = saved; store(map, transactionKey)
        } else {
            var transactionMap = load(transactionKey)
            transactionMap.removeValue(forKey: transactionID.uuidString)
            store(transactionMap, transactionKey)
            var map = load(merchantKey); map[SubscriptionDetector.normalize(merchant)] = saved; store(map, merchantKey)
        }
        cache[SubscriptionDetector.normalize(merchant)] = nil
    }

    /// Where the phone was when the purchase was reported (passed by the Shortcut): the closest branch
    /// of this merchant within 2 km, else the spot itself. Saved for this transaction only, since chains
    /// have many branches.
    static func rememberPurchaseSpot(_ location: CLLocation, merchant: String, transactionID: UUID) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = MerchantName.clean(merchant)
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 4_000, longitudinalMeters: 4_000)
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        let nearest = items
            .filter { ($0.placemark.location?.distance(from: location) ?? .infinity) < 2_000 }
            .min { ($0.placemark.location?.distance(from: location) ?? .infinity) < ($1.placemark.location?.distance(from: location) ?? .infinity) }
        let saved = Saved(name: nearest?.name ?? MerchantName.clean(merchant),
                          latitude: nearest?.placemark.coordinate.latitude ?? location.coordinate.latitude,
                          longitude: nearest?.placemark.coordinate.longitude ?? location.coordinate.longitude,
                          address: nearest?.placemark.title, phone: nil, isUserChosen: false)
        var map = load(transactionKey); map[transactionID.uuidString] = saved; store(map, transactionKey)
    }

    static func saved(merchant: String, transactionID: UUID) -> MKMapItem? {
        let saved = load(transactionKey)[transactionID.uuidString] ?? load(merchantKey)[SubscriptionDetector.normalize(merchant)]
        guard let saved, saved.isSuppressed != true else { return nil }
        let placemark = MKPlacemark(coordinate: .init(latitude: saved.latitude, longitude: saved.longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = saved.name
        item.phoneNumber = saved.isUserChosen == true ? saved.phone : nil
        return item
    }

    static func clearPlace(merchant: String, transactionID: UUID) {
        let saved = Saved(name: "", latitude: 0, longitude: 0, address: nil, phone: nil,
                          isUserChosen: true, isSuppressed: true)
        var map = load(transactionKey)
        map[transactionID.uuidString] = saved
        store(map, transactionKey)
        cache[SubscriptionDetector.normalize(merchant)] = nil
    }

    private static func isSuppressed(merchant: String, transactionID: UUID) -> Bool {
        load(transactionKey)[transactionID.uuidString]?.isSuppressed == true
    }

    // MARK: Search

    private static var cache: [String: MKMapItem?] = [:]
    private static let locationDelegate = LocationDelegate()
    private static let locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = locationDelegate
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return manager
    }()

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

    /// Nil means the system has not asked yet; false covers denied or restricted access.
    static var locationPermission: Bool? {
        switch locationManager.authorizationStatus {
        case .notDetermined: return nil
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Stores the current place locally for a manual transaction when permission and a fix already exist.
    static func rememberCurrentLocation(transactionID: UUID) async {
        guard locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways else { return }
        let location = await withCheckedContinuation { continuation in
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationDelegate.continuations.append(continuation)
            locationManager.requestLocation()
        }
        guard let location, PlaceSelection.acceptsAreaAccuracy(location.horizontalAccuracy) else { return }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        guard let area = placemark?.subLocality ?? placemark?.locality else { return }
        let saved = Saved(name: area,
                          latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                          address: nil, phone: nil, isUserChosen: false, isArea: true,
                          horizontalAccuracy: location.horizontalAccuracy)
        var map = load(transactionKey); map[transactionID.uuidString] = saved; store(map, transactionKey)
    }

    /// Best automatic match: the user's saved place, else a search for business-like names whose
    /// result starts like the merchant ("Samuel Claude" is not "Claude"), closest to the user.
    static func place(for merchant: String, transactionID: UUID, isManual: Bool = false) async -> MKMapItem? {
        if isSuppressed(merchant: merchant, transactionID: transactionID) { return nil }
        if isManual {
            let savedChoice = load(transactionKey)[transactionID.uuidString]
                ?? load(merchantKey)[SubscriptionDetector.normalize(merchant)]
            if let saved = savedChoice, saved.isUserChosen == true {
                return saved.isSuppressed == true ? nil : Self.mapItem(saved)
            }
            return await manualPlace(merchant: merchant, transactionID: transactionID)
        }
        if let saved = saved(merchant: merchant, transactionID: transactionID) { return saved }
        guard !isGeneric(merchant) else { return nil }
        let key = SubscriptionDetector.normalize(merchant)
        if let cached = cache[key] { return cached }
        if let hit = load(searchKey)[key] {
            let item = Self.mapItem(hit); item.phoneNumber = nil; cache[key] = item; return item
        }
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
        best?.phoneNumber = nil
        cache[key] = best
        if let best {
            var hits = load(searchKey)
            hits[key] = Saved(name: best.name ?? MerchantName.clean(merchant),
                              latitude: best.placemark.coordinate.latitude, longitude: best.placemark.coordinate.longitude,
                              address: best.placemark.title, phone: nil, isUserChosen: false)
            store(hits, searchKey)
        }
        return best
    }

    /// Manual entries use a strict location fix and only infer a shop when its nearest
    /// POI is uniquely separated. Otherwise just the reverse-geocoded area is retained.
    private static func manualPlace(merchant: String, transactionID: UUID) async -> MKMapItem? {
        let prior = load(transactionKey)[transactionID.uuidString]
        let location: CLLocation
        if let prior, prior.isArea == true,
           let accuracy = prior.horizontalAccuracy, PlaceSelection.acceptsAreaAccuracy(accuracy) {
            location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: prior.latitude, longitude: prior.longitude),
                                  altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: .now)
            if isGeneric(merchant) { return Self.mapItem(prior) }
        } else {
            guard locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways,
                  let fix = await accurateCurrentLocation(),
                  PlaceSelection.acceptsAreaAccuracy(fix.horizontalAccuracy) else { return nil }
            location = fix
        }

        if !isGeneric(merchant) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = MerchantName.clean(merchant)
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 250, longitudinalMeters: 250)
            let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            let candidates = items.compactMap { item -> (MKMapItem, Double)? in
                guard let point = item.placemark.location else { return nil }
                let distance = point.distance(from: location)
                return distance <= 60 ? (item, distance) : nil
            }
            if let selected = PlaceSelection.selectedCandidateIndex(distances: candidates.map(\.1)) {
                let item = candidates[selected].0
                let saved = Saved(name: item.name ?? MerchantName.clean(merchant),
                                  latitude: item.placemark.coordinate.latitude,
                                  longitude: item.placemark.coordinate.longitude,
                                  address: item.placemark.title, phone: nil, isUserChosen: false,
                                  isArea: false, horizontalAccuracy: location.horizontalAccuracy)
                var map = load(transactionKey); map[transactionID.uuidString] = saved; store(map, transactionKey)
                return Self.mapItem(saved)
            }
        }

        if let prior, prior.isArea == true { return Self.mapItem(prior) }
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
              let area = placemark.subLocality ?? placemark.locality else { return nil }
        let saved = Saved(name: area, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                          address: nil, phone: nil, isUserChosen: false, isArea: true,
                          horizontalAccuracy: location.horizontalAccuracy)
        var map = load(transactionKey); map[transactionID.uuidString] = saved; store(map, transactionKey)
        return Self.mapItem(saved)
    }

    private static func accurateCurrentLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationDelegate.continuations.append(continuation)
            locationManager.requestLocation()
        }
    }

    private static func mapItem(_ saved: Saved) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: saved.latitude, longitude: saved.longitude)))
        item.name = saved.name
        item.phoneNumber = saved.phone
        return item
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
