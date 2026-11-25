import SwiftUI
import SwiftData
import GhafCore
import os

private let subscriptionDetailLog = OSLog(subsystem: "com.ghaf.app", category: "SubscriptionDetail")

struct GhafSubscriptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \GhafSubscription.nextPaymentDate) private var subscriptions: [GhafSubscription]
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @Query(filter: #Predicate<GhafTransaction> { $0.direction == "debit" && !$0.isReversal }) private var debits: [GhafTransaction]
    /// One value drives the sheet, so it always opens on the tapped subscription (not a stale or blank one).
    private struct EditorTarget: Identifiable { let id = UUID(); let subscription: GhafSubscription? }
    @State private var editorTarget: EditorTarget?
#if DEBUG
    @State private var fixtureEditorOpened = false
    @State private var fixtureDetailOpened = false
#endif
    @State private var detail: GhafSubscription?
    @State private var detailTapStartedAt: TimeInterval = 0
    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }
    private var active: [GhafSubscription] { subscriptions.filter(\.isActive) }
    private var suggested: [GhafSubscription] { subscriptions.filter(\.needsConfirmation) }
    private var tracked: [GhafSubscription] { subscriptions.filter { !$0.needsConfirmation } }
    private var ar: Bool { settings.languageCode == "ar" }
    @State private var confirmedCount = 0
    /// Estimated monthly cost in the preferred currency; other currencies are never added in.
    private var monthlyEquivalent: Decimal {
        active.filter { $0.currency == settings.currency }.reduce(Decimal.zero) { $0 + $1.amount * $1.cycle.monthlyFactor }
    }

    private var lang: String { settings.languageCode }

    private var paymentMatches: [(GhafSubscription, GhafTransaction)] {
        let window = Calendar.current.dateInterval(of: .month, for: GhafClock.now)
        return active.compactMap { item in
            guard !item.needsConfirmation else { return nil }
            // Same per-cycle window as ingestion (R3): a flat 15 days let last week's charge pay this week's plan.
            let tolerance = item.cycle == .weekly ? 2 : 5
            let match = debits.first { transaction in
                guard transaction.currency == item.currency, window?.contains(transaction.date) == true,
                      !UserDefaults.standard.bool(forKey: "ghaf.subscription.match.dismissed.\(item.id).\(transaction.id)") else { return false }
                return SubscriptionDetector.isPayment(merchant: transaction.merchant, amount: transaction.amount, date: transaction.date,
                                                      subscriptionName: item.name, subscriptionAmount: item.amount,
                                                      dueDate: item.nextPaymentDate, toleranceDays: tolerance)
                    || SubscriptionDetector.raisedPrice(merchant: transaction.merchant, amount: transaction.amount, date: transaction.date,
                                                        subscriptionName: item.name, subscriptionAmount: item.amount,
                                                        dueDate: item.nextPaymentDate, toleranceDays: tolerance) != nil
            }
            return match.map { (item, $0) }
        }
    }

    private var paymentMatchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(paymentMatches, id: \.1.id) { item, transaction in
                let next = item.cycle.nextDate(after: item.nextPaymentDate).formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: lang)))
                VStack(alignment: .leading, spacing: 10) {
                    Text(ar ? "هل كانت هذه دفعة هذا الشهر لاشتراك \(item.name)؟ ينتقل التجديد القادم إلى \(next)."
                            : "Was this your \(item.name) payment for this month? The next payment moves to \(next).")
                        .font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(ar ? "ليست هذه الدفعة" : "Not this one") {
                            UserDefaults.standard.set(true, forKey: "ghaf.subscription.match.dismissed.\(item.id).\(transaction.id)")
                        }.ghafGlassButton(theme: theme, languageCode: lang)
                        Button(ar ? "تأكيد" : "Confirm") { confirmPayment(item, transaction: transaction) }
                            .ghafProminentButton(theme: theme, languageCode: lang)
                    }
                }
            }
        }.padding(16).ghafCard(theme: theme)
    }

    private func confirmPayment(_ item: GhafSubscription, transaction: GhafTransaction) {
        item.nextPaymentDate = item.cycle.nextDate(after: max(item.nextPaymentDate, transaction.date))
        do {
            try context.save()
            GhafSubscriptionReminderService.schedule(item, language: lang)
        } catch { context.rollback() }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GhafMetrics.sectionSpacing) {
                    GhafScreenTitle(title: ar ? "الاشتراكات" : "Subscriptions",
                                    subtitle: ar ? "التجديدات القادمة وتكلفتها" : "Renewals, costs and reminders",
                                    languageCode: lang, theme: theme, onClose: { dismiss() })
                        .padding(.top, 16)
                        .ghafEntrance(0)
                    costCard.ghafEntrance(1)
                    monthTiles.ghafEntrance(1)
                    if !paymentMatches.isEmpty { paymentMatchCard.ghafEntrance(2) }
                    if !priceChanges.isEmpty { priceChangeCard.ghafEntrance(2) }
                    if let next = active.filter({ !$0.needsConfirmation }).min(by: { $0.nextPaymentDate < $1.nextPaymentDate }) {
                        nextUpCard(next).ghafEntrance(2)
                    }

                    if !suggested.isEmpty { suggestionsCard.ghafEntrance(2) }
                    if !due.isEmpty { dueCard.ghafEntrance(2) }

                    VStack(spacing: 10) {
                        GhafSectionHeader(title: ar ? "كل الاشتراكات" : "Your subscriptions", theme: theme, languageCode: lang,
                                          actionTitle: ar ? "إضافة" : "Add") { editorTarget = EditorTarget(subscription: nil) }
                        if tracked.isEmpty {
                            VStack(spacing: 10) {
                                GhafIconBadge(symbol: "calendar.badge.clock", tint: theme.accent, size: 60, theme: theme)
                                Text(ar ? "لا توجد اشتراكات بعد" : "No subscriptions yet")
                                    .font(GhafTypography.heading(19, languageCode: lang)).foregroundStyle(theme.primaryText)
                                Text(ar ? "أضف خدماتك المتكررة ليذكّرك غاف بموعد التجديد." : "Add recurring services and Ghaf will remind you before renewal.")
                                    .font(GhafTypography.body(14, languageCode: lang)).foregroundStyle(theme.secondaryText)
                                Button { editorTarget = EditorTarget(subscription: nil) } label: {
                                    Label(ar ? "إضافة اشتراك" : "Add subscription", systemImage: "plus")
                                }
                                .ghafProminentButton(theme: theme, languageCode: lang)
                                .padding(.top, 6)
                            }
                            .multilineTextAlignment(.center)
                            .padding(22).frame(maxWidth: .infinity).ghafCard(theme: theme)
                            .ghafEntrance(1)
                        } else {
                            ForEach(groups, id: \.title) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.title)
                                        .font(GhafTypography.body(13, languageCode: lang, weight: .bold))
                                        .foregroundStyle(theme.secondaryText)
                                        .padding(.horizontal, 6)
                                    VStack(spacing: 0) {
                                        ForEach(group.items) { item in
                                            Button {
                                                detailTapStartedAt = ProcessInfo.processInfo.systemUptime
                                                os_signpost(.begin, log: subscriptionDetailLog, name: "TapToFirstFrame")
                                                detail = item
                                            } label: { subscriptionRow(item) }.buttonStyle(.ghafPress)
                                            if item.id != group.items.last?.id { Divider().overlay(theme.outline).padding(.leading, 58) }
                                        }
                                    }.padding(.horizontal, 16).padding(.vertical, 4).ghafCard(theme: theme)
                                }
                            }
                        }
                    }
                    .ghafEntrance(3)
                }
                .ghafScreenPadding().padding(.top, 8).padding(.bottom, 28)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.success, trigger: confirmedCount)
            .animation(.snappy, value: subscriptions.count)
            .sheet(item: $detail) { item in
                GhafSubscriptionDetailView(subscription: item, settings: settings, accounts: accounts.filter { !$0.isArchived }) {
                    let elapsed = (ProcessInfo.processInfo.systemUptime - detailTapStartedAt) * 1_000
                    os_signpost(.end, log: subscriptionDetailLog, name: "TapToFirstFrame")
                    os_signpost(.event, log: subscriptionDetailLog, name: "TapToFirstFrameMs", "%{public}.1f ms", elapsed)
                }
                    .presentationDragIndicator(.visible).ghafDirection(settings.languageCode)
            }
            .sheet(item: $editorTarget) { target in
                GhafSubscriptionEditor(settings: settings, accounts: accounts.filter { !$0.isArchived }, subscription: target.subscription)
                    .ghafDirection(settings.languageCode).presentationDetents([.large])
            }
            .onAppear {
#if DEBUG
                if GhafScreenshotFixture.enabled, ["subscription-editor", "subscription-editor-filled"].contains(GhafScreenshotFixture.screen ?? ""), !fixtureEditorOpened {
                    fixtureEditorOpened = true
                    editorTarget = EditorTarget(subscription: GhafScreenshotFixture.screen == "subscription-editor-filled" ? subscriptions.first : nil)
                }
                if GhafScreenshotFixture.enabled, GhafScreenshotFixture.screen == "subscriptions",
                   GhafScreenshotFixture.selection == "subscription-detail", !fixtureDetailOpened,
                   let item = subscriptions.first {
                    fixtureDetailOpened = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(900))
                        detailTapStartedAt = ProcessInfo.processInfo.systemUptime
                        os_signpost(.begin, log: subscriptionDetailLog, name: "TapToFirstFrame")
                        detail = item
                    }
                }
