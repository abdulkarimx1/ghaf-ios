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
    private var monthlyEquivalent: Decimal {
        active.reduce(Decimal.zero) { total, item in
            let factor: Decimal
            switch item.cycle {
            case .weekly: factor = 52 / 12
            case .monthly: factor = 1
            case .quarterly: factor = 1 / 3
            case .yearly: factor = 1 / 12
            }
            return total + item.amount * factor
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 5) {
                        Text(settings.languageCode == "ar" ? "الاشتراكات" : "RECURRING COMMITMENTS")
                            .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .bold))
                            .tracking(1.4).foregroundStyle(theme.secondaryText)
                        Text(settings.languageCode == "ar" ? "اشتراكاتك" : "Subscriptions")
                            .font(GhafTypography.display(32, languageCode: settings.languageCode))
                            .foregroundStyle(theme.primaryText)
                        Text(settings.languageCode == "ar" ? "تابع التجديدات القادمة وتكلفتها." : "Keep renewals, costs and reminders in one place.")
                            .font(GhafTypography.body(14, languageCode: settings.languageCode))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(settings.languageCode == "ar" ? "التكلفة الشهرية المقدرة" : "ESTIMATED MONTHLY")
                                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                                .foregroundStyle(theme.secondaryText)
                            Text(GhafFormat.money(monthlyEquivalent, currency: settings.currency, languageCode: settings.languageCode))
                                .font(GhafTypography.number(25, weight: .bold)).foregroundStyle(theme.primaryText)
                        }
                        Spacer()
                        Image(systemName: "repeat").font(.system(size: 24, weight: .semibold)).foregroundStyle(theme.accent)
                    }
                    .padding(18).ghafCard(theme: theme, radius: 20)

                    if !suggested.isEmpty { suggestionsCard }

                    HStack {
                        Text(settings.languageCode == "ar" ? "كل الاشتراكات" : "YOUR SUBSCRIPTIONS")
                            .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .bold))
                            .tracking(1).foregroundStyle(theme.secondaryText)
                        Spacer()
                        Button { editing = nil; showingEditor = true } label: {
                            Label(settings.languageCode == "ar" ? "إضافة" : "Add", systemImage: "plus")
                                .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .bold))
                        }.buttonStyle(.borderedProminent).tint(theme.accent)
                    }
                    if tracked.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "calendar.badge.clock").font(.system(size: 30, weight: .medium)).foregroundStyle(theme.accent)
                            Text(settings.languageCode == "ar" ? "لا توجد اشتراكات بعد" : "No subscriptions yet")
                                .font(GhafTypography.heading(19, languageCode: settings.languageCode)).foregroundStyle(theme.primaryText)
                            Text(settings.languageCode == "ar" ? "أضف خدماتك المتكررة ليذكّرك غاف بموعد التجديد." : "Add recurring services and Ghaf will remind you before renewal.")
                                .font(GhafTypography.body(14, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).ghafCard(theme: theme, radius: 18)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(tracked) { item in
                                Button { editing = item; showingEditor = true } label: {
                                    subscriptionRow(item)
                                }.buttonStyle(.plain)
                                if item.id != tracked.last?.id { Divider().overlay(theme.outline).padding(.leading, 58) }
                            }
                        }.padding(.horizontal, 14).ghafCard(theme: theme, radius: 18)
                    }
                }
                .padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingEditor) {
                GhafSubscriptionEditor(settings: settings, accounts: accounts.filter { !$0.isArchived }, subscription: editing)
            }
        }
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
                        Button { dismissSuggestion(item) } label: {
                            Text(ar ? "ليس اشتراكاً" : "Not a subscription").frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.bordered).tint(theme.secondaryText)
                        Button { confirm(item) } label: {
                            Text(ar ? "تأكيد" : "Confirm").frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.borderedProminent).tint(theme.accent)
                    }
                    .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .bold))
                }
            }
        }
        .padding(16).ghafCard(theme: theme, radius: 18)
    }

    private func confirm(_ item: GhafSubscription) {
        item.needsConfirmation = false
        item.isActive = true
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
        HStack(spacing: 12) {
            Image(systemName: "repeat").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.accent)
                .frame(width: 42, height: 42).background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(GhafTypography.body(16, languageCode: settings.languageCode, weight: .bold)).foregroundStyle(theme.primaryText)
                Text("\(item.cycle.title(language: settings.languageCode)) · \(item.nextPaymentDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(GhafTypography.body(12, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 4)
            Text(GhafFormat.money(item.amount, currency: item.currency, languageCode: settings.languageCode))
                .font(GhafTypography.number(14, weight: .bold)).foregroundStyle(theme.primaryText)
        }.padding(.vertical, 13).contentShape(Rectangle())
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
