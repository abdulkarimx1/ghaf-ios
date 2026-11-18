import SwiftUI
import SwiftData
import GhafCore

struct GhafSubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \GhafSubscription.nextPaymentDate) private var subscriptions: [GhafSubscription]
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    /// One value drives the sheet, so it always opens on the tapped subscription (not a stale or blank one).
    private struct EditorTarget: Identifiable { let id = UUID(); let subscription: GhafSubscription? }
    @State private var editorTarget: EditorTarget?
    @State private var detail: GhafSubscription?
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GhafMetrics.sectionSpacing) {
                    GhafScreenTitle(title: ar ? "الاشتراكات" : "Subscriptions",
                                    subtitle: ar ? "التجديدات القادمة وتكلفتها" : "Renewals, costs and reminders",
                                    languageCode: lang, theme: theme)
                        .ghafEntrance(0)
                    costCard.ghafEntrance(1)
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
                                GhafIconBadge(symbol: "calendar.badge.clock", tint: theme.accent, size: 60)
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
                        } else {
                            ForEach(groups, id: \.title) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.title)
                                        .font(GhafTypography.body(13, languageCode: lang, weight: .bold))
                                        .foregroundStyle(theme.secondaryText)
                                        .padding(.horizontal, 6)
                                    VStack(spacing: 0) {
                                        ForEach(group.items) { item in
                                            Button { detail = item } label: { subscriptionRow(item) }.buttonStyle(.ghafPress)
                                            if item.id != group.items.last?.id { Divider().overlay(theme.outline).padding(.leading, 58) }
                                        }
                                    }.padding(.horizontal, 16).padding(.vertical, 4).ghafCard(theme: theme)
                                }
                            }
                        }
                    }
                    .ghafEntrance(3)
                }
                .padding(.horizontal, GhafMetrics.gutter).padding(.top, 8).padding(.bottom, 28)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.success, trigger: confirmedCount)
            .animation(.snappy, value: subscriptions.count)
            .sheet(item: $detail) { item in
                GhafSubscriptionDetailView(subscription: item, settings: settings, accounts: accounts.filter { !$0.isArchived })
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $editorTarget) { target in
                GhafSubscriptionEditor(settings: settings, accounts: accounts.filter { !$0.isArchived }, subscription: target.subscription)
            }
        }
    }

    private func daysUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
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
                    GhafBrandBadge(name: item.name, fallbackTint: theme.accent, size: 46)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ar ? "التالي" : "Next up")
                        .font(GhafTypography.body(12, languageCode: lang, weight: .bold))
                        .foregroundStyle(theme.accent)
                    Text(item.name)
                        .font(GhafTypography.heading(18, languageCode: lang))
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
        .background(theme.ink, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
        let today = Calendar.current.startOfDay(for: .now)
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
                        Text(item.name).font(GhafTypography.body(15, languageCode: lang, weight: .semibold))
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
    let settings: GhafSettings
    let accounts: [GhafAccount]
    let subscription: GhafSubscription?
    @State private var name = ""
    @State private var amount = ""
    @State private var currency = "AED"
    @State private var cycle: GhafBillingCycle = .monthly
    @State private var nextDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var category = "Subscriptions"
    @State private var accountID: UUID?
    @State private var reminderDays = 2
    @State private var active = true
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section(settings.languageCode == "ar" ? "تفاصيل الاشتراك" : "Subscription details") {
                    TextField(settings.languageCode == "ar" ? "اسم الخدمة" : "Service name", text: $name)
                    TextField(settings.languageCode == "ar" ? "المبلغ" : "Amount", text: $amount).keyboardType(.decimalPad)
                    Picker(settings.languageCode == "ar" ? "العملة" : "Currency", selection: $currency) {
                        ForEach(["AED","SAR","KWD","BHD","OMR","QAR"], id: \.self) { Text($0).tag($0) }
                    }
                    Picker(settings.languageCode == "ar" ? "دورة الفوترة" : "Billing cycle", selection: $cycle) {
                        ForEach(GhafBillingCycle.allCases) { Text($0.title(language: settings.languageCode)).tag($0) }
                    }
                    DatePicker(settings.languageCode == "ar" ? "موعد التجديد القادم" : "Next renewal", selection: $nextDate, displayedComponents: .date)
                }
                Section(settings.languageCode == "ar" ? "التذكير والحساب" : "Reminder & account") {
                    Picker(settings.languageCode == "ar" ? "ذكّرني قبل" : "Remind me", selection: $reminderDays) {
                        Text(settings.languageCode == "ar" ? "في نفس اليوم" : "Same day").tag(0)
                        Text(settings.languageCode == "ar" ? "قبل يوم" : "1 day before").tag(1)
                        Text(settings.languageCode == "ar" ? "قبل يومين" : "2 days before").tag(2)
                        Text(settings.languageCode == "ar" ? "قبل أسبوع" : "1 week before").tag(7)
                    }
                    Picker(settings.languageCode == "ar" ? "الحساب" : "Payment account", selection: $accountID) {
                        Text(settings.languageCode == "ar" ? "غير محدد" : "Not specified").tag(UUID?.none)
                        ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Toggle(settings.languageCode == "ar" ? "نشط" : "Active", isOn: $active)
                }
                if subscription != nil {
                    Section {
                        Button(settings.languageCode == "ar" ? "حذف الاشتراك" : "Delete subscription", role: .destructive) {
                            guard let subscription else { return dismiss() }
                            context.delete(subscription)
                            do {
                                try context.save()
                                GhafSubscriptionReminderService.cancel(subscription)
                                dismiss()
                            } catch {
                                context.rollback()
                                saveFailed = true
                            }
                        }
                    }
                }
            }
            .ghafKeyboardDone()
            .navigationTitle(settings.languageCode == "ar" ? "الاشتراك" : "Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(settings.languageCode == "ar" ? "إلغاء" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(settings.languageCode == "ar" ? "حفظ" : "Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Decimal(string: amount) == nil) }
            }
            .onAppear(perform: load)
            .alert(settings.languageCode == "ar" ? "تعذر حفظ التغيير" : "Couldn't save the change",
                   isPresented: $saveFailed) {
                Button(settings.languageCode == "ar" ? "حسناً" : "OK", role: .cancel) {}
            } message: {
                Text(settings.languageCode == "ar" ? "لم يتغير شيء. حاول مرة أخرى." : "Nothing was changed. Please try again.")
            }
        }
    }

    private func load() {
        guard let subscription else { return }
        name = subscription.name; amount = NSDecimalNumber(decimal: subscription.amount).stringValue
        currency = subscription.currency; cycle = subscription.cycle; nextDate = subscription.nextPaymentDate
        category = subscription.category; accountID = subscription.accountID
        reminderDays = subscription.reminderDays; active = subscription.isActive
    }

    private func save() {
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
            Task {
                _ = await GhafSubscriptionReminderService.requestPermission()
                GhafSubscriptionReminderService.schedule(item, language: settings.languageCode)
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    let subscription: GhafSubscription
    let settings: GhafSettings
    let accounts: [GhafAccount]

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
                }
                .padding(.horizontal, GhafMetrics.gutter)
                .padding(.top, 8).padding(.bottom, 20)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .safeAreaInset(edge: .bottom) {
                GhafDetailActionBar(theme: theme, languageCode: lang,
                                    secondarySymbol: subscription.isActive ? "pause.fill" : "play.fill",
                                    secondaryLabel: subscription.isActive ? (ar ? "إيقاف مؤقت" : "Pause") : (ar ? "استئناف" : "Resume"),
                                    secondaryAction: toggleActive,
                                    primaryTitle: ar ? "تعديل الاشتراك" : "Edit subscription",
                                    primaryAction: { editing = true })
            }
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
            }
            .onAppear(perform: load)
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var header: some View {
        VStack(spacing: 8) {
            GhafStatusMark(tint: theme.primaryText) {
                GhafBrandBadge(name: subscription.name, fallbackTint: theme.accent, size: 60)
            }
            Text(subscription.name)
                .font(GhafTypography.heading(24, languageCode: lang))
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
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
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
                .padding(.horizontal, GhafMetrics.gutter).padding(.vertical, 12)
                .background(theme.surface, in: Capsule())
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