#endif
            }
        }
        .ghafDirection(settings.languageCode)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func daysUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: GhafClock.now),
                                        to: Calendar.current.startOfDay(for: date)).day ?? 0
    }

    private func whenText(_ date: Date) -> String {
        let days = daysUntil(date)
        if days < 0 { return ar ? "متأخر \(-days) يوم" : "\(-days) days overdue" }
        if days == 0 { return ar ? "اليوم" : "Today" }
        if days == 1 { return ar ? "غداً" : "Tomorrow" }
        return ar ? "بعد \(days) يوم" : "In \(days) days"
    }

    /// Renewals by how soon they come; paused ones last.
    private var groups: [(title: String, items: [GhafSubscription])] {
        let sorted = tracked.sorted { $0.nextPaymentDate < $1.nextPaymentDate }
        let live = sorted.filter(\.isActive)
        let result: [(String, [GhafSubscription])] = [
            (ar ? "هذا الأسبوع" : "This week", live.filter { daysUntil($0.nextPaymentDate) <= 7 }),
            (ar ? "هذا الشهر" : "This month", live.filter { (8...31).contains(daysUntil($0.nextPaymentDate)) }),
            (ar ? "لاحقاً" : "Later", live.filter { daysUntil($0.nextPaymentDate) > 31 }),
            (ar ? "متوقفة" : "Paused", sorted.filter { !$0.isActive })
        ]
        return result.filter { !$0.1.isEmpty }.map { (title: $0.0, items: $0.1) }
    }

    /// The next renewal, with how far through its billing cycle it is.
    private func nextUpCard(_ item: GhafSubscription) -> some View {
        let cycleDays = max(1, Calendar.current.dateComponents([.day], from: item.cycle.previousDate(before: item.nextPaymentDate),
                                                               to: item.nextPaymentDate).day ?? 30)
        let progress = min(1, max(0, 1 - Double(daysUntil(item.nextPaymentDate)) / Double(cycleDays)))
        return Button { detail = item } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(theme.outline, lineWidth: 4)
                    Circle().trim(from: 0, to: progress)
                        .stroke(LinearGradient(colors: [theme.accent, theme.glow], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    GhafBrandBadge(name: item.name, fallbackTint: theme.accent, size: 46, theme: theme)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ar ? "التالي" : "Next up")
                        .font(GhafTypography.body(12, languageCode: lang, weight: .bold))
                        .foregroundStyle(theme.accent)
                    Text(item.name)
                        .font(GhafTypography.userContent(item.name, size: 18, languageCode: lang, heading: true))
                        .foregroundStyle(theme.primaryText)
                    Text(whenText(item.nextPaymentDate) + " · " + item.nextPaymentDate.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: lang))))
                        .font(GhafTypography.body(13, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 8)
                GhafMoneyLabel(amount: item.amount, currency: item.currency, languageCode: lang, size: 18)
                    .foregroundStyle(theme.primaryText)
            }
            .padding(16)
            .ghafCard(theme: theme)
        }
        .buttonStyle(.ghafPress)
        .accessibilityElement(children: .combine)
    }

    /// The dark summary card: estimated monthly and yearly cost.
    private var costCard: some View {
        let next = active.filter { !$0.needsConfirmation }.min { $0.nextPaymentDate < $1.nextPaymentDate }
        return VStack(spacing: 14) {
            Text(ar ? "التكلفة الشهرية المقدّرة" : "Estimated monthly")
                .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.inkText.opacity(0.7))
            GhafMoneyLabel(amount: monthlyEquivalent, currency: settings.currency, languageCode: lang, size: 38)
                .foregroundStyle(theme.inkText)
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(ar ? "سنوياً" : "Per year")
                        .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.inkText.opacity(0.6))
                    GhafMoneyLabel(amount: monthlyEquivalent * 12, currency: settings.currency, languageCode: lang, size: 15)
                        .foregroundStyle(theme.inkText)
                }
                .frame(maxWidth: .infinity)
                costMetric(ar ? "نشطة" : "Active", "\(active.count)")
                costMetric(ar ? "التالي" : "Next",
                           next.map { $0.nextPaymentDate.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: lang))) } ?? "—")
            }
        }
        .padding(.vertical, 22).padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .ghafGlassHero(theme: theme, radius: 28, fallback: theme.ink)
    }

    private func costMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.inkText.opacity(0.6))
            Text(value)
                .font(GhafTypography.number(15, weight: .bold))
                .foregroundStyle(theme.inkText)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: This month, from the ledger

    /// Paid: real bank charges this month for tracked subscriptions. Still due: renewals left this month.
    /// Both in the preferred currency only; other currencies are never added in.
    private var monthTiles: some View {
        let month = Calendar.current.dateInterval(of: .month, for: GhafClock.now)!
        let live = active.filter { !$0.needsConfirmation && $0.currency == settings.currency }
        let paid = debits.filter { item in
            item.currency == settings.currency && month.contains(item.date)
                && live.contains { SubscriptionDetector.sameService(merchant: item.merchant ?? "", subscriptionName: $0.name) }
        }.reduce(Decimal.zero) { $0 + $1.amount }
        let due = live.filter { $0.nextPaymentDate < month.end }.reduce(Decimal.zero) { $0 + $1.amount }
        return HStack(spacing: 10) {
            monthTile(ar ? "دُفع هذا الشهر" : "Paid this month", paid, symbol: "arrow.up.right", tint: theme.over)
            monthTile(ar ? "متبقٍ هذا الشهر" : "Still due this month", due, symbol: "calendar", tint: theme.accent)
        }
    }

    private func monthTile(_ title: String, _ amount: Decimal, symbol: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Label(title, systemImage: symbol)
                .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .labelStyle(.titleAndIcon)
                .lineLimit(1).minimumScaleFactor(0.8)
            GhafMoneyLabel(amount: amount, currency: settings.currency, languageCode: lang, size: 20)
                .foregroundStyle(theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)
        }
        .frame(maxWidth: .infinity)
        .padding(GhafMetrics.heroPadding)
        .ghafCard(theme: theme, radius: 22)
    }

    // MARK: Price changes

    /// A real charge came in higher than the set price. The user decides whether future payments use it.
    private var priceChanges: [GhafSubscription] { subscriptions.filter { $0.proposedAmount != nil } }

    private var priceChangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(ar ? "تغيّر السعر" : "Price went up", systemImage: "arrow.up.circle.fill")
                .font(GhafTypography.body(13, languageCode: lang, weight: .bold))
                .foregroundStyle(theme.accent)
            ForEach(priceChanges) { item in
                let new = item.proposedAmount ?? item.amount
                let newText = GhafFormat.shownMoney(new, currency: item.currency, languageCode: lang)
                let oldText = GhafFormat.shownMoney(item.amount, currency: item.currency, languageCode: lang)
                VStack(alignment: .leading, spacing: 10) {
                    Text(ar ? "خُصم من \(item.name) \(newText) بدلاً من \(oldText). هل تريد اعتماد السعر الجديد للدفعات القادمة؟"
                            : "\(item.name) charged \(newText) instead of \(oldText). Use the new price for future payments?")
                        .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(ar ? "أبقِ \(oldText)" : "Keep \(oldText)") { resolvePrice(item, accept: false) }
                            .ghafGlassButton(theme: theme, languageCode: lang)
                        Button(ar ? "حدّث إلى \(newText)" : "Update to \(newText)") { resolvePrice(item, accept: true) }
                            .ghafProminentButton(theme: theme, languageCode: lang)
                    }
                }
            }
            Text(ar ? "الدفعات السابقة تبقى كما هي في السجل." : "Past payments stay as they are in your ledger.")
                .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
        }
        .padding(16).ghafCard(theme: theme)
    }

    private func resolvePrice(_ item: GhafSubscription, accept: Bool) {
        if accept, let new = item.proposedAmount {
            item.amount = new
        }
        item.proposedAmount = nil
        confirmedCount += 1
        do {
            try context.save()
            if accept && item.isActive { GhafSubscriptionReminderService.schedule(item, language: lang) }
        } catch { context.rollback() }
    }

    /// Subscriptions found in bank messages. Nothing is tracked or reminded until the user confirms.
    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(ar ? "اشتراكات محتملة" : "Found in your bank messages", systemImage: "sparkles")
                .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .bold))
                .foregroundStyle(theme.accent)
            ForEach(suggested) { item in
                VStack(spacing: 10) {
                    subscriptionRow(item)
                    HStack(spacing: 10) {
                        Button(ar ? "ليس اشتراكاً" : "Not a subscription") { dismissSuggestion(item) }
                            .ghafGlassButton(theme: theme, languageCode: lang)
                        Button(ar ? "تأكيد" : "Confirm") { confirm(item) }
                            .ghafProminentButton(theme: theme, languageCode: lang)
                    }
                }
            }
        }
        .padding(16).ghafCard(theme: theme)
    }

    private func confirm(_ item: GhafSubscription) {
        item.needsConfirmation = false
        item.isActive = true
        confirmedCount += 1
        do {
            try context.save()
            Task {
                _ = await GhafSubscriptionReminderService.requestPermission()
                GhafSubscriptionReminderService.schedule(item, language: settings.languageCode)
            }
        } catch { context.rollback() }
    }

    /// Renewals whose date has come. They move on only when the user says the money was deducted.
    private var due: [GhafSubscription] {
        let today = Calendar.current.startOfDay(for: GhafClock.now)
        return active.filter { !$0.needsConfirmation && Calendar.current.startOfDay(for: $0.nextPaymentDate) <= today }
    }

    private var dueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(ar ? "هل تم الخصم؟" : "Was it deducted?", systemImage: "questionmark.circle.fill")
                .font(GhafTypography.body(13, languageCode: lang, weight: .bold))
                .foregroundStyle(theme.accent)
            ForEach(due) { item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(GhafTypography.userContent(item.name, size: 15, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                        Text(item.nextPaymentDate.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: lang))))
                            .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    GhafMoneyLabel(amount: item.amount, currency: item.currency, languageCode: lang, size: 15)
                        .foregroundStyle(theme.primaryText)
                    Button(ar ? "تم الخصم" : "Paid") { markPaid(item) }
                        .ghafProminentButton(theme: theme, languageCode: lang)
                }
            }
            Text(ar ? "لا ينتقل الاشتراك للموعد التالي حتى تؤكد الخصم. المبلغ نفسه يُسجَّل من رسالة البنك."
                    : "Ghaf waits for you before moving to the next renewal. The charge itself comes from your bank message.")
                .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
        }
        .padding(16).ghafCard(theme: theme)
    }

    private func markPaid(_ item: GhafSubscription) {
        item.nextPaymentDate = item.cycle.nextDate(after: item.nextPaymentDate)
        confirmedCount += 1
        do {
            try context.save()
            GhafSubscriptionReminderService.schedule(item, language: lang)
        } catch { context.rollback() }
    }

    private func dismissSuggestion(_ item: GhafSubscription) {
        context.delete(item)
        do { try context.save() } catch { context.rollback() }
    }

    private func subscriptionRow(_ item: GhafSubscription) -> some View {
        return GhafListRow(icon: "repeat", tint: theme.accent, title: item.name,
                           subtitle: "\(item.cycle.title(language: lang)) · " + (item.isActive ? whenText(item.nextPaymentDate) : (ar ? "متوقف" : "Paused")),
                           theme: theme, languageCode: lang, brandName: item.name) {
            GhafMoneyLabel(amount: item.amount, currency: item.currency, languageCode: lang, size: 16)
                .foregroundStyle(item.isActive ? theme.primaryText : theme.secondaryText)
        }
    }
}

