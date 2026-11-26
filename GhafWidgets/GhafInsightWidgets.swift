import WidgetKit
import SwiftUI

// 1.31 widgets: Streak, Top places, Budget petals. Every value comes from the snapshot the app writes.

private func insightBackground(_ entry: GhafEntry) -> some View {
    GhafWidgetBackground(tile: GhafTile(.ink, entry.snapshot), enabled: entry.snapshot?.glass ?? false)
}

// MARK: Streak

struct GhafStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhafStreak", provider: GhafProvider()) { entry in
            GhafStreakView(entry: entry)
                .widgetURL(URL(string: "ghaf://home"))
                .containerBackground(for: .widget) { insightBackground(entry) }
                .modifier(GhafWidgetProLock(required: true, isArabic: entry.snapshot?.arabic) {
                    GhafStreakView(entry: .init(date: entry.date, snapshot: .proPreview(arabic: entry.snapshot?.arabic)))
                })
        }
        .configurationDisplayName("Streak")
        .description("Your logging streak and the last 7 days.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct GhafStreakView: View {
    @Environment(\.widgetFamily) private var systemFamily
    var galleryFamily: WidgetFamily? = nil
    private var family: WidgetFamily { galleryFamily ?? systemFamily }
    let entry: GhafEntry

    var body: some View {
        let tile = GhafTile(.ink, entry.snapshot)
        if let s = entry.snapshot, let streak = s.streak {
            // The app rewrites on every transaction: a day after the last write the streak can only still be alive
            // (shifted a day), two days after it is over.
            let calendar = Calendar.current
            let passed = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: s.updated), to: calendar.startOfDay(for: entry.date)).day ?? 0)
            let days = passed >= 2 ? 0 : streak.days
            let week = Array(streak.week.dropFirst(min(passed, 7))) + Array(repeating: false, count: min(passed, 7))
            let spoken = text(s, "\(days) day streak", "سلسلة \(days) يوم")
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "flame.fill").font(.system(size: 13, weight: .semibold))
                        Text("\(days)").font(ghafNumberFont(20, weight: .bold)).minimumScaleFactor(0.6)
                    }
                }.accessibilityLabel(spoken)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Caption(value: text(s, "Streak", "السلسلة"))
                    Text(text(s, "\(days) days", "\(days) يوم")).font(.headline)
                    HStack(spacing: 3) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, on in
                            Capsule().fill(on ? Color.primary : Color.primary.opacity(0.25)).frame(height: 6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
                .accessibilityElement(children: .ignore).accessibilityLabel(spoken)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "flame.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(tile.highlight)
                        Spacer()
                        Caption(value: text(s, "Streak", "السلسلة")).foregroundStyle(tile.dim)
                    }
                    Spacer(minLength: 0)
                    Text("\(days)").font(ghafNumberFont(44, weight: .heavy)).tracking(-1)
                        .foregroundStyle(tile.foreground).minimumScaleFactor(0.5).lineLimit(1)
                    Text(text(s, days == 1 ? "day" : "days", "يوم")).font(.system(size: 11, weight: .bold)).foregroundStyle(tile.highlight)
                    HStack(spacing: 4) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, on in
                            Capsule().fill(on ? tile.highlight : tile.foreground.opacity(0.14)).frame(height: 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
                .accessibilityElement(children: .ignore).accessibilityLabel(spoken)
            }
        } else {
            OpenGhaf(ink: family.isAccessory ? .primary : tile.foreground)
        }
    }
}

// MARK: Top places

