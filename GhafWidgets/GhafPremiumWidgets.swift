import AppIntents
import SwiftUI
import WidgetKit

struct PremiumEntry: TimelineEntry {
    let date: Date
    let snapshot: GhafWidgetSnapshot?
    let tip: GhafMoneyTip?
}

private struct PremiumProvider: TimelineProvider {
    func placeholder(in context: Context) -> PremiumEntry { .init(date: .now, snapshot: .sample, tip: nil) }
    func getSnapshot(in context: Context, completion: @escaping (PremiumEntry) -> Void) {
        completion(.init(date: .now, snapshot: context.isPreview ? .sample : GhafWidgetSnapshot.load(), tip: GhafMoneyTip.today))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PremiumEntry>) -> Void) {
        Task {
            let tips = await GhafMoneyTip.refresh()
            let day = Calendar.current.startOfDay(for: .now)
            let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? .now.addingTimeInterval(86_400)
            let tip = tips.isEmpty ? GhafMoneyTip.today : tips[(Calendar.current.ordinality(of: .day, in: .era, for: .now).map { max(0, $0 - 1) } ?? 0) % tips.count]
            completion(Timeline(entries: [.init(date: .now, snapshot: GhafWidgetSnapshot.load(), tip: tip)], policy: .after(next)))
        }
    }
}

struct PremiumTile: View {
    var galleryFamily: WidgetFamily? = nil
    let entry: PremiumEntry
    let title: String
    let symbol: String
    let url: URL
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.locale) private var locale
    private var family: WidgetFamily { galleryFamily ?? systemFamily }
    private var tile: GhafTile { GhafTile(.ink, entry.snapshot) }
    private var isArabic: Bool { entry.snapshot?.arabic ?? (locale.language.languageCode?.identifier == "ar") }
    private var localizedTitle: String {
        guard isArabic else { return title }
        switch title {
        case "Quick add": return "إضافة سريعة"
        case "Ask Ghaf": return "اسأل غاف"
        default: return title
        }
    }

    @ViewBuilder private func layout(for value: PremiumEntry) -> some View {
        let contentTile = GhafTile(.ink, value.snapshot)
        let arabic = value.snapshot?.arabic == true
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(contentTile.highlight)
                Spacer()
                if family != .systemSmall { Caption(value: localizedTitle).foregroundStyle(contentTile.dim) }
            }
            Spacer(minLength: 0)
            if title == "Money tip", let tip = value.tip {
                Text(arabic ? tip.ar : tip.en).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(family == .systemLarge ? 5 : 3)
                Text("\(tip.source) ↗").font(.system(size: 10, weight: .medium)).foregroundStyle(contentTile.dim)
            } else {
                Text(localizedTitle).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(2)
                if title == "Ask Ghaf" {
                    Image(systemName: "waveform").font(.system(size: 25, weight: .medium)).foregroundStyle(contentTile.highlight)
                } else {
                    Text(arabic ? "سجّل عملية جديدة" : "Add a transaction").font(.caption).foregroundStyle(contentTile.dim)
                }
            }
        }
        .padding(14)
        .foregroundStyle(contentTile.foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .fontDesign(.default)
        .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
    }

    var body: some View {
        let destination = title == "Money tip" ? entry.tip.flatMap { URL(string: $0.url) } ?? url : url
        Link(destination: destination) { layout(for: entry) }
            .containerBackground(for: .widget) { GhafWidgetBackground(tile: tile, enabled: false) }
            .modifier(GhafWidgetProLock(required: true, isArabic: isArabic) {
                layout(for: PremiumEntry(date: entry.date, snapshot: .proPreview(arabic: isArabic), tip: nil))
            })
    }
}

struct GhafQuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhafQuickAdd", provider: PremiumProvider()) { entry in
            PremiumTile(entry: entry, title: "Quick add", symbol: "plus", url: URL(string: "ghaf://add-transaction")!)
        }
        .configurationDisplayName("Quick add")
        .description("Open Ghaf to add a transaction.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GhafAskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhafAsk", provider: PremiumProvider()) { entry in
            PremiumTile(entry: entry, title: "Ask Ghaf", symbol: "mic.fill", url: URL(string: "ghaf://ai/voice")!)
        }
        .configurationDisplayName("Ask Ghaf")
        .description("Open Ghaf AI in voice mode.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GhafMoneyTipWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhafMoneyTip", provider: PremiumProvider()) { entry in
            PremiumTile(entry: entry, title: "Money tip", symbol: "lightbulb.fill", url: URL(string: "https://www.consumerfinance.gov/consumer-tools/budgeting/")!)
        }
        .configurationDisplayName("Money tip")
        .description("A daily budgeting tip with a source link.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
