import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]
    @Query(sort: \GhafAccount.sortOrder)
    private var accounts: [GhafAccount]
    @Query private var subscriptions: [GhafSubscription]

    @State private var showQuickAdd = false
    @State private var showVoiceEntry = false
    @State private var showAutomationGuide = false
    @State private var showSalaryCheckIn = false
    @State private var showAccounts = false
    @State private var showImportSheet = false
    @State private var showInsights = false
    @State private var showInbox = false
#if DEBUG
    @State private var showNotificationSettings = false
#endif
    @State private var inboxTargetID: String?
    @State private var selectedTransaction: GhafTransaction?
    @AppStorage(GhafAutomationStatus.lastRunKey) private var automationLastRun: Double = 0
    @AppStorage(GhafAutomationStatus.walletRunKey) private var walletLastRun: Double = 0
    @AppStorage(GhafAutomationStatus.setupCompletedKey) private var automationSetupCompleted: Double = 0
    @AppStorage(GhafAutomationStatus.warningDismissedUntilKey) private var automationWarningDismissedUntil: Double = 0
    /// Observed so the weekly figures redraw as soon as the week start changes.
    @AppStorage(GhafCalendar.weekStartKey) private var weekStart = 0
    @AppStorage(GhafFormat.hideBalancesKey) private var hideBalances = false
    @State private var eyeLidClosed = false
    @State private var showSubscriptions = false
    /// Weekly used to be the calendar week; tell the user once that it's now the last 7 days.
    @AppStorage("ghaf.seenRollingWeekNote") private var seenRollingWeekNote = false
    @State private var activityPeriodIndex = 0
    @State private var summary = Summary()
    @State private var cachedSummaryID: String?
    @State private var summaryPrepared = false

    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var inboxCount: Int {
        summary.reviewCount
            + subscriptions.filter(\.needsConfirmation).count
            + GhafEventNotifications.events.filter { $0.kind == .budgetThreshold || $0.kind == .subscriptionDue }.count
    }

    /// Everything Home shows, derived in one pass per render instead of once per view.
    private struct Summary {
        var accountBalances: [UUID: Decimal] = [:]
        var balances: [GhafCurrencyBalance] = []
        var mainCurrency = ""
        var spent: Decimal = 0
        var income: Decimal = 0
        var count = 0
        var reviewCount = 0
        var topCategory: (name: String, amount: Decimal)?
        /// Spending by category, largest first.
        var categories: [(name: String, amount: Decimal)] = []
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
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: GhafClock.now))!
            let start = calendar.date(byAdding: .day, value: -7, to: tomorrow)!
            interval = DateInterval(start: start, end: tomorrow)
            previous = DateInterval(start: calendar.date(byAdding: .day, value: -7, to: start)!, end: start)
        } else {
            let component: Calendar.Component = activityPeriodIndex == 0 ? .day : .month
            interval = calendar.dateInterval(of: component, for: GhafClock.now)
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

    /// Rebuild only when summary inputs change, when Home becomes visible, or when a sheet
    /// that can change ledger data is dismissed. Body re-evaluation during scrolling stays cheap.
    private var summaryTaskID: String {
        "\(activityPeriodIndex)-\(transactions.count)-\(accounts.count)-\(subscriptions.count)-\(settings.currency)-\(weekStart)-\(router.ledgerRevision)"
    }

    private func refreshSummaryIfNeeded() {
        let currentID = summaryTaskID
        guard currentID != cachedSummaryID else { return }
#if DEBUG
        summary = GhafPerformanceProbe.measure("home-summary") { makeSummary() }
#else
        summary = makeSummary()
#endif
        cachedSummaryID = currentID
        summaryPrepared = true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GhafMetrics.sectionSpacing) {
                    if automationNeedsAttention && GhafClock.now.timeIntervalSince1970 >= automationWarningDismissedUntil {
                        automationWarningCard
                    }
                    if accounts.contains(where: { !$0.isArchived }) {
                        if summaryPrepared {
                            balanceCard(summary).ghafEntrance(1)
                            actionRow().ghafEntrance(2)
                            insightCard(summary).ghafEntrance(3)
                            recentActivity.ghafEntrance(4)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 260)
                                .accessibilityLabel(settings.languageCode == "ar" ? "جارٍ تحميل الملخص" : "Loading summary")
                        }
                    } else {
                        emptyAccountsState.ghafEntrance(1)
                    }
                }
                .ghafScreenPadding()
                .padding(.top, 32)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(theme.background.ignoresSafeArea())
            .ghafStatusBarFade(theme: theme)
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .ghafScreenPadding()
                    .padding(.top, 16)
                    .background(theme.background)
                    // Content scrolling under the pinned header fades out instead of showing a hard cut.
                    .overlay(alignment: .bottom) {
                        LinearGradient(stops: [.init(color: theme.background, location: 0), .init(color: theme.background, location: 0.45),
                                               .init(color: theme.background.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 40)
                            .offset(y: 40)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            }
#if DEBUG
            .onAppear {
                if GhafScreenshotFixture.enabled, ["amount-pad", "new-transaction"].contains(GhafScreenshotFixture.screen ?? "") { showQuickAdd = true }
            }
#endif
            .onChange(of: router.homeReselects) { _, _ in
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) { activityPeriodIndex = (activityPeriodIndex + 1) % 3 }
            }
            .onChange(of: summaryTaskID) { _, _ in refreshSummaryIfNeeded() }
            .onAppear { refreshSummaryIfNeeded() }
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
            .sheet(isPresented: $showInbox) {
                GhafReviewInboxView(settings: settings, initialTargetID: inboxTargetID).presentationDragIndicator(.visible).ghafDirection(settings.languageCode)
            }
#if DEBUG
            .sheet(isPresented: $showNotificationSettings) {
                NavigationStack { GhafNotificationSettingsView(settings: settings) }
                    .presentationDragIndicator(.visible).ghafDirection(settings.languageCode)
            }
#endif
            .sheet(item: $selectedTransaction) { transaction in
                GhafTransactionDetailView(transaction: transaction, settings: settings, accounts: accounts.filter { !$0.isArchived })
                    .presentationDragIndicator(.visible).ghafDirection(settings.languageCode)
            }
            .sheet(isPresented: $showImportSheet) { GhafImportSheet(settings: settings) }
            .onAppear {
                GhafEventNotifications.configure()
                rescheduleLocalNotifications()
                if let target = GhafEventNotifications.consumePendingTarget(), !target.isEmpty {
                    inboxTargetID = target
                    router.selectedTab = 0
                    showInbox = true
                }
#if DEBUG
                switch GhafScreenshotFixture.screen {
                case "inbox-proof", "inbox-empty", "home-inbox-count":
                    GhafScreenshotFixture.configureInbox(context: modelContext, settings: settings)
                    showInbox = GhafScreenshotFixture.screen != "home-inbox-count"
                case "notification-settings": showNotificationSettings = true
                default: break
                }
                if ProcessInfo.processInfo.arguments.contains("-ghafDebugEvent") {
                    GhafEventNotifications.scheduleDebugEvent("review")
                }
#endif
            }
            .onReceive(NotificationCenter.default.publisher(for: GhafEventNotifications.openInboxItem)) { note in
                inboxTargetID = note.object as? String
                router.selectedTab = 0
                showInbox = true
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { rescheduleLocalNotifications() }
            }
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
                    try? await GhafSalaryReminderService.scheduleNext(salaryDay: day, languageCode: settings.languageCode,
                                                                      salaryAmount: settings.salaryAmount,
                                                                      salaryCurrency: settings.salaryCurrency ?? settings.currency)
                }
            }
        }
    }

    private var ar: Bool { settings.languageCode == "ar" }
    private var lang: String { settings.languageCode }
    private var messageRunHistory: [Double] { UserDefaults.standard.array(forKey: GhafAutomationStatus.messageHistoryKey) as? [Double] ?? [] }
    private var walletRunHistory: [Double] { UserDefaults.standard.array(forKey: GhafAutomationStatus.walletHistoryKey) as? [Double] ?? [] }

    private func rescheduleLocalNotifications() {
        GhafDigestNotifications.reschedule(context: modelContext)
        for subscription in subscriptions where subscription.isActive {
            GhafSubscriptionReminderService.schedule(subscription, language: settings.languageCode)
        }
    }

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
            }
            .ghafProminentButton(theme: theme, languageCode: lang)
            Button { showImportSheet = true } label: {
                Label(ar ? "استيراد نسخة غاف الاحتياطية" : "Import Ghaf backup", systemImage: "arrow.down.doc")
            }
            .ghafGlassButton(theme: theme, languageCode: lang)
        }
        .padding(GhafMetrics.heroPadding)
        .frame(maxWidth: .infinity, minHeight: 320)
        .ghafGlassHero(theme: theme, radius: 28)
        .multilineTextAlignment(.center)
    }

    private var automationNeedsAttention: Bool {
        let now = GhafClock.now.timeIntervalSince1970
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
                    automationWarningDismissedUntil = GhafClock.now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970
                }
                .font(GhafTypography.body(12, languageCode: lang))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 18), fallback: theme.surface)
    }

    // MARK: Header: greeting, accounts pill, hide-balances eye

    private var header: some View {
        HStack(spacing: 8) {
            if accounts.contains(where: { !$0.isArchived }) {
                Button { showAccounts = true } label: {
                    Image(systemName: "wallet.bifold.fill")
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 44, height: 44)
                        .background(theme.surface, in: Circle())
                }
                .accessibilityLabel(ar ? "الحسابات" : "Accounts")
                .buttonStyle(.ghafPress)
                .modifier(HomeAccountsZoomSource(namespace: accountsNamespace))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            VStack(spacing: 2) {
                Text(greeting)
                    .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Text(settings.userName.isEmpty ? (ar ? "غاف" : "Ghaf") : settings.userName)
                    .font(GhafTypography.display(32, languageCode: lang))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            Button {
                GhafSounds.shared.play(.tick)
                if reduceMotion {
                    withAnimation(.easeInOut(duration: 0.15)) { hideBalances.toggle() }
                } else {
                    withAnimation(.easeInOut(duration: 0.11)) { eyeLidClosed = true }
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.26)) { hideBalances.toggle() }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(110))
                        withAnimation(.easeOut(duration: 0.11)) { eyeLidClosed = false }
                    }
                }
            } label: {
                Image(systemName: hideBalances ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 15, weight: .bold))
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.downUp))
                    .scaleEffect(y: eyeLidClosed ? 0.15 : 1)
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(theme.surface, in: Circle())
            }
            .buttonStyle(.ghafPress)
            .sensoryFeedback(.selection, trigger: hideBalances)
            .accessibilityLabel(ar ? (hideBalances ? "إظهار الأرصدة" : "إخفاء الأرصدة")
                                   : (hideBalances ? "Show balances" : "Hide balances"))
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: GhafClock.now)
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
                           label: ar ? "المصروف" : "spent", currency: summary.mainCurrency)
                changeLine(icon: "arrow.up.right", value: summary.income, color: theme.credit,
                           label: ar ? "الدخل" : "in", currency: summary.mainCurrency)
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
                    .accessibilityIdentifier("home.period.count")
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
            GhafSounds.shared.play(.tick)
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
            GhafRollingNumber(amount: value, currency: currency, languageCode: lang, size: 14, hidden: hideBalances)
                .accessibilityIdentifier(label == (ar ? "المصروف" : "spent") ? "home.period.spent" : "home.period.income")
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

    private func actionRow() -> some View {
        HStack(spacing: 8) {
            actionButton(ar ? "إضافة" : "Add", icon: "plus", prominent: true) { showQuickAdd = true }
            actionButton(ar ? "اشتراكات" : "Subs", icon: "repeat") { showSubscriptions = true }
            actionButton(ar ? "النشاط" : "Activity", icon: "tray.full.fill", count: inboxCount) {
                showInbox = true
            }
        }
    }

    private func actionButton(_ title: String, icon: String, count: Int = 0, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(prominent ? theme.background : theme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(prominent ? theme.primaryText : theme.surface, in: Capsule())
            .overlay(alignment: .topTrailing) {
                if count > 0 { Circle().fill(theme.accent).frame(width: 7, height: 7).padding(9) }
            }
        }
        .buttonStyle(.ghafPress)
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? (ar ? "يحتاج إلى انتباه" : "Needs attention") : "")
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
                        Text(index == 3 && rest > 0 ? (lang == "ar" ? "أخرى" : "Other") : GhafLocalization.category(slice.name, languageCode: lang))
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
        let text = ar
            ? ["لا مصروفات اليوم حتى الآن.", "لا مصروفات في آخر ٧ أيام.", "لا مصروفات هذا الشهر حتى الآن."][activityPeriodIndex]
            : activityPeriodIndex == 1 ? "Nothing spent in the last 7 days." : "Nothing spent \(periodPhrase) yet."
        guard summary.previousSpent > 0 else {
            return text + (ar ? " يوم بلا مصروفات." : " A good day for your wallet.")
        }
        let previousName = ar ? ["مصروف أمس", "مصروف الأيام السبعة السابقة", "مصروف الشهر الماضي"][activityPeriodIndex]
                              : ["Yesterday", "In the 7 days before", "Last month"][activityPeriodIndex]
        guard !hideBalances else { return text }
        let amount = GhafFormat.money(summary.previousSpent, currency: summary.mainCurrency, languageCode: lang)
        return text + (ar ? " \(previousName): \(GhafMoneyText.isolate(amount))" : " \(previousName), you spent \(amount).")
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
              let range = Calendar.current.range(of: .day, in: .month, for: GhafClock.now) else {
            return
        }

        let effectiveDay = min(max(salaryDay, 1), range.count)
        let currentDay = Calendar.current.component(.day, from: GhafClock.now)
        let key = GhafSalaryCycle.periodKey(for: GhafClock.now, salaryDay: salaryDay)

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
    @AppStorage("ghaf.merchant.aliases") private var merchantAliases = Data()
    let transaction: GhafTransaction
    let theme: GhafTheme
    let languageCode: String
    var hidden = false

    var body: some View {
        HStack(spacing: 14) {
            GhafCategoryIcon(category: transaction.category, tint: theme.accent, theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                Text(merchantTitle)
                    .font(GhafTypography.userContent(merchantTitle, size: 16, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(GhafLocalization.category(transaction.category, languageCode: languageCode)
                         + (transaction.subcategory.map { " · \(GhafLocalization.category($0, languageCode: languageCode))" } ?? ""))
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
        if let merchant = GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant), !merchant.isEmpty {
            return merchant
        }
        return GhafLocalization.category(transaction.category, languageCode: languageCode)
    }

}

// MARK: - Manual Transaction Entry

struct GhafQuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GhafTabRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var showingDate = false
    @State private var showingTime = false
    @State private var showingDiscard = false
    @State private var locationPermission: Bool?
    @State private var showingSuccess = false
    @State private var suggestedCategory = false
    @State private var categoryWasManuallyPicked = false
    @State private var categorizationTask: Task<Void, Never>?
    @State private var noteExpanded = false
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
    private var presentAmountPadOnAppear: Bool {
        #if DEBUG
        settings.showKeypadOnAdd && GhafScreenshotFixture.screen != "new-transaction"
        #else
        settings.showKeypadOnAdd
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                    ZStack {
                        Text(ar ? "عملية جديدة" : "New transaction")
                            .font(GhafTypography.body(17, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                        HStack {
                            Button(ar ? "إلغاء" : "Cancel", action: requestDismiss).font(GhafTypography.body(15, languageCode: lang, weight: .semibold))
                                .foregroundStyle(theme.accent).frame(width: 64, alignment: .leading)
                            Spacer()
                        }
                    }
                    .frame(height: 44)
                    amountHeader
                    GhafFormCard(theme: theme) {
                      if isTransfer {
                        accountPicker($selectedAccountID, title: ar ? "من" : "From", icon: "arrow.up.forward.circle")
                        divider
                        accountPicker($toAccountID, title: ar ? "إلى" : "To", icon: "arrow.down.forward.circle")
                        divider
                      } else {
                        row(ar ? "المتجر" : "Merchant", icon: "storefront") {
                            HStack(spacing: 7) {
                                TextField(ar ? "اسم المتجر" : "Store name", text: $merchant)
                                    .lineLimit(1).submitLabel(.done)
                                    .multilineTextAlignment(.leading)
                                    .onSubmit { suggestCategory() }
                                    .onChange(of: merchant) { _, _ in
                                        categorizationTask?.cancel()
                                        categorizationTask = Task { try? await Task.sleep(for: .milliseconds(150)); if !Task.isCancelled { suggestCategory() } }
                                    }
                                Image(systemName: "chevron.forward").font(.system(size: 13, weight: .bold)).opacity(0.7)
                            }
                        }
                        divider
                        row(ar ? "الفئة" : "Category", icon: "square.grid.2x2") {
                            HStack(spacing: 6) {
                                GhafCategoryPicker(category: $category, subcategory: $subcategory, languageCode: lang, tint: theme.accent) { categoryWasManuallyPicked = true; suggestedCategory = false }
                                if suggestedCategory { Text(ar ? "مقترحة" : "Suggested").font(GhafTypography.body(10, languageCode: lang)).foregroundStyle(theme.secondaryText) }
                            }
                        }
                        divider
                        accountPicker($selectedAccountID, title: ar ? "الحساب" : "Account", icon: "wallet.pass")
                        divider
                        if locationPermission != false {
                            locationRow
                            divider
                        }
                      }
                        dateRow
                        divider
                        VStack(spacing: 0) {
                            GhafFormActionRow(icon: "text.alignleft", tint: theme.accent, title: ar ? "ملاحظة" : "Note",
                                              value: note.isEmpty ? (ar ? "اختياري" : "Optional") : note,
                                              theme: theme, languageCode: lang) { noteExpanded.toggle() }
                            if noteExpanded {
                                TextField(ar ? "اكتب ملاحظة" : "Write a note", text: $note, axis: .vertical)
                                    .font(GhafTypography.body(17, languageCode: lang)).foregroundStyle(theme.primaryText)
                                    .padding(16).frame(minHeight: 56, alignment: .leading)
                                    .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 18))
                                    .padding(.leading, 52).padding(.bottom, 10)
                            }
                        }
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(GhafTypography.body(13, languageCode: lang))
                            .foregroundStyle(theme.over)
                    }
                }
                .ghafScreenPadding()
                .padding(.top, 0).padding(.bottom, 0)
                .frame(maxWidth: 580)
                .frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .ghafKeyboardDone()
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    NavigationLink { GhafVoiceEntryView(settings: settings) } label: {
                        Image(systemName: "mic.fill").font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(theme.primaryText).frame(width: 60, height: 60)
                            .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Circle())
                    }.accessibilityLabel(ar ? "قلها بصوتك" : "Say it aloud")
                    Button(action: save) { Text(ar ? "حفظ العملية" : "Save transaction") }
                        .buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: lang, role: .primary))
                }
                .padding(.horizontal, GhafMetrics.gutter).padding(.vertical, 8)
                .background(theme.background)
            }
            .toolbar(.hidden, for: .navigationBar)
        .background(GhafQuickAddDismissObserver { showingDiscard = true }.frame(width: 1, height: 1))
        .tint(theme.accent)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .interactiveDismissDisabled(isDirty)
        .blur(radius: showingSuccess ? 18 : 0)
        .animation(.easeOut(duration: 0.3), value: showingSuccess)
        .overlay { if showingDiscard { GhafConfirmCard(title: ar ? "هل تريد تجاهل هذه العملية؟" : "Discard this transaction?", message: ar ? "ستفقد كل ما أدخلته." : "What you entered will be lost.", keepTitle: ar ? "متابعة التعديل" : "Keep editing", discardTitle: ar ? "تجاهل" : "Discard", theme: theme, languageCode: lang, keep: { showingDiscard = false }, discard: { showingDiscard = false; dismiss() }) } }
        .overlay { if showingSuccess { GhafSuccessSplash(title: ar ? "تمت إضافة العملية" : "Transaction added", subtitle: [GhafFormat.money(Decimal(string: amount) ?? 0, currency: accounts.first(where: { $0.id == selectedAccountID })?.currency ?? settings.currency, languageCode: lang), merchant].filter { !$0.isEmpty }.joined(separator: " · "), theme: theme, languageCode: lang) { router.isSaveSplashPresented = false; dismiss() } } }
        .sheet(isPresented: $showingDate) { dateSheet.presentationDetents([.height(430)]).ghafSheetFrame(theme: theme).presentationDragIndicator(.visible) }
        .sheet(isPresented: $showingTime) { timeSheet.presentationDetents([.height(300)]).ghafSheetFrame(theme: theme).presentationDragIndicator(.visible) }
        .onAppear {
            selectedAccountID = presetAccountID
                ?? accounts.first(where: { $0.isPrimary && !$0.isArchived })?.id
                ?? accounts.first(where: { !$0.isArchived })?.id
            if startAsTransfer { direction = "transfer" }
            toAccountID = activeAccounts.first(where: { $0.id != selectedAccountID })?.id
            locationPermission = GhafPlaces.locationPermission
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { locationPermission = GhafPlaces.locationPermission }
        }
    }

    /// Expense or income, then the amount, large and centred like the rest of Ghaf's money.
    private var amountHeader: some View {
        let currency = accounts.first { $0.id == selectedAccountID }?.currency ?? settings.currency
        return VStack(spacing: 16) {
            GhafAmountField(value: $amount, currency: currency, label: ar ? "المبلغ" : "Amount",
                            theme: theme, languageCode: lang, fontSize: 48, chromeless: true, presentOnAppear: presentAmountPadOnAppear)
            GhafSegmented(options: [("debit", ar ? "مصروف" : "Expense"), ("credit", ar ? "دخل" : "Income"), ("transfer", ar ? "تحويل" : "Transfer")],
                          selection: $direction, theme: theme, languageCode: lang)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var dateRow: some View {
        HStack(spacing: 10) {
            datePill
            timePill
        }.padding(.horizontal, 14).padding(.vertical, 6)
    }

    private var locationRow: some View {
        HStack(spacing: 12) {
            GhafIconBadge(symbol: "location", tint: theme.accent, size: 40, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text(ar ? "الموقع" : "Location")
                    .font(GhafTypography.body(16, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                Text(ar ? "يُحفظ على iPhone فقط" : "Saved on your iPhone only")
                    .font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(theme.secondaryText)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            if locationPermission == true {
                Text(ar ? "الموقع الحالي" : "Current place")
                    .font(GhafTypography.body(13, languageCode: lang, weight: .medium)).foregroundStyle(theme.secondaryText)
                    .lineLimit(1).minimumScaleFactor(0.75)
            } else {
                Button(ar ? "سماح" : "Allow") {
                    GhafPlaces.requestLocationIfUndecided()
                }
                .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 16).frame(minHeight: 36)
                .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 64)
    }

    private var datePill: some View {
        Button { showingDate = true } label: {
            Label(dateLabel, systemImage: "calendar").font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity, minHeight: 44)
                .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel(ar ? "التاريخ" : "Date")
    }
    private var timePill: some View {
        Button { showingTime = true } label: {
            Label(date.formatted(.dateTime.hour().minute().locale(Locale(identifier: ar ? "ar_AE" : "en_US"))), systemImage: "clock")
                .font(GhafTypography.body(13, languageCode: lang, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 44).background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel(ar ? "الوقت" : "Time")
    }
    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return ar ? "اليوم" : "Today" }
        if calendar.isDateInYesterday(date) { return ar ? "أمس" : "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: ar ? "ar_AE" : "en_US")))
    }
    private var dateSheet: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                quickDate(ar ? "اليوم" : "Today", value: GhafClock.now)
                quickDate(ar ? "أمس" : "Yesterday", value: Calendar.current.date(byAdding: .day, value: -1, to: GhafClock.now) ?? GhafClock.now)
            }
            DatePicker(ar ? "التاريخ" : "Date", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().tint(theme.accent)
        }.padding(20).background(theme.background)
    }
    private func quickDate(_ title: String, value: Date) -> some View {
        Button(title) { date = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: date), minute: Calendar.current.component(.minute, from: date), second: 0, of: value) ?? value; showingDate = false }
            .font(GhafTypography.body(14, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 44).background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Capsule())
    }
    private var timeSheet: some View {
        VStack(spacing: 8) {
            DatePicker(ar ? "الوقت" : "Time", selection: $date, displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden().tint(theme.accent)
            Button(ar ? "تم" : "Done") { showingTime = false }.buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: lang, role: .primary))
        }.padding(20).background(theme.background)
    }

    private var isDirty: Bool { !amount.isEmpty || !merchant.isEmpty || !note.isEmpty || category != "Other" || abs(date.timeIntervalSinceNow) > 60 }
    private func requestDismiss() { if isDirty { showingDiscard = true } else { dismiss() } }
    private func suggestCategory() {
        guard !categoryWasManuallyPicked else { return }
        let text = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if suggestedCategory { category = "Other"; subcategory = nil; suggestedCategory = false }
            return
        }
        guard let match = MerchantCategorizer.suggestion(for: text, context: modelContext), !match.isNewCategory else {
            if suggestedCategory { category = "Other"; subcategory = nil; suggestedCategory = false }
            return
        }
        category = match.category
        subcategory = match.subcategory
        suggestedCategory = true
    }

    private func accountPicker(_ selection: Binding<UUID?>, title: String, icon: String) -> some View {
        let value = activeAccounts.first(where: { $0.id == selection.wrappedValue }).map { "\($0.name) · \($0.currency)" } ?? (ar ? "اختر" : "Choose")
        return Menu {
            Picker(ar ? "الحساب" : "Account", selection: selection) {
                if selection.wrappedValue == nil { Text(ar ? "اختر" : "Choose").tag(nil as UUID?) }
                ForEach(activeAccounts, id: \.id) { account in
                    Text("\(account.name) · \(account.currency)").tag(Optional(account.id))
                }
            }
        } label: {
            row(title, icon: icon) {
                HStack(spacing: 7) { Text(value); Image(systemName: "chevron.forward").font(.system(size: 13, weight: .bold)) }
            }
        }
    }

    private var divider: some View { GhafFormDivider(theme: theme) }

    private func row<Content: View>(_ title: String, icon: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        GhafFormRow(icon: icon, tint: theme.accent, title: title, theme: theme, languageCode: lang) {
            content().tint(theme.accent).foregroundStyle(theme.primaryText)
        }
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
            if let merchant = transaction.merchant { try MerchantCategorizer.learn(merchant: merchant, category: finalCategory, subcategory: transaction.subcategory, context: modelContext) }
            try modelContext.save()
            GhafDigestNotifications.reschedule(context: modelContext)
            Task { await GhafPlaces.rememberCurrentLocation(transactionID: transaction.id) }
            router.isSaveSplashPresented = true
            showingSuccess = true
        } catch {
            errorMessage = settings.languageCode == "ar" ? "تعذر حفظ العملية." : "Could not save transaction."
        }
    }

}

private struct GhafQuickAddDismissObserver: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = DismissObserverController()
        controller.onAttempt = onAttempt
        controller.view.alpha = 0.01
        controller.view.isUserInteractionEnabled = false
        return controller
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let controller = controller as? DismissObserverController else { return }
        controller.onAttempt = onAttempt
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            controller.attachToPresentedSheet()
        }
    }

    final class DismissObserverController: UIViewController, UIAdaptivePresentationControllerDelegate {
        var onAttempt: () -> Void
        init() { onAttempt = {} ; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachToPresentedSheet()
        }

        func attachToPresentedSheet() {
            var current: UIViewController? = parent
            while let candidate = current {
                if candidate.presentingViewController != nil, let presentation = candidate.presentationController {
                    presentation.delegate = self
                    return
                }
                current = candidate.parent
            }
            current = view.window?.rootViewController
            while let candidate = current {
                if candidate.presentingViewController != nil, let presentation = candidate.presentationController {
                    presentation.delegate = self
                    return
                }
                current = candidate.presentedViewController
            }
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onAttempt()
        }
    }
}
