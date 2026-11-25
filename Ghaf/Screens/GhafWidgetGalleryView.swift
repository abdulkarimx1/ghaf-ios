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
        ("Money tip", "A cited daily budgeting tip", false),
        ("Streak", "Your logging streak and the last 7 days", false),
        ("Top places", "Where you spent the most this month", false),
        ("Budget petals", "Category budgets as petals", false)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if !GhafProAccess.hasAccess {
                Button { showPro = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles").font(.system(size: 24, weight: .semibold)).foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ar ? "انضم إلى غاف Pro" : "Join Ghaf Pro").font(GhafTypography.heading(19, languageCode: lang))
                            Text(ar ? "افتح الودجات وخيارات التخصيص" : "Unlock more widgets and customization").font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.forward").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.secondaryText)
                    }
                    .foregroundStyle(theme.primaryText).padding(18).ghafCard(theme: theme)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                }

                Text(ar ? "لإضافة أداة، اضغط مطولًا على الشاشة الرئيسية، ثم اختر تحرير وإضافة أداة." : "To add a widget, touch and hold your Home Screen, tap Edit, then Add Widget.")
                    .font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(Array(widgets.enumerated()), id: \.offset) { index, item in
                        let (name, detail, free) = item
                        let family: WidgetFamily = index.isMultiple(of: 3) ? .systemMedium : .systemSmall
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 5) {
                                Text(ar ? arabicTitle(name) : name)
                                    .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                                    .foregroundStyle(theme.primaryText).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 2)
                                if !free && !GhafProAccess.hasAccess { Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.accent) }
                            }
                            widgetPreview(name, family: family)
                            Text(ar ? arabicDetail(name) : detail)
                                .font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(theme.secondaryText)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gridCellColumns(family == .systemMedium ? 2 : 1)
                    }
                }
            }
            .padding(.horizontal, GhafMetrics.gutter).padding(.vertical, 16)
        }
        .background(theme.background)
        .navigationTitle(ar ? "الودجات" : "Widgets")
        .ghafDirection(lang)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPro) { GhafProSheet(settings: settings, feature: ("Widgets", "الودجات")).ghafDirection(lang) }
    }

    @ViewBuilder private func widgetPreview(_ name: String, family: WidgetFamily) -> some View {
        let snapshot = GhafWidgetSnapshot.sample
        let config = GhafConfigEntry<GhafBalanceConfig>(date: GhafClock.now, snapshot: snapshot, config: GhafBalanceConfig())
        let proLocked = !["Balance", "Spending", "Upcoming payments"].contains(name) && !GhafProAccess.hasAccess
        let height: CGFloat = 158
        Group {
            switch name {
            case "Balance": GhafBalanceView(galleryFamily: family, entry: config)
            case "Spending": GhafSpendingView(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot, config: GhafSpendingConfig()))
            case "Upcoming payments": GhafBillsView(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot, config: GhafBillsConfig()))
            case "Today": GhafTodayView(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot, config: GhafTodayConfig()))
            case "Latest transaction": GhafRecentView(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot, config: GhafRecentConfig()))
            case "Budget": GhafBudgetWidgetView(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot, config: GhafBudgetConfig()))
            case "Where it went": GhafCategoriesView(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot, config: GhafCategoriesConfig()))
            case "Trends": GhafTrendsView(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot, config: GhafTrendsConfig()))
            case "Streak": GhafStreakView(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot))
            case "Top places": GhafTopPlacesView(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot))
            case "Budget petals": GhafBudgetPetalsView(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot))
            default:
                PremiumTile(galleryFamily: family, entry: .init(date: GhafClock.now, snapshot: snapshot,
                                         tip: .init(id: 0, en: "Plan a small weekly savings goal and track it.", ar: "حدّد هدفًا أسبوعيًا صغيرًا للادخار وتابعه.", source: "CFPB", url: "https://www.consumerfinance.gov/")),
                            title: name, symbol: name == "Quick add" ? "plus" : name == "Ask Ghaf" ? "mic.fill" : "lightbulb.fill",
                            url: URL(string: name == "Money tip" ? "ghaf://money-tip?source=https%3A%2F%2Fwww.consumerfinance.gov%2F" : name == "Quick add" ? "ghaf://add-transaction" : "ghaf://ai/type")!)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .padding(8)
        .background { GhafWidgetBackground(tile: GhafTile(.ink, snapshot), enabled: false) }
        // V17: everyone sees every widget; only using a Pro one needs Pro (lock on the title, tap opens Pro).
        .contentShape(Rectangle())
        .onTapGesture { if proLocked { showPro = true } }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(family == .systemSmall ? "Small" : family == .systemMedium ? "Medium" : "Large")")
    }

    private func arabicTitle(_ value: String) -> String {
        ["Balance":"الرصيد", "Spending":"المصروف", "Upcoming payments":"الدفعات القادمة", "Today":"اليوم", "Latest transaction":"آخر عملية", "Budget":"الميزانية", "Where it went":"أين صُرف المال", "Trends":"الاتجاهات", "Quick add":"إضافة سريعة", "Ask Ghaf":"اسأل غاف", "Money tip":"نصيحة مالية", "Streak":"السلسلة", "Top places":"أكثر الأماكن صرفاً", "Budget petals":"بتلات الميزانية"][value] ?? value
    }
    private func arabicDetail(_ value: String) -> String {
        ["Balance":"إجمالي الأرصدة", "Spending":"المصروف في الفترة المحددة", "Upcoming payments":"الاشتراكات المستحقة قريبًا", "Today":"مصروف اليوم حسب الفئة", "Latest transaction":"أحدث عملية سجّلها غاف", "Budget":"التقدم في الميزانية", "Where it went":"أعلى فئات الإنفاق", "Trends":"الإنفاق عبر الوقت", "Quick add":"سجّل عملية", "Ask Ghaf":"افتح غاف AI لكتابة سؤالك", "Money tip":"نصيحة مالية موثوقة مع مصدرها", "Streak":"سلسلتك في تسجيل العمليات وآخر ٧ أيام", "Top places":"أكثر الأماكن في المصروف هذا الشهر", "Budget petals":"ميزانيات الفئات على شكل بتلات"][value] ?? value
    }
}
