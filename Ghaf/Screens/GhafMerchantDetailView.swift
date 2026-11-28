import SwiftUI
import SwiftData
import MapKit
import GhafCore

/// The likely place from Apple Maps and this merchant's recent history, shown under a transaction's
/// receipt. Only the merchant name is sent to Apple Maps.
struct GhafMerchantDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage("ghaf.merchant.aliases") private var merchantAliases = Data()
    let transaction: GhafTransaction
    let theme: GhafTheme
    let languageCode: String
    let mapsAppPreference: String

    @State private var place: MKMapItem?
    @State private var lookupDone = false
    @State private var choosingPlace = false
    @State private var history: [GhafTransaction] = []

    private var ar: Bool { languageCode == "ar" }
    private var merchant: String? {
        guard let name = GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant), !name.isEmpty else { return nil }
        return name
    }

    var body: some View {
        VStack(spacing: 14) {
            if let place { placeCard(place) }
            else if merchant != nil && transaction.isSpendingOrIncome && !lookupDone {
                ProgressView().frame(maxWidth: .infinity).padding(8)
            } else if canHavePlace {
                Button { choosingPlace = true } label: {
                    Label(ar ? "تغيير المكان" : "Change place", systemImage: "mappin.and.ellipse")
                        .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(GhafMetrics.cardPadding)
                        .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), fallback: theme.surface)
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.ghafPress)
            }
            if history.count > 1 { historyCard }
        }
        .task(id: transaction.id) {
            await Task.yield()
            await load()
        }
        .sheet(isPresented: $choosingPlace) {
            GhafPlacePicker(initialQuery: GhafPlaces.isGeneric(merchant ?? "") ? "" : (merchant ?? ""),
                            theme: theme, languageCode: languageCode) { item in
                if let item {
                    GhafPlaces.remember(item, merchant: merchant ?? "", transactionID: transaction.id)
                    place = item
                } else {
                    GhafPlaces.clearPlace(merchant: merchant ?? "", transactionID: transaction.id)
                    place = nil
                }
                lookupDone = true
            }
        }
    }

    private func placeCard(_ item: MKMapItem) -> some View {
        let coordinate = item.placemark.coordinate
        let displayName = item.name ?? merchant ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            // A fixed preview: Directions and the other buttons below handle navigation.
            Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 900)), interactionModes: []) {
                Marker(displayName, systemImage: "bag.fill", coordinate: coordinate).tint(theme.accent)
            }
            .mapControlVisibility(.hidden)
            .environment(\.colorScheme, theme.isDark ? .dark : .light)
            .frame(height: 170)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName).font(GhafTypography.heading(18, languageCode: languageCode))
                        .foregroundStyle(theme.primaryText)
                    if let address = item.placemark.title {
                        Text(address).font(GhafTypography.body(13, languageCode: languageCode))
                            .foregroundStyle(theme.secondaryText).lineLimit(2)
                    }
                }
                HStack(spacing: 8) {
                    placeAction(ar ? "الاتجاهات" : "Directions", "arrow.triangle.turn.up.right.diamond.fill") {
                        GhafMapsAppPicker.openDirections(to: item, preference: mapsAppPreference)
                    }
                    if let phone = item.phoneNumber,
                       let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                        placeAction(ar ? "اتصال" : "Call", "phone.fill") { openURL(url) }
                    }
                    placeAction(ar ? "تغيير المكان" : "Change place", "mappin.and.ellipse") { choosingPlace = true }
                }
                Text(ar ? "قد لا يظهر موقع دقيق. يمكنك تغييره أو إزالته."
                        : "The exact place may be unavailable. You can change or remove it.")
                    .font(GhafTypography.body(11, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(GhafMetrics.cardPadding)
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
                    Text(item.date.formatted(.dateTime.day().month().year().locale(GhafLocale.locale(identifier: languageCode))))
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), fallback: theme.surface)
    }

    /// Spending at a physical place; online services and subscriptions have no shop to show.
    private var canHavePlace: Bool {
        transaction.isSpendingOrIncome && transaction.category != "Subscriptions" && GhafBrand.match(merchant) == nil
    }

    private func load() async {
        guard let merchant else { lookupDone = true; return }
        let name = merchant
        history = ((try? context.fetch(FetchDescriptor<GhafTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [])
            .filter { GhafMerchantAliasStore.displayName($0.rawMerchant ?? $0.merchant) == name }
        guard canHavePlace else { lookupDone = true; return }
        place = await GhafPlaces.place(for: merchant, transactionID: transaction.id,
                                       isManual: transaction.fingerprint.hasPrefix("manual-")
                                           || (transaction.fingerprint.hasPrefix("voice-") && GhafPlaces.hasSavedPlace(transactionID: transaction.id)),
                                       purchaseDate: transaction.date)
        lookupDone = true
    }
}

/// Search Apple Maps for the real place, nearest first, with the results on a map; the choice is remembered.
struct GhafPlacePicker: View {
    @Environment(\.dismiss) private var dismiss
    let initialQuery: String
    let theme: GhafTheme
    let languageCode: String
    let onPick: (MKMapItem?) -> Void

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
                Button(ar ? "بلا مكان" : "No place") {
                    onPick(nil)
                    dismiss()
                }
                .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                .padding(.horizontal, 16)
                ScrollView {
                    LazyVStack(spacing: 8) {
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
                                        .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))).locale(GhafLocale.locale(identifier: languageCode))))
                                        .font(GhafTypography.number(12, weight: .semibold))
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                            .frame(minHeight: GhafMetrics.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollContentBackground(.hidden)
                .ghafBackground(theme: theme)
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
