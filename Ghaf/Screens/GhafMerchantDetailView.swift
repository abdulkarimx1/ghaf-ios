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
                HStack {
                    Text(ar ? "رسائل البنك لا تتضمن الموقع، فهذا تطابق من خرائط Apple أو اختيارك."
                            : "Bank messages don't include a location, so this is an Apple Maps match or your choice.")
                        .font(GhafTypography.body(10, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                    Spacer(minLength: 8)
                    Button(ar ? "مكان خاطئ؟" : "Wrong place?") { choosingPlace = true }
                        .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
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

/// Search Apple Maps for the real place, nearby first; the choice is remembered.
struct GhafPlacePicker: View {
    @Environment(\.dismiss) private var dismiss
    let initialQuery: String
    let theme: GhafTheme
    let languageCode: String
    let onPick: (MKMapItem) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    private var ar: Bool { languageCode == "ar" }

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !searching {
                    Text(query.isEmpty ? (ar ? "اكتب اسم المتجر أو المطعم." : "Type the shop or restaurant name.")
                                       : (ar ? "لا نتائج قريبة." : "No nearby results."))
                        .foregroundStyle(theme.secondaryText)
                }
                ForEach(results, id: \.self) { item in
                    Button {
                        onPick(item)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name ?? "").font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                            if let address = item.placemark.title {
                                Text(address).font(GhafTypography.body(12, languageCode: languageCode))
                                    .foregroundStyle(theme.secondaryText).lineLimit(2)
                            }
                        }
                    }
                }
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
                results = (try? await GhafPlaces.search(query)) ?? []
                searching = false
            }
            .onAppear {
                query = initialQuery
                // Asked here, where the reason is obvious: nearby places for this purchase.
                GhafPlaces.requestLocationIfUndecided()
            }
        }
    }
}
