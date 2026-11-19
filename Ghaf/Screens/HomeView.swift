import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private struct HomeAccountsZoomSource: ViewModifier {
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.matchedTransitionSource(id: "home-accounts", in: namespace)
        } else {
            content
        }
    }
}
import GhafCore
import AppIntents

struct GhafHomeView: View {
    @Namespace private var accountsNamespace
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(GhafTabRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]
    @Query(sort: \GhafAccount.sortOrder)
    private var accounts: [GhafAccount]

    @State private var showQuickAdd = false
    @State private var showVoiceEntry = false
    @State private var showAutomationGuide = false
    @State private var showSalaryCheckIn = false
    @State private var showAccounts = false
    @State private var showBackupImporter = false
    @State private var backupImportError: String?
    @State private var showInsights = false
    @State private var showReview = false
    @State private var selectedTransaction: GhafTransaction?
    @AppStorage(GhafAutomationStatus.lastRunKey) private var automationLastRun: Double = 0
    @AppStorage(GhafAutomationStatus.walletRunKey) private var walletLastRun: Double = 0
    @AppStorage(GhafAutomationStatus.setupCompletedKey) private var automationSetupCompleted: Double = 0
    @AppStorage(GhafAutomationStatus.warningDismissedUntilKey) private var automationWarningDismissedUntil: Double = 0
    /// Observed so the weekly figures redraw as soon as the week start changes.
    @AppStorage(GhafCalendar.weekStartKey) private var weekStart = 0
    @AppStorage(GhafFormat.hideBalancesKey) private var hideBalances = false
    @State private var showSubscriptions = false
    /// Weekly used to be the calendar week; tell the user once that it's now the last 7 days.
    @AppStorage("ghaf.seenRollingWeekNote") private var seenRollingWeekNote = false
    @State private var activityPeriodIndex = 0

    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    /// Everything Home shows, derived in one pass per render instead of once per view.
    private struct Summary {
        var accountBalances: [UUID: Decimal] = [:]
        var balances: [GhafCurrencyBalance] = []
        var mainCurrency = ""
        var spent: Decimal = 0
        var income: Decimal = 0
        var count = 0
        var topCategory: (name: String, amount: Decimal)?
        /// Spending by category, largest first.
        var categories: [(name: String, amount: Decimal)] = []
        var reviewCount = 0
        /// The selected period, and spending in the one before it (same currency rules).
        var interval: DateInterval?
        var previousSpent: Decimal = 0
    }

    private func makeSummary() -> Summary {
        var summary = Summary()
        summary.accountBalances = GhafAccountBalanceCalculator.balances(accounts: accounts, transactions: transactions)
        summary.balances = GhafAccountBalanceCalculator.balancesByCurrency(accounts: accounts, balances: summary.accountBalances)
        let main = summary.balances.contains { $0.currency == settings.currency }
            ? settings.currency : (summary.balances.first?.currency ?? settings.currency)
        summary.mainCurrency = main

        let calendar = GhafCalendar.current
        // Day and month are calendar periods. Week is the last 7 days including today, so it never
        // looks empty just because a new calendar week began this morning.
        let interval: DateInterval?
        let previous: DateInterval?
        if activityPeriodIndex == 1 {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
            let start = calendar.date(byAdding: .day, value: -7, to: tomorrow)!
            interval = DateInterval(start: start, end: tomorrow)
            previous = DateInterval(start: calendar.date(byAdding: .day, value: -7, to: start)!, end: start)
        } else {
            let component: Calendar.Component = activityPeriodIndex == 0 ? .day : .month
            interval = calendar.dateInterval(of: component, for: .now)
            previous = interval.flatMap { calendar.date(byAdding: component, value: -1, to: $0.start) }
                .flatMap { calendar.dateInterval(of: component, for: $0) }
        }
        summary.interval = interval
        var byCategory: [String: Decimal] = [:]
        for transaction in transactions {
            if transaction.needsReview { summary.reviewCount += 1 }
            guard let interval else { continue }
            let date = transaction.date
            if date >= interval.end { continue }
            if date < interval.start {
                if let previous, date >= previous.start, date < previous.end,
                   transaction.currency == main, transaction.isSpendingOrIncome, transaction.isExpense {
                    summary.previousSpent += transaction.spendingAmount
                }
                continue
            }
            summary.count += 1
            guard transaction.currency == main, transaction.isSpendingOrIncome else { continue }
            if transaction.isExpense {
                summary.spent += transaction.spendingAmount
                byCategory[transaction.category, default: 0] += transaction.spendingAmount
            } else {
                summary.income += transaction.incomeAmount
            }
        }
        summary.categories = byCategory.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        summary.topCategory = summary.categories.first
        return summary
    }

