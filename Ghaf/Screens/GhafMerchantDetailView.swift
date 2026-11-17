import SwiftUI
import SwiftData
import MapKit
import GhafCore

/// The likely place from Apple Maps and this merchant's recent history, shown under a transaction's
/// receipt. Only the merchant name is sent to Apple Maps.
struct GhafMerchantDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    let transaction: GhafTransaction
    let theme: GhafTheme
    let languageCode: String

    @State private var place: MKMapItem?
    @State private var lookupDone = false
    @State private var choosingPlace = false
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
            } else if canHavePlace {
                Button { choosingPlace = true } label: {
                    Label(ar ? "حدّد المكان" : "Choose place", systemImage: "mappin.and.ellipse")
                        .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.ghafPress)
            }
            if history.count > 1 { historyCard }
        }
        .task(id: transaction.id) { await load() }
        .sheet(isPresented: $choosingPlace) {
            GhafPlacePicker(initialQuery: GhafPlaces.isGeneric(merchant ?? "") ? "" : (merchant ?? ""),
                            theme: theme, languageCode: languageCode) { item in
                GhafPlaces.remember(item, merchant: merchant ?? "", transactionID: transaction.id)
                place = item
            }
        }
    }

    private func placeCard(_ item: MKMapItem) -> some View {
        let coordinate = item.placemark.coordinate
        return VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 900))) {
                Marker(item.name ?? "", systemImage: "bag.fill", coordinate: coordinate).tint(theme.accent)
            }
            .mapControlVisibility(.hidden)
            .frame(height: 170)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name ?? "").font(GhafTypography.heading(18, languageCode: languageCode))
                        .foregroundStyle(theme.primaryText)
                    if let address = item.placemark.title {
                        Text(address).font(GhafTypography.body(13, languageCode: languageCode))
                            .foregroundStyle(theme.secondaryText).lineLimit(2)
                    }
                }
                HStack(spacing: 8) {
                    placeAction(ar ? "الاتجاهات" : "Directions", "arrow.triangle.turn.up.right.diamond.fill") {
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                    }
                    // A universal link: opens the Google Maps app when installed, else the web. No SDK or key needed.
                    if let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)") {
                        placeAction("Google Maps", "map.fill") { openURL(url) }
                    }
                    if let phone = item.phoneNumber,
                       let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                        placeAction(ar ? "اتصال" : "Call", "phone.fill") { openURL(url) }
                    }
                    placeAction(ar ? "تغيير" : "Change", "mappin.and.ellipse") { choosingPlace = true }
                }
                Text(ar ? "رسائل البنك لا تتضمن الموقع. هذا اختيارك أو أقرب تطابق، ويُحفظ لكل عمليات هذا المتجر."
                        : "Bank messages don't include a location. This is your pick or the closest match, saved for every purchase here.")
                    .font(GhafTypography.body(11, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme)
        .clipShape(RoundedRectangle(cornerRadius: GhafMetrics.cardRadius, style: .continuous))
    }

    private func placeAction(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(GhafTypography.body(11, languageCode: languageCode, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.ghafPress)
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

    /// Spending at a physical place; online services and subscriptions have no shop to show.
    private var canHavePlace: Bool {
        transaction.isSpendingOrIncome && transaction.category != "Subscriptions" && GhafBrand.match(merchant) == nil
    }

    private func load() async {
        guard let merchant else { lookupDone = true; return }
        let name = merchant
        history = (try? context.fetch(FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { $0.merchant == name },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        guard canHavePlace else { lookupDone = true; return }
        place = await GhafPlaces.place(for: merchant, transactionID: transaction.id)
        lookupDone = true
    }
}

/// Search Apple Maps for the real place, nearest first, with the results on a map; the choice is remembered.
struct GhafPlacePicker: View {
    @Environment(\.dismiss) private var dismiss
    let initialQuery: String
    let theme: GhafTheme
    let languageCode: String
    let onPick: (MKMapItem) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    private var ar: Bool { languageCode == "ar" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(results, id: \.self) { item in
                        Marker(item.name ?? "", coordinate: item.placemark.coordinate).tint(theme.accent)
                    }
                }
                .frame(height: 220)
                List {
                    if results.isEmpty && !searching {
                        Text(query.isEmpty ? (ar ? "اكتب اسم المتجر أو المطعم كما في الرسالة." : "Type the shop or restaurant name as it appears in the message.")
                                           : (ar ? "لا نتائج. جرّب جزءاً من الاسم أو اسم المنطقة." : "No results. Try part of the name, or add the area."))
                            .foregroundStyle(theme.secondaryText)
                    }
                    ForEach(results, id: \.self) { item in
                        Button {
                            onPick(item)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name ?? "").font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                                        .foregroundStyle(theme.primaryText)
                                    if let address = item.placemark.title {
                                        Text(address).font(GhafTypography.body(12, languageCode: languageCode))
                                            .foregroundStyle(theme.secondaryText).lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 8)
                                if let distance = GhafPlaces.distance(to: item) {
                                    Text(Measurement(value: distance / 1000, unit: UnitLength.kilometers)
                                        .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))).locale(Locale(identifier: languageCode))))
                                        .font(GhafTypography.number(12, weight: .semibold))
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .overlay { if searching { ProgressView() } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: ar ? "ابحث في خرائط Apple" : "Search Apple Maps")
            .navigationTitle(ar ? "حدّد المكان" : "Choose place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(ar ? "إلغاء" : "Cancel") { dismiss() } } }
            .task(id: query) {
                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(350))   // wait for typing to pause
                guard !Task.isCancelled else { return }
                searching = true
                results = await GhafPlaces.searchNearestFirst(query)
                searching = false
                if !results.isEmpty { withAnimation { camera = .automatic } }
            }
            .onAppear {
                query = initialQuery
                // Asked here, where the reason is obvious: nearby places for this purchase.
                GhafPlaces.requestLocationIfUndecided()
            }
        }
    }
}