private struct GhafSubscriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    let settings: GhafSettings
    let accounts: [GhafAccount]
    let subscription: GhafSubscription?
    @State private var name = ""
    @State private var amount = ""
    @State private var currency = "AED"
    @State private var cycle: GhafBillingCycle = .monthly
    @State private var nextDate = Calendar.current.date(byAdding: .month, value: 1, to: GhafClock.now) ?? GhafClock.now
    @State private var category = "Subscriptions"
    @State private var categoryPickedManually = false
    @State private var accountID: UUID?
    @State private var reminderDays = 2
    @State private var active = true
    @State private var saveFailed = false
    @State private var showDatePicker = false
    @State private var showUpcomingPrompt = false
    @State private var originalAmount: Decimal = 0
    @State private var originalCycle: GhafBillingCycle = .monthly
    @State private var originalNextDate = GhafClock.now
    @FocusState private var nameFocused: Bool

    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        let ar = settings.languageCode == "ar"
        let valid = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (Decimal(string: amount) ?? 0) > 0
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Text(name.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "+")
                        .font(GhafTypography.number(26, weight: .bold)).foregroundStyle(theme.accent)
                        .frame(width: 48, height: 48).background(theme.accent.opacity(0.14), in: Circle())
                        .padding(.top, 8)
                    TextField(ar ? "اسم الخدمة" : "Service name", text: $name, prompt: Text(ar ? "اسم الخدمة" : "Service name").font(GhafTypography.body(24, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText))
                        .font(GhafTypography.userContent(name, size: 24, languageCode: settings.languageCode, heading: true))
                        .foregroundStyle(theme.primaryText).tint(theme.accent).multilineTextAlignment(.center)
                        .focused($nameFocused).submitLabel(.done)
                        .frame(minWidth: 160, maxWidth: .infinity, minHeight: 40)
                        .overlay(alignment: .bottom) {
                            if nameFocused {
                                Rectangle().fill(theme.accent).frame(width: max(160, min(340, CGFloat(max(name.count, ar ? 10 : 12)) * 13 + 24)), height: 1.5)
                            }
                        }
                        .padding(.top, 0)
                    GhafAmountField(value: $amount, currency: currency, label: "", theme: theme,
                                    languageCode: settings.languageCode, fontSize: 40, chromeless: true)
                        .padding(.top, 4)
                    Menu {
                        Picker(ar ? "العملة" : "Currency", selection: $currency) {
                            ForEach(["AED", "SAR", "KWD", "BHD", "OMR", "QAR"], id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currency).font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold))
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(theme.primaryText).padding(.horizontal, 18).frame(minHeight: GhafMetrics.compactButtonHeight)
                        .background(theme.elevatedSurface, in: Capsule())
                    }
                    .padding(.top, 0)
                    GhafSegmented(options: GhafBillingCycle.allCases.map { ($0, cycleTitle($0, arabic: ar)) },
                                  selection: $cycle, theme: theme, languageCode: settings.languageCode)
                        .padding(.top, 8)
                    if cycle != .monthly, let estimate = monthlyEstimate {
                        HStack(spacing: 5) {
                            Text("≈")
                            GhafMoneyLabel(amount: estimate, currency: currency, languageCode: settings.languageCode, size: 14)
                            Text(ar ? "شهرياً · تقديري" : "a month · estimate")
                        }
                        .font(GhafTypography.body(14, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText).frame(maxWidth: .infinity)
                        .padding(.top, 0)
                    }

                    GhafFormCard(theme: theme) {
                        GhafFormMenuRow(icon: "tag", tint: theme.secondaryText, title: ar ? "الفئة" : "Category",
                                        value: GhafLocalization.category(category, languageCode: settings.languageCode),
                                        theme: theme, languageCode: settings.languageCode) {
                            Picker(ar ? "الفئة" : "Category", selection: Binding(get: { category }, set: { category = $0; categoryPickedManually = true })) {
                                ForEach(settings.categories, id: \.self) { item in
                                    Text(GhafLocalization.category(item, languageCode: settings.languageCode)).tag(item)
                                }
                            }
                        }
                        GhafFormDivider(theme: theme)
                        GhafFormDateRow(icon: "calendar", tint: theme.secondaryText, title: ar ? "التجديد القادم" : "Next renewal",
                                        selection: $nextDate, isExpanded: $showDatePicker, theme: theme, languageCode: settings.languageCode)
                        GhafFormDivider(theme: theme)
                        GhafFormMenuRow(icon: "bell.badge", tint: theme.secondaryText, title: ar ? "التذكير" : "Reminder",
                                        value: reminderName, theme: theme, languageCode: settings.languageCode) {
                            Picker(ar ? "التذكير" : "Reminder", selection: $reminderDays) {
                                Text(ar ? "في نفس اليوم" : "Same day").tag(0)
                                Text(ar ? "قبل يوم" : "1 day before").tag(1)
                                Text(ar ? "قبل يومين" : "2 days before").tag(2)
                                Text(ar ? "قبل أسبوع" : "1 week before").tag(7)
                            }
                        }
                        GhafFormDivider(theme: theme)
                        GhafFormMenuRow(icon: "creditcard", tint: theme.secondaryText, title: ar ? "حساب الدفع" : "Paid from",
                                        value: accounts.first(where: { $0.id == accountID })?.name ?? (ar ? "غير محدد" : "Not specified"),
                                        theme: theme, languageCode: settings.languageCode) {
                            Picker(ar ? "حساب الدفع" : "Paid from", selection: $accountID) {
                                Text(ar ? "غير محدد" : "Not specified").tag(UUID?.none)
                                ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                        GhafFormDivider(theme: theme)
                        GhafFormToggleRow(icon: "power", tint: theme.secondaryText, title: ar ? "نشط" : "Active",
                                          isOn: $active, theme: theme, languageCode: settings.languageCode)
                    }
                    .padding(.top, 8)
                    if subscription != nil {
                        GhafSplitDeleteButton(title: ar ? "حذف الاشتراك" : "Delete subscription", confirmTitle: ar ? "حذف" : "Delete",
                                              theme: theme, languageCode: settings.languageCode) {
                            guard let subscription else { return dismiss() }
                            context.delete(subscription)
                            do { try context.save(); GhafSubscriptionReminderService.cancel(subscription); dismiss() }
                            catch { context.rollback(); saveFailed = true }
                        }
                        .padding(.top, 8)
                    }
                    Button { requestSave() } label: { Text(ar ? "حفظ" : "Save") }
                        .ghafProminentButton(theme: theme, languageCode: settings.languageCode)
                        .disabled(!valid).opacity(valid ? 1 : 0.4)
                        .padding(.top, subscription == nil ? 8 : 4)
                }
                .ghafScreenPadding().padding(.bottom, 0).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme).ghafKeyboardDone()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(ar ? "إلغاء" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Text(subscription == nil ? (ar ? "اشتراك جديد" : "New subscription") : (ar ? "تعديل الاشتراك" : "Edit subscription"))
                        .font(GhafTypography.body(17, languageCode: settings.languageCode, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear(perform: load)
            .onChange(of: name) { _, value in
                guard subscription == nil, !categoryPickedManually,
                      let suggestion = SubscriptionDetector.suggestedCategory(for: value),
                      settings.categories.contains(suggestion.category) else { return }
                category = suggestion.category
            }
            .alert(ar ? "تعذر حفظ التغيير" : "Couldn't save the change", isPresented: $saveFailed) {
                Button(ar ? "حسناً" : "OK", role: .cancel) {}
            } message: { Text(ar ? "لم يتغير شيء. حاول مرة أخرى." : "Nothing was changed. Please try again.") }
            .alert(ar ? "تحديث الدفعات القادمة؟" : "Update upcoming payments too?", isPresented: $showUpcomingPrompt) {
                Button(ar ? "تحديث التذكيرات" : "Update reminders") { save(updateReminders: true) }
                Button(ar ? "حفظ فقط" : "Save only", role: .cancel) { save(updateReminders: false) }
            } message: {
                Text(ar ? "ستستخدم التذكيرات القادمة المبلغ ودورة الفوترة الجديدين." : "Future reminders will use the new amount and billing cycle.")
            }
        }
        .ghafDirection(settings.languageCode).preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private var monthlyEstimate: Decimal? {
        guard let value = Decimal(string: amount), value > 0 else { return nil }
        return value * cycle.monthlyFactor
    }

    private func cycleTitle(_ cycle: GhafBillingCycle, arabic: Bool) -> String {
        if arabic { return cycle.title(language: "ar") }
        return switch cycle { case .weekly: "Weekly"; case .monthly: "Monthly"; case .quarterly: "Quarterly"; case .yearly: "Yearly" }
    }

    private var reminderName: String {
        switch reminderDays {
        case 0: settings.languageCode == "ar" ? "في نفس اليوم" : "Same day"
        case 1: settings.languageCode == "ar" ? "قبل يوم" : "1 day before"
        case 2: settings.languageCode == "ar" ? "قبل يومين" : "2 days before"
        default: settings.languageCode == "ar" ? "قبل أسبوع" : "1 week before"
        }
    }

    private func load() {
        guard let subscription else { originalNextDate = nextDate; return }
        categoryPickedManually = true
        name = subscription.name; amount = NSDecimalNumber(decimal: subscription.amount).stringValue
        currency = subscription.currency; cycle = subscription.cycle; nextDate = subscription.nextPaymentDate
        category = subscription.category; accountID = subscription.accountID
        reminderDays = subscription.reminderDays; active = subscription.isActive
        originalAmount = subscription.amount; originalCycle = subscription.cycle; originalNextDate = subscription.nextPaymentDate
    }

    private func requestSave() {
        if subscription != nil, (Decimal(string: amount) ?? 0) != originalAmount || cycle != originalCycle {
            showUpcomingPrompt = true
        } else { save(updateReminders: true) }
    }

    private func save(updateReminders: Bool) {
        let value = Decimal(string: amount) ?? 0
        let item: GhafSubscription
        if let subscription { item = subscription } else {
            item = GhafSubscription(name: name, amount: value, currency: currency, billingCycle: cycle, nextPaymentDate: nextDate)
            context.insert(item)
        }
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.amount = value; item.currency = currency; item.billingCycle = cycle.rawValue
        item.nextPaymentDate = nextDate; item.category = category; item.accountID = accountID
        item.reminderDays = reminderDays; item.isActive = active; item.needsConfirmation = false
        do {
            try context.save()
            if updateReminders || nextDate != originalNextDate {
                if item.isActive {
                    Task {
                        _ = await GhafSubscriptionReminderService.requestPermission()
                        GhafSubscriptionReminderService.schedule(item, language: settings.languageCode)
                    }
                } else {
                    GhafSubscriptionReminderService.cancel(item)
                }
            }
            dismiss()
        } catch {
            context.rollback()
            saveFailed = true
        }
    }
}

/// One subscription at a glance: what it is, its billing timeline, what it costs, and its reminder.
private struct GhafSubscriptionDetailView: View {
    @Environment(GhafTabRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    let subscription: GhafSubscription
    let settings: GhafSettings
    let accounts: [GhafAccount]
    let onFirstFrame: () -> Void

    @State private var payments: [GhafTransaction] = []
    @State private var editing = false

    private var lang: String { settings.languageCode }

    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }
    private func date(_ value: Date) -> String {
        value.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: lang)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header.ghafEntrance(0)
                    costCard.ghafEntrance(1)
                    timeline.ghafEntrance(2)
                    reminderRow.ghafEntrance(3)
                    HStack(spacing: 12) {
                        Button(action: toggleActive) {
                            Image(systemName: subscription.isActive ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                                .frame(width: 64, height: 56)
                                .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Capsule())
                        }
                        .buttonStyle(.ghafPress)
                        .accessibilityLabel(subscription.isActive ? (ar ? "إيقاف مؤقت" : "Pause") : (ar ? "استئناف" : "Resume"))
                        GhafPrimaryButton(title: ar ? "تعديل الاشتراك" : "Edit subscription", theme: theme,
                                          languageCode: lang) { editing = true }
                    }
                    .ghafScreenPadding()
                }
                .ghafScreenPadding()
                .padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .scrollBounceBehavior(.basedOnSize)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(ar ? "إغلاق" : "Close")
                }
            }
            .sheet(isPresented: $editing, onDismiss: {
                // Deleted from the editor: close this page instead of showing a removed record.
                if subscription.isDeleted || subscription.modelContext == nil { dismiss() } else { load() }
            }) {
                GhafSubscriptionEditor(settings: settings, accounts: accounts, subscription: subscription)
                    .ghafDirection(settings.languageCode).presentationDetents([.large])
            }
            .task {
                await Task.yield()
                onFirstFrame()
                await Task.yield()
                load()
            }
        }
        .ghafDirection(settings.languageCode)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var header: some View {
        VStack(spacing: 8) {
            GhafStatusMark(tint: theme.primaryText) {
                GhafBrandBadge(name: subscription.name, fallbackTint: theme.accent, size: 60, theme: theme)
            }
            Text(subscription.name)
                .font(GhafTypography.userContent(subscription.name, size: 24, languageCode: lang, heading: true))
                .foregroundStyle(theme.primaryText)
            let account = accounts.first { $0.id == subscription.accountID }?.name
            let status = subscription.isActive ? nil : (ar ? "متوقف" : "Paused")
            Text([subscription.cycle.title(language: lang), account, status].compactMap { $0 }.joined(separator: " · "))
                .font(GhafTypography.body(14, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: Timeline

    private struct Stop: Identifiable {
        let id = UUID()
        let title: String
        let date: Date
        let amount: Decimal
        let currency: String
        var note: String? = nil
        let kind: Kind
        enum Kind { case paid, next, later }
    }

    private var stops: [Stop] {
        let next = subscription.nextPaymentDate
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: GhafClock.now),
                                                   to: Calendar.current.startOfDay(for: next)).day ?? 0
        var result = payments.prefix(1).map {
            Stop(title: ar ? "مدفوع" : "Paid", date: $0.date, amount: $0.amount, currency: $0.currency, kind: .paid)
        }
        let when = days == 0 ? (ar ? "اليوم" : "today") : days > 0 ? (ar ? "بعد \(days) يوم" : "in \(days) days")
                                                            : (ar ? "متأخر \(-days) يوم" : "\(-days) days overdue")
        result.append(Stop(title: ar ? "التجديد القادم" : "Next renewal", date: next, amount: subscription.amount,
                           currency: subscription.currency, note: when, kind: .next))
        return result
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ar ? "مواعيد الفوترة" : "Billing timeline")
                .font(GhafTypography.body(15, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .padding(.bottom, 12)
            let items = stops
            ForEach(Array(items.enumerated()), id: \.element.id) { index, stop in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        dot(stop.kind)
                        if index < items.count - 1 {
                            Rectangle()
                                .fill(stop.kind == .paid ? theme.accent.opacity(0.6) : theme.outline)
                                .frame(width: 2)
                                .frame(minHeight: 34)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.title)
                            .font(GhafTypography.body(13, languageCode: lang))
                            .foregroundStyle(theme.secondaryText)
                        Text(date(stop.date))
                            .font(GhafTypography.body(16, languageCode: lang, weight: stop.kind == .next ? .bold : .medium))
                            .foregroundStyle(stop.kind == .later ? theme.secondaryText : theme.primaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        GhafMoneyLabel(amount: stop.amount, currency: stop.currency, languageCode: lang, size: 16)
                            .foregroundStyle(stop.kind == .later ? theme.secondaryText : theme.primaryText)
                        if let note = stop.note {
                            Text(note).font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if payments.isEmpty {
                Text(ar ? "لا توجد دفعات مسجلة بعد. تظهر هنا عندما تصل رسالة البنك." : "No payments recorded yet. They appear here when the bank message arrives.")
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme)
    }

    private func dot(_ kind: Stop.Kind) -> some View {
        ZStack {
            Circle().fill(kind == .later ? theme.outline : theme.accent.opacity(kind == .next ? 0.2 : 1))
                .frame(width: 22, height: 22)
            if kind == .paid {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(theme.accentContrast)
            } else if kind == .next {
                Circle().stroke(theme.accent, lineWidth: 3).frame(width: 14, height: 14)
            }
        }
        .frame(width: 22, height: 22)
    }

    // MARK: Cost and reminder

    private var costCard: some View {
        let monthly = subscription.amount * subscription.cycle.monthlyFactor
        return VStack(spacing: 8) {
            Text(subscription.cycle == .monthly ? (ar ? "التكلفة الشهرية" : "Monthly cost") : (ar ? "التكلفة الشهرية التقديرية" : "Estimated monthly cost"))
                .font(GhafTypography.body(14, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                GhafMoneyLabel(amount: monthly, currency: subscription.currency, languageCode: lang, size: 30)
                Text(ar ? "/شهر" : "/month")
                    .font(GhafTypography.body(17, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
            }
            .foregroundStyle(theme.primaryText)
            .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 5) {
                Text(ar ? "سنوياً" : "Per year")
                GhafMoneyLabel(amount: monthly * 12, currency: subscription.currency, languageCode: lang, size: 13)
            }
                .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(theme.primaryText.opacity(0.07), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            LinearGradient(colors: [theme.accent.opacity(0.16), theme.surface], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var reminderRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ar ? "التذكير" : "Reminder")
                    .font(GhafTypography.body(16, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(subscription.reminderDays == 0 ? (ar ? "في يوم التجديد · لا يخصم أي مبلغ" : "On renewal day · never deducts money")
                        : (ar ? "قبل \(subscription.reminderDays) يوم · لا يخصم أي مبلغ" : "\(subscription.reminderDays) days before · never deducts money"))
                    .font(GhafTypography.body(13, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Button(ar ? "تغيير" : "Change") { editing = true }
                .font(GhafTypography.body(15, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .ghafScreenPadding().padding(.vertical, 12)
                .ghafGlassShape(theme: theme, shape: Capsule(), fallback: theme.surface)
        }
        .padding(.horizontal, 4)
    }

    private func toggleActive() {
        subscription.isActive.toggle()
        do {
            try context.save()
            if subscription.isActive {
                Task {
                    _ = await GhafSubscriptionReminderService.requestPermission()
                    GhafSubscriptionReminderService.schedule(subscription, language: lang)
                }
            } else {
                GhafSubscriptionReminderService.cancel(subscription)
            }
        } catch {
            context.rollback()
        }
    }

    private func load() {
        let currency = subscription.currency, name = subscription.name
        let debits = (try? context.fetch(FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { $0.direction == "debit" && !$0.isReversal && $0.currency == currency && $0.merchant != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        payments = Array(debits.lazy.filter {
            SubscriptionDetector.sameService(merchant: $0.merchant ?? "", subscriptionName: name)
        }.prefix(12))
    }
}
