import SwiftUI
import WidgetKit

struct GhafWidgetGalleryView: View {
    let settings: GhafSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPro = false

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }
    private let widgets: [(String, String, Bool)] = [
        ("Balance", "Your total balance and recent activity", true),
        ("Spending", "Spending for the selected period", true),
        ("Upcoming payments", "Subscriptions due soon", true),
        ("Today", "Today's spending by category", false),
        ("Latest transaction", "The last transaction Ghaf recorded", false),
        ("Budget", "Budget progress", false),
        ("Where it went", "Top spending categories", false),
        ("Trends", "Spending over time", false),
        ("Quick add", "Add a transaction", false),
        ("Ask Ghaf", "Open Ghaf AI ready to type", false),
        ("Money tip", "A cited daily budgeting tip", false)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Button { showPro = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles").font(.system(size: 24, weight: .semibold)).foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ar ? "انضم إلى غاف Pro" : "Join Ghaf Pro").font(GhafTypography.heading(19, languageCode: lang))
                            Text(ar ? "افتح الأدوات والخيارات الإضافية" : "Unlock more widgets and customization").font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.forward").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.secondaryText)
                    }
                    .foregroundStyle(theme.primaryText).padding(18).ghafCard(theme: theme)
                }.buttonStyle(.plain)

                Text(ar ? "لإضافة أداة، اضغط مطولًا على الشاشة الرئيسية، ثم اختر تحرير وإضافة أداة." : "To add a widget, touch and hold your Home Screen, tap Edit, then Add Widget.")
                    .font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)

                LazyVStack(spacing: 14) {
                    ForEach(widgets, id: \.0) { name, detail, free in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(ar ? arabicTitle(name) : name).font(GhafTypography.heading(17, languageCode: lang)).foregroundStyle(theme.primaryText)
                                Spacer()
                                Text(free ? (ar ? "مجانية" : "Free") : "Pro")
                                    .font(GhafTypography.body(11, languageCode: lang, weight: .semibold))
                                    .foregroundStyle(free ? theme.secondaryText : theme.accent)
                                    .padding(.horizontal, 10).padding(.vertical, 6).background(theme.elevatedSurface, in: Capsule())
                            }
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach([WidgetFamily.systemSmall, .systemMedium, .systemLarge], id: \.self) { family in
                                        widgetPreview(name, family: family)
                                    }
                                }
                            }.scrollIndicators(.hidden)
                            Text(ar ? arabicDetail(name) : detail).font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        }
                        .padding(14).ghafCard(theme: theme)
                    }
                }
            }
            .padding(.horizontal, GhafMetrics.gutter).padding(.vertical, 16)
        }
        .background(theme.background)
        .navigationTitle(ar ? "الأدوات" : "Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPro) { GhafProSheet(settings: settings, feature: ("Widgets", "الأدوات")).ghafDirection(lang) }
    }

    @ViewBuilder private func widgetPreview(_ name: String, family: WidgetFamily) -> some View {
        let snapshot = GhafWidgetSnapshot.sample
        let config = GhafConfigEntry<GhafBalanceConfig>(date: .now, snapshot: snapshot, config: GhafBalanceConfig())
        let proLocked = !["Balance", "Spending", "Upcoming payments"].contains(name) && !GhafWidgetProAccess.unlocked
        let size: CGFloat = family == .systemSmall ? 158 : 338
        let height: CGFloat = family == .systemLarge ? 338 : 158
        Group {
            switch name {
            case "Balance": GhafBalanceView(galleryFamily: family, entry: config)
            case "Spending": GhafSpendingView(galleryFamily: family, entry: .init(date: .now, snapshot: snapshot, config: GhafSpendingConfig()))
            case "Upcoming payments": GhafBillsView(galleryFamily: family, entry: .init(date: .now, snapshot: snapshot, config: GhafBillsConfig()))
            case "Today": GhafTodayView(galleryFamily: family, entry: .init(date: .now, snapshot: snapshot, config: GhafTodayConfig()))
            case "Latest transaction": GhafRecentView(galleryFamily: family, entry: .init(date: .now, snapshot: snapshot, config: GhafRecentConfig()))
            case "Budget": GhafBudgetWidgetView(galleryFamily: family, entry: .init(date: .now, snapshot: snapshot, config: GhafBudgetConfig()))
            case "Where it went": GhafCategoriesView(galleryFamily: family, entry: .init(date: .now, snapshot: snapshot, config: GhafCategoriesConfig()))
            case "Trends": GhafTrendsView(galleryFamily: family, entry: .init(date: .now, snapshot: snapshot, config: GhafTrendsConfig()))
            default:
                PremiumTile(galleryFamily: family, entry: .init(date: .now, snapshot: snapshot,
                                         tip: .init(id: 0, en: "Plan a small weekly savings goal and track it.", ar: "حدّد هدفًا أسبوعيًا صغيرًا للادخار وتابعه.", source: "CFPB", url: "https://www.consumerfinance.gov/")),
                            title: name, symbol: name == "Quick add" ? "plus" : name == "Ask Ghaf" ? "mic.fill" : "lightbulb.fill",
                            url: URL(string: name == "Money tip" ? "ghaf://money-tip?source=https%3A%2F%2Fwww.consumerfinance.gov%2F" : name == "Quick add" ? "ghaf://add-transaction" : "ghaf://ai/type")!)
            }
        }
        .frame(width: size, height: height)
        .padding(12)
        .background { GhafWidgetBackground(tile: GhafTile(.ink, snapshot), enabled: false) }
        .blur(radius: proLocked ? 7 : 0)
        .overlay {
            if proLocked {
                Button { showPro = true } label: {
                    VStack(spacing: 4) {
                        Text("Pro").font(.system(size: 13, weight: .bold, design: .rounded)).padding(.horizontal, 12).padding(.vertical, 6).background(ink, in: Capsule())
                        Text(ar ? "افتح غاف Pro" : "Unlock with Ghaf Pro").font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                    }.foregroundStyle(paper).padding(7).background(ink.opacity(0.96), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(family == .systemSmall ? "Small" : family == .systemMedium ? "Medium" : "Large")")
    }

    private func arabicTitle(_ value: String) -> String {
        ["Balance":"الرصيد", "Spending":"الإنفاق", "Upcoming payments":"الدفعات القادمة", "Today":"اليوم", "Latest transaction":"آخر عملية", "Budget":"الميزانية", "Where it went":"أين صُرف المال", "Trends":"الاتجاهات", "Quick add":"إضافة سريعة", "Ask Ghaf":"اسأل غاف", "Money tip":"نصيحة مالية"][value] ?? value
    }
    private func arabicDetail(_ value: String) -> String {
        ["Balance":"إجمالي الأرصدة", "Spending":"إنفاق الفترة المحددة", "Upcoming payments":"الاشتراكات المستحقة قريبًا", "Today":"إنفاق اليوم حسب الفئة", "Latest transaction":"أحدث عملية سجّلها غاف", "Budget":"التقدم في الميزانية", "Where it went":"أعلى فئات الإنفاق", "Trends":"الإنفاق عبر الوقت", "Quick add":"سجّل عملية", "Ask Ghaf":"افتح غاف AI لكتابة سؤالك", "Money tip":"نصيحة مالية موثوقة مع مصدرها"][value] ?? value
    }
}
