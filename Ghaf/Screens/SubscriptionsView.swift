import SwiftUI
import SwiftData

struct GhafSubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \GhafSubscription.nextPaymentDate) private var subscriptions: [GhafSubscription]
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @State private var showingEditor = false
    @State private var editing: GhafSubscription?
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
        active.filter { $0.currency == settings.currency }.reduce(Decimal.zero) { total, item in
            let factor: Decimal
            switch item.cycle {
            case .weekly: factor = Decimal(52) / Decimal(12)
            case .monthly: factor = 1
            case .quarterly: factor = Decimal(1) / Decimal(3)
            case .yearly: factor = Decimal(1) / Decimal(12)
            }
            return total + item.amount * factor
        }
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

                    if !suggested.isEmpty { suggestionsCard.ghafEntrance(2) }

                    VStack(spacing: 10) {
                        GhafSectionHeader(title: ar ? "كل الاشتراكات" : "Your subscriptions", theme: theme, languageCode: lang,
                                          actionTitle: ar ? "إضافة" : "Add") { editing = nil; showingEditor = true }
                        if tracked.isEmpty {
                            VStack(spacing: 10) {
                                GhafIconBadge(symbol: "calendar.badge.clock", tint: theme.accent, size: 60)
                                Text(ar ? "لا توجد اشتراكات بعد" : "No subscriptions yet")
                                    .font(GhafTypography.heading(19, languageCode: lang)).foregroundStyle(theme.primaryText)
                                Text(ar ? "أضف خدماتك المتكررة ليذكّرك غاف بموعد التجديد." : "Add recurring services and Ghaf will remind you before renewal.")
                                    .font(GhafTypography.body(14, languageCode: lang)).foregroundStyle(theme.secondaryText)
                                Button { editing = nil; showingEditor = true } label: {
                                    Label(ar ? "إضافة اشتراك" : "Add subscription", systemImage: "plus")
                                }
                                .ghafProminentButton(theme: theme, languageCode: lang)
                                .padding(.top, 6)
                            }
                            .multilineTextAlignment(.center)
                            .padding(22).frame(maxWidth: .infinity).ghafCard(theme: theme)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(tracked) { item in
                                    Button { editing = item; showingEditor = true } label: {
                                        subscriptionRow(item)
                                    }.buttonStyle(.ghafPress)
                                    if item.id != tracked.last?.id { Divider().overlay(theme.outline).padding(.leading, 58) }
                                }
                            }.padding(.horizontal, 16).padding(.vertical, 4).ghafCard(theme: theme)
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
            .sheet(isPresented: $showingEditor) {
                GhafSubscriptionEditor(settings: settings, accounts: accounts.filter { !$0.isArchived }, subscription: editing)
            }
        }
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
                costMetric(ar ? "سنوياً" : "Per year",
                           GhafFormat.money(monthlyEquivalent * 12, currency: settings.currency, languageCode: lang))
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

    private func dismissSuggestion(_ item: GhafSubscription) {
        context.delete(item)
        do { try context.save() } catch { context.rollback() }
    }

    private func subscriptionRow(_ item: GhafSubscription) -> some View {
        let date = item.nextPaymentDate.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: lang)))
        return GhafListRow(icon: "repeat", tint: theme.accent, title: item.name,
                           subtitle: "\(item.cycle.title(language: lang)) · " + (ar ? "التجديد \(date)" : "Renews \(date)"),
                           theme: theme, languageCode: lang) {
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
                            if let subscription { GhafSubscriptionReminderService.cancel(subscription); context.delete(subscription); try? context.save() }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(settings.languageCode == "ar" ? "الاشتراك" : "Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(settings.languageCode == "ar" ? "إلغاء" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(settings.languageCode == "ar" ? "حفظ" : "Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Decimal(string: amount) == nil) }
            }
            .onAppear(perform: load)
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
        } catch { context.rollback() }
    }
}