    var body: some View {
        let summary = makeSummary()
        NavigationStack {
            ScrollView {
                VStack(spacing: GhafMetrics.sectionSpacing) {
                    header.ghafEntrance(0)
                    if automationNeedsAttention && Date.now.timeIntervalSince1970 >= automationWarningDismissedUntil {
                        automationWarningCard
                    }
                    if accounts.contains(where: { !$0.isArchived }) {
                        balanceCard(summary).ghafEntrance(1)
                        actionRow(summary).ghafEntrance(2)
                        insightCard(summary).ghafEntrance(3)
                        recentActivity.ghafEntrance(4)
                    } else {
                        emptyAccountsState
                    }
                }
                .ghafScreenPadding()
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ghafBackground(theme: theme)
            .ghafStatusBarFade(theme: theme)
#if DEBUG
            .onAppear {
                if GhafScreenshotFixture.enabled, GhafScreenshotFixture.screen == "amount-pad" { showQuickAdd = true }
            }
#endif
            .onChange(of: router.homeReselects) { _, _ in
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) { activityPeriodIndex = (activityPeriodIndex + 1) % 3 }
            }
            .sensoryFeedback(.selection, trigger: activityPeriodIndex)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showAccounts) { GhafAccountsView(settings: settings, zoomNamespace: accountsNamespace) }
            .sheet(isPresented: $showQuickAdd) { GhafQuickAddView(settings: settings).ghafDirection(settings.languageCode) }
            .sheet(isPresented: $showVoiceEntry) {
                NavigationStack { GhafVoiceEntryView(settings: settings) }.ghafDirection(settings.languageCode)
            }
            .sheet(isPresented: $showSubscriptions) {
                GhafSubscriptionsView(settings: settings).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showInsights) {
                GhafInsightsView(settings: settings).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showReview) {
                GhafReviewInboxView(settings: settings).presentationDragIndicator(.visible).ghafDirection(settings.languageCode)
            }
            .sheet(item: $selectedTransaction) { transaction in
                GhafTransactionDetailView(transaction: transaction, settings: settings, accounts: accounts.filter { !$0.isArchived })
                    .presentationDragIndicator(.visible).ghafDirection(settings.languageCode)
            }
            .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    try GhafBackupService.restore(from: url, context: modelContext)
                } catch {
                    backupImportError = error.localizedDescription
                }
            }
            .alert(ar ? "تعذر استيراد النسخة" : "Could not import backup", isPresented: Binding(
                get: { backupImportError != nil }, set: { if !$0 { backupImportError = nil } }
            )) {
                Button(ar ? "حسناً" : "OK", role: .cancel) { backupImportError = nil }
            } message: { Text(backupImportError ?? "") }
            .sheet(isPresented: $showAutomationGuide) {
                NavigationStack {
                    GhafAutomationGuideView(settings: settings)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(ar ? "تم" : "Done") { showAutomationGuide = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showSalaryCheckIn) {
                GhafSalaryCheckInView(settings: settings, accounts: accounts).ghafDirection(settings.languageCode)
            }
            .onAppear(perform: checkSalaryDue)
            .task {
                if settings.salaryEnabled == true, settings.salaryReminderEnabled == true,
                   let day = settings.salaryDay {
                    try? await GhafSalaryReminderService.scheduleNext(salaryDay: day, languageCode: settings.languageCode)
                }
            }
        }
    }

    private var ar: Bool { settings.languageCode == "ar" }
    private var lang: String { settings.languageCode }
    private var messageRunHistory: [Double] { UserDefaults.standard.array(forKey: GhafAutomationStatus.messageHistoryKey) as? [Double] ?? [] }
    private var walletRunHistory: [Double] { UserDefaults.standard.array(forKey: GhafAutomationStatus.walletHistoryKey) as? [Double] ?? [] }

    private var emptyAccountsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.accent)
            Text(ar ? "أضف حسابك الأول" : "Add your first account")
                .font(GhafTypography.heading(22, languageCode: lang))
                .foregroundStyle(theme.primaryText)
            Text(ar ? "أضف حساباً لعرض رصيدك ومتابعة عملياتك." : "Add an account to see your balance and track activity.")
                .font(GhafTypography.body(15, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            Button { showAccounts = true } label: {
                Label(ar ? "إضافة حساب" : "Add account", systemImage: "plus")
                    .frame(maxWidth: .infinity).frame(height: 56)
            }
            .ghafProminentButton(theme: theme, languageCode: lang)
            Button { showBackupImporter = true } label: {
                Label(ar ? "استيراد نسخة غاف الاحتياطية" : "Import Ghaf backup", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity).frame(height: 56)
            }
            .ghafGlassButton(theme: theme, languageCode: lang)
        }
        .padding(GhafMetrics.heroPadding)
        .frame(maxWidth: .infinity, minHeight: 320)
        .ghafGlassHero(theme: theme, radius: 28)
        .multilineTextAlignment(.center)
    }

    private var automationNeedsAttention: Bool {
        let now = Date.now.timeIntervalSince1970
        guard automationSetupCompleted > 0 else { return false }
        if automationLastRun == 0 { return now - automationSetupCompleted >= 24 * 60 * 60 }
        if walletLastRun > 0, now - walletLastRun >= 14 * 24 * 60 * 60 { return true }
        let runs = (messageRunHistory + walletRunHistory).sorted().suffix(10)
        let gaps = zip(runs, runs.dropFirst()).map { $1 - $0 }.sorted()
        guard !gaps.isEmpty, automationLastRun > 0 else { return false }
        let median = gaps[gaps.count / 2]
        return now - automationLastRun >= max(4 * 24 * 60 * 60, median * 3)
    }

    private var automationWarningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(ar ? "هناك خطوة ناقصة" : "Something is missing", systemImage: "exclamationmark.circle.fill")
                .font(GhafTypography.body(15, languageCode: lang, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Text(ar ? "لا يستطيع غاف فحص الأتمتة مباشرة. لم تصل رسالة حديثاً؛ تحقق من إعداد الاختصار." : "Ghaf can’t inspect your automations directly. No recent run arrived; check your Shortcut setup.")
                .font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
            HStack {
                Button(ar ? "إصلاح الإعداد" : "Fix setup") { showAutomationGuide = true }
                    .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                Spacer()
                Button(ar ? "إخفاء ٧ أيام" : "Dismiss for 7 days") {
                    automationWarningDismissedUntil = Date.now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970
                }
                .font(GhafTypography.body(12, languageCode: lang))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 18), fallback: theme.surface)
    }

    // MARK: Header: greeting, accounts pill, hide-balances eye

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Text(settings.userName.isEmpty ? (ar ? "غاف" : "Ghaf") : settings.userName)
                    .font(GhafTypography.heading(24, languageCode: lang))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            if accounts.contains(where: { !$0.isArchived }) {
                Button { showAccounts = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wallet.bifold.fill").font(.system(size: 13, weight: .bold))
                        Text(ar ? "الحسابات" : "Accounts")
                            .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                        Image(systemName: "chevron.forward").font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 14).frame(height: 40)
                    .ghafGlassShape(theme: theme, shape: Capsule(), fallback: theme.surface)
                    .shadow(color: theme.shadow, radius: 8, y: 3)
                }
                .buttonStyle(.ghafPress)
                .modifier(HomeAccountsZoomSource(namespace: accountsNamespace))
            }
            Button {
                withAnimation(.spring(duration: 0.5, bounce: 0.25)) { hideBalances.toggle() }
            } label: {
                Image(systemName: hideBalances ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 15, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 44, height: 44)
                    .ghafGlassShape(theme: theme, shape: Circle(), fallback: theme.surface)
                    .shadow(color: theme.shadow, radius: 8, y: 3)
            }
            .buttonStyle(.ghafPress)
            .sensoryFeedback(.impact(weight: .medium), trigger: hideBalances)
            .accessibilityLabel(ar ? (hideBalances ? "إظهار الأرصدة" : "إخفاء الأرصدة")
                                   : (hideBalances ? "Show balances" : "Hide balances"))
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if ar { return hour < 12 ? "صباح الخير" : "مساء الخير" }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: Balance card: tap to switch Day / Week / Month

    private var periodName: String {
        ar ? ["اليوم", "آخر ٧ أيام", "هذا الشهر"][activityPeriodIndex]
           : ["Today", "Last 7 days", "This month"][activityPeriodIndex]
    }

    /// The period inside a sentence: "your biggest spend in the last 7 days".
    private var periodPhrase: String {
        ar ? ["اليوم", "في آخر ٧ أيام", "هذا الشهر"][activityPeriodIndex]
           : ["today", "in the last 7 days", "this month"][activityPeriodIndex]
    }

    /// " · 16–22 Nov" for a week or month, so it's clear where the period starts; nothing for a day.
    private func periodRange(_ summary: Summary) -> String {
        guard activityPeriodIndex > 0, let interval = summary.interval else { return "" }
        let formatter = DateIntervalFormatter()
        formatter.locale = Locale(identifier: ar ? "ar_AE" : "en_AE")
        formatter.dateTemplate = "dMMM"
        return " · " + formatter.string(from: interval.start, to: interval.end.addingTimeInterval(-1))
    }

    private var rollingWeekNote: some View {
        Button { withAnimation(.snappy) { seenRollingWeekNote = true } } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle.fill")
                Text(ar ? "تغيّر الأسبوعي: يعرض الآن آخر ٧ أيام بدلاً من أسبوع التقويم."
                        : "Weekly has changed: it now shows the last 7 days instead of the calendar week.")
                    .multilineTextAlignment(.leading)
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(ar ? "اضغط للإخفاء" : "Tap to dismiss")
        .transition(.opacity)
    }

    private func balanceCard(_ summary: Summary) -> some View {
        let main = summary.balances.first { $0.currency == summary.mainCurrency }
        let others = summary.balances.filter { $0.currency != summary.mainCurrency }

        return VStack(spacing: 14) {
            Text(ar ? "إجمالي الرصيد" : "Total balance")
                .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)

            GhafMoneyLabel(amount: main?.amount ?? 0, currency: summary.mainCurrency,
                           languageCode: lang, size: 44, hidden: hideBalances)
                .foregroundStyle(theme.primaryText)

            // Other currencies are listed, never added to the main total.
            ForEach(others) { balance in
                GhafMoneyLabel(amount: balance.amount, currency: balance.currency,
                               languageCode: lang, size: 16, hidden: hideBalances)
                    .foregroundStyle(theme.secondaryText)
            }

            HStack(spacing: 14) {
                changeLine(icon: "arrow.down.right", value: summary.spent, color: theme.debit,
                           label: ar ? "صرفت" : "spent", currency: summary.mainCurrency)
                changeLine(icon: "arrow.up.right", value: summary.income, color: theme.credit,
                           label: ar ? "دخل" : "in", currency: summary.mainCurrency)
            }

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == activityPeriodIndex ? theme.accent : theme.secondaryText.opacity(0.25))
                        .frame(width: index == activityPeriodIndex ? 18 : 6, height: 6)
                }
                Text(periodName + periodRange(summary) + " · \(summary.count) " + (ar ? "عملية" : (summary.count == 1 ? "transaction" : "transactions")))
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .contentTransition(.numericText())
            }

            if activityPeriodIndex == 1 && !seenRollingWeekNote { rollingWeekNote }

            accountStrip(summary)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .ghafGlassHero(theme: theme, radius: 28)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            withAnimation(.snappy(duration: 0.25)) { activityPeriodIndex = (activityPeriodIndex + 1) % 3 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(ar ? "اضغط للتبديل بين اليوم والأسبوع والشهر" : "Tap to switch between day, week and month")
        .sensoryFeedback(.selection, trigger: activityPeriodIndex)
    }

    private func changeLine(icon: String, value: Decimal, color: Color, label: String, currency: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .heavy))
            GhafMoneyLabel(amount: value, currency: currency, languageCode: lang, size: 14, hidden: hideBalances)
            Text(label).font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private func accountStrip(_ summary: Summary) -> some View {
        let open = accounts.filter { !$0.isArchived }
        if !open.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(open) { account in
                        Button { showAccounts = true } label: {
                            VStack(spacing: 2) {
                                Text(account.name)
                                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                                    .foregroundStyle(theme.secondaryText)
                                GhafMoneyLabel(amount: summary.accountBalances[account.id] ?? account.openingBalance,
                                               currency: account.currency, languageCode: lang,
                                               size: 14, hidden: hideBalances)
                                    .foregroundStyle(theme.primaryText)
                            }
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 14, style: .continuous), fallback: theme.elevatedSurface)
                        }
                        .buttonStyle(.ghafPress)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: Big pill actions

    private func actionRow(_ summary: Summary) -> some View {
        HStack(spacing: 10) {
            GhafPillButton(title: ar ? "إضافة" : "Add", icon: "plus", theme: theme, languageCode: lang,
                           prominent: true) { showQuickAdd = true }
            GhafPillButton(title: ar ? "اشتراكات" : "Subs", icon: "repeat", theme: theme,
                           languageCode: lang) { showSubscriptions = true }
            GhafPillButton(title: ar ? "مراجعة" : "Review", icon: "tray.full.fill", theme: theme,
                           languageCode: lang, badge: summary.reviewCount) { showReview = true }
        }
    }

    // MARK: Dark insight card

    private func insightCard(_ summary: Summary) -> some View {
        Button { showInsights = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label((ar ? "التحليلات · " : "Insights · ")
                          + (ar ? ["يومي", "أسبوعي", "شهري"] : ["Daily", "Weekly", "Monthly"])[activityPeriodIndex],
                          systemImage: "chart.pie.fill")
                        .contentTransition(.opacity)
                        .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                        .foregroundStyle(theme.inkText.opacity(0.75))
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(theme.inkText)
                        .frame(width: 34, height: 34)
                        .background(theme.inkText.opacity(0.12), in: Circle())
                }
                if summary.spent > 0 {
                    categoryBar(summary)
                        .id(activityPeriodIndex)
                        .transition(.opacity)
                } else {
                    GhafMoneyText.text(emptyInsight(summary), size: 17)
                        .font(GhafTypography.heading(17, languageCode: lang))
                        .foregroundStyle(theme.inkText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.ink, in: RoundedRectangle(cornerRadius: GhafMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.ghafPress)
    }

    /// Where the money went, as one bar with the categories named under it.
    private func categoryBar(_ summary: Summary) -> some View {
        let total = NSDecimalNumber(decimal: summary.spent).doubleValue
        var slices = Array(summary.categories.prefix(3))
        let rest = summary.categories.dropFirst(3).reduce(Decimal.zero) { $0 + $1.amount }
        if rest > 0 { slices.append((ar ? "أخرى" : "Other", rest)) }
        let shades: [Double] = [0.95, 0.62, 0.4, 0.22]
        func share(_ amount: Decimal) -> Double { NSDecimalNumber(decimal: amount).doubleValue / total }
        return VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                        Capsule().fill(theme.inkText.opacity(shades[index]))
                            .frame(width: max(6, (proxy.size.width - CGFloat(slices.count - 1) * 3) * share(slice.amount)))
                    }
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            VStack(spacing: 7) {
                ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                    HStack(spacing: 8) {
                        Circle().fill(theme.inkText.opacity(shades[index])).frame(width: 8, height: 8)
                        Text(index == 3 && rest > 0 ? slice.name : GhafLocalization.category(slice.name, languageCode: lang))
                            .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.inkText)
                            .lineLimit(1)
                        Spacer()
                        GhafMoneyLabel(amount: slice.amount, currency: summary.mainCurrency, languageCode: lang,
                                       size: 13, hidden: hideBalances)
                            .foregroundStyle(theme.inkText.opacity(0.7))
                        Text("\(Int((share(slice.amount) * 100).rounded()))%")
                            .font(GhafTypography.number(13, weight: .bold))
                            .foregroundStyle(theme.inkText)
                            .frame(minWidth: 38, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Nothing spent yet: say what the period before cost.
    private func emptyInsight(_ summary: Summary) -> String {
        let text = activityPeriodIndex == 1
            ? (ar ? "ما صرفت شيئاً في آخر ٧ أيام." : "Nothing spent in the last 7 days.")
            : (ar ? "ما صرفت شيئاً \(periodName) بعد." : "Nothing spent \(periodPhrase) yet.")
        guard summary.previousSpent > 0 else {
            return text + (ar ? " يوم جميل لمحفظتك." : " A good day for your wallet.")
        }
        let previousName = ar ? ["أمس", "في الأيام السبعة التي قبلها", "الشهر الماضي"][activityPeriodIndex]
                              : ["Yesterday", "In the 7 days before", "Last month"][activityPeriodIndex]
        guard !hideBalances else { return text }
        let amount = GhafFormat.money(summary.previousSpent, currency: summary.mainCurrency, languageCode: lang)
        return text + (ar ? " \(previousName) صرفت \(amount)." : " \(previousName) you spent \(amount).")
    }

    // MARK: Recent activity (a short shortcut; the full list lives in Transactions)

    private var recentActivity: some View {
        VStack(spacing: 10) {
            GhafSectionHeader(title: ar ? "النشاط" : "Activity", theme: theme, languageCode: lang,
                              actionTitle: ar ? "عرض الكل" : "See all") { router.selectedTab = 3 }
            VStack(spacing: 0) {
                let recent = Array(transactions.prefix(4))
                if recent.isEmpty && automationLastRun == 0 {
                    GhafListRow(icon: "bolt.fill", tint: theme.accent,
                                title: ar ? "اربط رسائل البنك" : "Connect your bank messages",
                                subtitle: ar ? "سجّل العمليات تلقائياً عبر الاختصارات" : "Log transactions automatically with Shortcuts",
                                theme: theme, languageCode: lang, chevron: true)
                        .onTapGesture { showAutomationGuide = true }
                } else {
                    ForEach(recent) { transaction in
                        Button { selectedTransaction = transaction } label: {
                            GhafTransactionRow(transaction: transaction, theme: theme, languageCode: lang, hidden: hideBalances)
                        }
                        .buttonStyle(.ghafPress)
                        if transaction.id != recent.last?.id {
                            Divider().overlay(theme.outline).padding(.leading, 58)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .ghafCard(theme: theme)

            if automationLastRun == 0 {
            Button { showAutomationGuide = true } label: {
                GhafListRow(icon: "bolt.fill", tint: theme.accent,
                            title: ar ? "ربط البنك" : "Bank setup",
                            subtitle: ar ? "التقاط العمليات من رسائل البنك" : "Capture transactions from bank messages",
                            theme: theme, languageCode: lang, chevron: true)
                    .padding(.horizontal, 16).padding(.vertical, 4)
                    .ghafCard(theme: theme)
            }
            .buttonStyle(.ghafPress)
            }
        }
    }

    private func checkSalaryDue() {
        guard settings.salaryEnabled == true,
              let salaryDay = settings.salaryDay,
              let range = Calendar.current.range(of: .day, in: .month, for: .now) else {
            return
        }

        let effectiveDay = min(max(salaryDay, 1), range.count)
        let currentDay = Calendar.current.component(.day, from: .now)
        let key = GhafSalaryCycle.periodKey(for: .now, salaryDay: salaryDay)

        // Ask once, on salary day only: a missed day is not asked about later.
        if currentDay == effectiveDay && settings.lastSalaryDecisionKey != key {
            settings.lastSalaryDecisionKey = key
            try? modelContext.save()
            showSalaryCheckIn = true
        }
    }
}

// MARK: - Transaction Row

struct GhafTransactionRow: View {
    let transaction: GhafTransaction
    let theme: GhafTheme
    let languageCode: String
    var hidden = false

    var body: some View {
        HStack(spacing: 14) {
            GhafCategoryIcon(category: transaction.category, tint: theme.accent, theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                Text(merchantTitle)
                    .font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(GhafLocalization.category(transaction.category, languageCode: languageCode)
                         + (transaction.subcategory.map { " · \($0)" } ?? ""))
                    Text("·")
                    Text(transaction.date.formatted(
                        .dateTime.hour().minute().locale(Locale(identifier: languageCode))
                    ))
                }
                .font(GhafTypography.body(13, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 2) {
                    Text(transaction.direction == "credit" ? "+" : "−")
                        .font(GhafTypography.number(16, weight: .bold))
                    GhafMoneyLabel(amount: transaction.amount, currency: transaction.currency, languageCode: languageCode, size: 16, hidden: hidden)
                }
                .foregroundStyle(transaction.direction == "credit" ? theme.credit : theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)

                if transaction.needsReview {
                    Text(languageCode == "ar" ? "مراجعة" : "REVIEW")
                        .font(GhafTypography.body(11, languageCode: languageCode, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(theme.close)
                }
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var merchantTitle: String {
        if let merchant = transaction.merchant, !merchant.isEmpty {
            return merchant
        }
        return GhafLocalization.category(transaction.category, languageCode: languageCode)
    }

}

// MARK: - Manual Transaction Entry

struct GhafQuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]

    let settings: GhafSettings
    /// Opened from a card in Accounts: start on that account, optionally as a transfer.
    var presetAccountID: UUID? = nil
    var startAsTransfer = false

    @State private var selectedAccountID: UUID?
    @State private var amount = ""
    @State private var merchant = ""
    @State private var category = "Other"
    @State private var direction = "debit"
    @State private var note = ""
    @State private var date = Date()
    @State private var errorMessage = ""

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var ar: Bool { settings.languageCode == "ar" }
    private var lang: String { settings.languageCode }
    @State private var subcategory: String?
    @State private var toAccountID: UUID?
    private var isTransfer: Bool { direction == "transfer" }
    private var activeAccounts: [GhafAccount] { accounts.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    amountHeader
                    VStack(spacing: 0) {
                      if isTransfer {
                        row(ar ? "من" : "From", icon: "arrow.up.forward.circle") { accountPicker($selectedAccountID) }
                        divider
                        row(ar ? "إلى" : "To", icon: "arrow.down.forward.circle") { accountPicker($toAccountID) }
                        divider
                      } else {
                        row(ar ? "المتجر" : "Merchant", icon: "storefront") {
                            TextField(ar ? "اسم المتجر" : "Store name", text: $merchant)
                                .multilineTextAlignment(.trailing)
                        }
                        divider
                        row(ar ? "الفئة" : "Category", icon: "square.grid.2x2") {
                            GhafCategoryPicker(category: $category, subcategory: $subcategory, languageCode: lang, tint: theme.accent)
                        }
                        divider
                        row(ar ? "الحساب" : "Account", icon: "wallet.pass") { accountPicker($selectedAccountID) }
                        divider
                      }
                        row(ar ? "التاريخ" : "Date", icon: "calendar") {
                            DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute]).labelsHidden().tint(theme.accent)
                        }
                        divider
                        row(ar ? "ملاحظة" : "Note", icon: "text.alignleft") {
                            TextField(ar ? "اختياري" : "Optional", text: $note).multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .ghafCard(theme: theme)

                    NavigationLink { GhafVoiceEntryView(settings: settings) } label: {
                        Label(ar ? "أو قلها بصوتك" : "Or say it out loud", systemImage: "mic.fill")
                            .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.ghafPress)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(GhafTypography.body(13, languageCode: lang))
                            .foregroundStyle(theme.over)
                    }
                }
                .ghafScreenPadding()
                .padding(.top, 8).padding(.bottom, 20)
                .frame(maxWidth: 580)
                .frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .ghafKeyboardDone()
            .safeAreaInset(edge: .bottom) {
                GhafDetailActionBar(theme: theme, languageCode: lang,
                                    primaryTitle: ar ? "حفظ العملية" : "Save transaction", primaryAction: save)
            }
            .navigationTitle(ar ? "عملية جديدة" : "New transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ar ? "إلغاء" : "Cancel") { dismiss() }
                }
            }
        }
        .tint(theme.accent)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        .onAppear {
            selectedAccountID = presetAccountID
                ?? accounts.first(where: { $0.isPrimary && !$0.isArchived })?.id
                ?? accounts.first(where: { !$0.isArchived })?.id
            if startAsTransfer { direction = "transfer" }
            toAccountID = activeAccounts.first(where: { $0.id != selectedAccountID })?.id
        }
    }

    /// Expense or income, then the amount, large and centred like the rest of Ghaf's money.
    private var amountHeader: some View {
        let currency = accounts.first { $0.id == selectedAccountID }?.currency ?? settings.currency
        return VStack(spacing: 14) {
            HStack(spacing: 8) {
                directionChip("debit", ar ? "مصروف" : "Expense", "arrow.down.right")
                directionChip("credit", ar ? "دخل" : "Income", "arrow.up.right")
                if activeAccounts.count > 1 {
                    directionChip("transfer", ar ? "تحويل" : "Transfer", "arrow.left.arrow.right")
                }
            }
            GhafAmountField(value: $amount, currency: currency, label: ar ? "المبلغ" : "Amount",
                            theme: theme, languageCode: lang, fontSize: 44, presentOnAppear: true)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .ghafCard(theme: theme)
    }

    private func directionChip(_ value: String, _ title: String, _ icon: String) -> some View {
        let selected = direction == value
        return Button { withAnimation(.snappy) { direction = value } } label: {
            Label(title, systemImage: icon)
                .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.65)
                .foregroundStyle(selected ? theme.accentContrast : theme.primaryText)
                .padding(.horizontal, 16).frame(minHeight: 38)
                .background(selected ? theme.accent : theme.primaryText.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.ghafPress)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func accountPicker(_ selection: Binding<UUID?>) -> some View {
        GhafMenuRow(title: ar ? "الحساب" : "Account", value: activeAccounts.first(where: { $0.id == selection.wrappedValue }).map { "\($0.name) · \($0.currency)" } ?? (ar ? "اختر" : "Choose"), theme: theme, languageCode: lang, compact: true) {
            Picker(ar ? "الحساب" : "Account", selection: selection) {
                if selection.wrappedValue == nil { Text(ar ? "اختر" : "Choose").tag(nil as UUID?) }
                ForEach(activeAccounts, id: \.id) { account in
                    Text("\(account.name) · \(account.currency)").tag(Optional(account.id))
                }
            }
        }
    }

    private var divider: some View { Divider().overlay(theme.outline).padding(.leading, 38) }

    private func row<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 26)
            Text(title)
                .font(GhafTypography.body(15, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .fixedSize()
            Spacer(minLength: 12)
            content()
                .font(GhafTypography.body(15, languageCode: lang))
                .tint(theme.accent)
        }
        .frame(minHeight: 54)
    }

    /// Money moved between the user's own accounts: out of one, into the other, both as Transfers, so
    /// the total stays the same and it never counts as spending or income.
    private func saveTransfer(_ value: Decimal) {
        guard let from = activeAccounts.first(where: { $0.id == selectedAccountID }),
              let to = activeAccounts.first(where: { $0.id == toAccountID }), from.id != to.id else {
            errorMessage = ar ? "اختر حسابين مختلفين." : "Choose two different accounts."
            return
        }
        guard from.currency == to.currency else {
            // shortcut: no exchange rate in Ghaf yet, so cross-currency transfers are refused rather than guessed.
            errorMessage = ar ? "الحسابان بعملتين مختلفتين. التحويل بين العملات غير مدعوم بعد."
                              : "These accounts use different currencies. Transfers between currencies aren't supported yet."
            return
        }
        let id = UUID().uuidString
        let title = ar ? "تحويل إلى \(to.name)" : "Transfer to \(to.name)"
        for (account, dir, suffix, name) in [(from, TransactionDirection.debit, "out", title),
                                             (to, .credit, "in", ar ? "تحويل من \(from.name)" : "Transfer from \(from.name)")] {
            let parsed = ParsedTransaction(amount: value, currency: account.currency, merchant: name, date: date,
                                           direction: dir, confidence: 1.0, bank: nil)
            let transaction = GhafTransaction(fingerprint: "transfer-\(id)-\(suffix)", parsed: parsed, category: "Transfers",
                                              needsReview: false, isReversal: false, accountID: account.id)
            transaction.note = note
            modelContext.insert(transaction)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = ar ? "تعذر حفظ التحويل." : "Could not save the transfer."
        }
    }

    private func save() {
        guard let value = Decimal(string: amount), value > 0 else {
            errorMessage = settings.languageCode == "ar" ? "أدخل مبلغاً صحيحاً." : "Enter a valid amount."
            return
        }
        if isTransfer { saveTransfer(value); return }

        let selectedAccount = accounts.first(where: { $0.id == selectedAccountID })
        let transactionDirection = TransactionDirection(rawValue: direction) ?? .debit
        let suggestedCategory = (try? MerchantCategorizer.category(
            for: merchant.isEmpty ? nil : merchant,
            direction: transactionDirection,
            context: modelContext
        )) ?? "Other"
        let finalCategory = category == "Other" ? suggestedCategory : category

        let parsed = ParsedTransaction(
            amount: value,
            currency: selectedAccount?.currency ?? settings.currency,
            merchant: merchant.isEmpty ? nil : merchant,
            date: date,
            direction: transactionDirection,
            confidence: 1.0,
            bank: nil
        )

        let transaction = GhafTransaction(
            fingerprint: "manual-\(UUID().uuidString)",
            parsed: parsed,
            category: finalCategory,
            needsReview: false,
            isReversal: false,
            accountID: selectedAccountID
        )
        transaction.note = note
        transaction.subcategory = category == finalCategory ? subcategory : nil
        modelContext.insert(transaction)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = settings.languageCode == "ar" ? "تعذر حفظ العملية." : "Could not save transaction."
        }
    }
}
