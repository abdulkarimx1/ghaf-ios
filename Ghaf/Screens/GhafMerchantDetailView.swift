import SwiftUI
import SwiftData
import MapKit
import GhafCore

/// The likely place from Apple Maps and this merchant's recent history, shown under a transaction's
/// receipt. Only the merchant name is sent to Apple Maps.
struct GhafMerchantDetailView: View {
    @Environment(\.modelContext) private var context
    let transaction: GhafTransaction
    let theme: GhafTheme
    let languageCode: String

    @State private var place: MKMapItem?
    @State private var lookupDone = false
    @State private var history: [GhafTransaction] = []

    private var ar: Bool { languageCode == "ar" }
    private var merchant: String? {
        guard let name = transaction.merchant?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    var body: some View {
        VStack(spacing: 14) {
            if let place { placeCard(place) }
            else if merchant != nil && transaction.isSpendingOrIncome && !lookupDone {
                ProgressView().frame(maxWidth: .infinity).padding(8)
            }
            if history.count > 1 { historyCard }
        }
        .task(id: transaction.id) { await load() }
    }

    private func placeCard(_ item: MKMapItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .item(item), interactionModes: []) {
                Marker(item.name ?? "", coordinate: item.placemark.coordinate).tint(theme.accent)
            }
            .frame(height: 150)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.name ?? "").font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                if let address = item.placemark.title {
                    Text(address).font(GhafTypography.body(13, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                }
                HStack(spacing: 10) {
                    if let phone = item.phoneNumber,
                       let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                        Link(destination: url) { Label(phone, systemImage: "phone.fill") }
                    }
                    Button { item.openInMaps() } label: {
                        Label(ar ? "الخرائط" : "Maps", systemImage: "map.fill")
                    }
                }
                .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                .buttonStyle(.bordered).tint(theme.accent)
                Text(ar ? "تطابق محتمل من خرائط Apple حسب اسم المتجر، وقد لا يكون الفرع نفسه."
                        : "Likely match from Apple Maps by merchant name. It may not be the exact branch.")
                    .font(GhafTypography.body(10, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ar ? "السجل مع هذا المتجر" : "History with this merchant")
                .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .padding(.bottom, 6)
            ForEach(history.prefix(5)) { item in
                HStack {
                    Text(item.date.formatted(.dateTime.day().month().year().locale(Locale(identifier: languageCode))))
                        .foregroundStyle(item.id == transaction.id ? theme.accent : theme.primaryText)
                    Spacer()
                    GhafMoneyLabel(amount: item.amount, currency: item.currency, languageCode: languageCode, size: 14)
                        .foregroundStyle(theme.primaryText)
                }
                .font(GhafTypography.body(14, languageCode: languageCode))
                .padding(.vertical, 7)
            }
            let month = history.filter {
                $0.currency == transaction.currency && Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month)
            }
            HStack {
                Text(ar ? "هذا الشهر · \(month.count)" : "This month · \(month.count)")
                Spacer()
                GhafMoneyLabel(amount: month.reduce(0) { $0 + $1.spendingAmount }, currency: transaction.currency,
                               languageCode: languageCode, size: 14)
            }
            .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
            .padding(.top, 6)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func load() async {
        guard let merchant else { lookupDone = true; return }
        let name = merchant
        history = (try? context.fetch(FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { $0.merchant == name },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        // Online services (known brands, subscriptions) have no shop to show.
        guard transaction.isSpendingOrIncome, GhafBrand.match(merchant) == nil,
              transaction.category != "Subscriptions" else { lookupDone = true; return }
        place = await Self.lookup(merchant)
        lookupDone = true
    }

    /// One Apple Maps query per merchant name per launch.
    private static var cache: [String: MKMapItem?] = [:]

    @MainActor
    private static func lookup(_ merchant: String) async -> MKMapItem? {
        let key = SubscriptionDetector.normalize(merchant)
        if let cached = cache[key] { return cached }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = merchant
        request.resultTypes = .pointOfInterest
        // UAE and the wider Gulf, where Ghaf's banks operate; no device location is used.
        request.region = MKCoordinateRegion(center: .init(latitude: 24.6, longitude: 54.8),
                                            span: .init(latitudeDelta: 8, longitudeDelta: 10))
        // A place counts only when its name starts like the merchant's ("Samuel Claude" is not "Claude").
        let first = key.split(separator: " ").first.map(String.init) ?? key
        let item = try? await MKLocalSearch(request: request).start().mapItems.first { candidate in
            let name = SubscriptionDetector.normalize(candidate.name ?? "")
            return !first.isEmpty && (name.hasPrefix(first) || key.hasPrefix(name.split(separator: " ").first.map(String.init) ?? "\u{0}"))
        }
        cache[key] = item
        return item
    }
}