struct GhafTopPlacesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhafTopPlaces", provider: GhafProvider()) { entry in
            GhafTopPlacesView(entry: entry)
                .widgetURL(URL(string: "ghaf://transactions"))
                .containerBackground(for: .widget) { insightBackground(entry) }
                .modifier(GhafWidgetProLock(required: true, isArabic: entry.snapshot?.arabic) {
                    GhafTopPlacesView(entry: .init(date: entry.date, snapshot: .proPreview(arabic: entry.snapshot?.arabic)))
                })
        }
        .configurationDisplayName("Top places")
        .description("The areas you spent the most in this month.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GhafTopPlacesView: View {
    @Environment(\.widgetFamily) private var systemFamily
    var galleryFamily: WidgetFamily? = nil
    private var family: WidgetFamily { galleryFamily ?? systemFamily }
    let entry: GhafEntry

    var body: some View {
        let tile = GhafTile(.ink, entry.snapshot)
        if let s = entry.snapshot {
            // Spending is for the month the app wrote; after that month ends nothing is known yet.
            let places = s.month.map { entry.date >= $0.end } == true ? [] : (s.places ?? [])
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 16, weight: .semibold)).foregroundStyle(tile.highlight)
                    Spacer()
                    Caption(value: text(s, "Top places", "أكثر الأماكن صرفاً")).foregroundStyle(tile.dim)
                }
                Spacer(minLength: 0)
                if places.isEmpty {
                    Text(text(s, "Places appear after a transaction is saved with a location.", "تظهر الأماكن بعد حفظ عملية مع موقعها."))
                        .font(.caption.weight(.semibold)).foregroundStyle(tile.dim).lineLimit(3)
                } else {
                    ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                        HStack(spacing: 6) {
                            Text(place.name).font(.system(size: family == .systemSmall ? 12 : 14, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(family == .systemSmall && !s.hidden ? s.whole(place.amount) : s.money(place.amount, currency: s.currency))
                                .font(.system(size: family == .systemSmall ? 12 : 14, weight: .bold)).foregroundStyle(tile.highlight)
                                .lineLimit(1).minimumScaleFactor(0.6).privacySensitive()
                        }
                    }
                }
            }
            .foregroundStyle(tile.foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
        } else {
            OpenGhaf(ink: tile.foreground)
        }
    }
}

// MARK: Budget petals

struct GhafBudgetPetalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhafBudgetPetals", provider: GhafProvider()) { entry in
            GhafBudgetPetalsView(entry: entry)
                .widgetURL(URL(string: "ghaf://insights"))
                .containerBackground(for: .widget) { insightBackground(entry) }
                .modifier(GhafWidgetProLock(required: true, isArabic: entry.snapshot?.arabic) {
                    GhafBudgetPetalsView(entry: .init(date: entry.date, snapshot: .proPreview(arabic: entry.snapshot?.arabic)))
                })
        }
        .configurationDisplayName("Budget petals")
        .description("Category budgets as petals, filled by what you spent.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GhafBudgetPetalsView: View {
    @Environment(\.widgetFamily) private var systemFamily
    var galleryFamily: WidgetFamily? = nil
    private var family: WidgetFamily { galleryFamily ?? systemFamily }
    let entry: GhafEntry

    var body: some View {
        let tile = GhafTile(.ink, entry.snapshot)
        if let s = entry.snapshot {
            let petals = s.petals ?? []
            let over = s.overColor.map { Color(ghafHex: $0) } ?? Color(ghafHex: 0xFF7A6B)
            HStack(spacing: 12) {
                if petals.isEmpty {
                    Text(text(s, "Set category budgets in Ghaf", "حدد ميزانيات الفئات في غاف"))
                        .font(.caption.weight(.semibold)).foregroundStyle(tile.dim).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geometry in
                        let diameter = min(geometry.size.width, geometry.size.height)
                        let step = 360.0 / Double(petals.count)
                        let gap = 3 / 150.0 * 180 / .pi // the Budget screen's 3 pt gap on its ~150 pt radius, so proportions match
                        ZStack {
                            ForEach(Array(petals.enumerated()), id: \.offset) { index, petal in
                                let start = -90 + Double(index) * step + gap / 2
                                let end = -90 + Double(index + 1) * step - gap / 2
                                let color = petal.over ? over : tile.highlight
                                GhafPetalSegment(start: start, end: end, inner: 0.16, outer: 1).fill(color.opacity(tile.isDark ? 0.25 : 0.18))
                                GhafPetalSegment(start: start, end: end, inner: 0.16, outer: CGFloat(petal.fill)).fill(color)
                            }
                        }
                        .frame(width: diameter, height: diameter)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    if family == .systemMedium {
                        VStack(alignment: .leading, spacing: 4) {
                            Caption(value: text(s, "Budget petals", "بتلات الميزانية")).foregroundStyle(tile.dim)
                            ForEach(Array(petals.prefix(4).enumerated()), id: \.offset) { _, petal in
                                HStack(spacing: 6) {
                                    Circle().fill(petal.over ? over : tile.highlight).frame(width: 7, height: 7)
                                    Text(petal.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Spacer(minLength: 2)
                                    if !s.hidden {
                                        Text(NSDecimalNumber(decimal: petal.spent / petal.budget).doubleValue.formatted(.percent.precision(.fractionLength(0)).locale(s.locale)))
                                            .font(.system(size: 12, weight: .bold)).foregroundStyle(petal.over ? over : tile.dim)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .foregroundStyle(tile.foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(petals.map { "\($0.name)\($0.over ? text(s, ", over budget", "، تجاوز الميزانية") : "")" }.joined(separator: ", "))
        } else {
            OpenGhaf(ink: tile.foreground)
        }
    }
}
