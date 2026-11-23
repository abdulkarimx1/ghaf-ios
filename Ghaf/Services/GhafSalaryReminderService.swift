import Foundation
import UserNotifications
import SwiftUI
import SwiftData
import GhafCore

enum GhafSalaryReminderService {
    static let identifier = "ghaf.salary.reminder"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )) ?? false
    }

    static func scheduleNext(
        salaryDay: Int,
        languageCode: String,
        salaryAmount: Decimal? = nil,
        salaryCurrency: String = "AED"
    ) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let date = GhafSalaryCycle.nextSalaryDate(after: .now, salaryDay: salaryDay)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = languageCode == "ar" ? "موعد الراتب" : "Salary day"
        let expected = salaryAmount.map { GhafFormat.shownMoney($0, currency: salaryCurrency, languageCode: languageCode) }
        content.body = languageCode == "ar"
            ? "هل وصلك راتبك\(expected.map { " البالغ \($0)" } ?? "")؟ افتح غاف لتأكيد الاستلام وتحديث رصيدك."
            : "Has your salary\(expected.map { " of \($0)" } ?? "") arrived? Open Ghaf to confirm it and update your balance."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
        )
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

struct GhafSalaryCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme

    let settings: GhafSettings
    let accounts: [GhafAccount]

    @State private var amountText = ""
    @State private var selectedAccountID: UUID?
    @State private var showError = false

    private var activeAccounts: [GhafAccount] {
        accounts.filter { !$0.isArchived }
    }

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var periodKey: String {
        GhafSalaryCycle.periodKey(for: .now, salaryDay: settings.salaryDay ?? 1)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 17) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(theme.accent)

                Text(settings.languageCode == "ar" ? "هل وصلك راتبك؟" : "Has your salary arrived?")
                    .font(GhafTypography.display(29, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)

                Text(settings.languageCode == "ar"
                     ? "أكد الاستلام لتحديث رصيد الحساب ودورة ميزانيتك."
                     : "Confirm it to update the selected account balance and salary cycle.")
                    .font(GhafTypography.body(14, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)

                VStack(alignment: .leading, spacing: 7) {
                    Text(settings.languageCode == "ar" ? "المبلغ المستلم" : "AMOUNT RECEIVED")
                        .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(theme.secondaryText)
                    GhafAmountField(value: $amountText, currency: activeAccounts.first(where: { $0.id == selectedAccountID })?.currency ?? settings.currency,
                                    label: settings.languageCode == "ar" ? "المبلغ المستلم" : "Amount received",
                                    theme: theme, languageCode: settings.languageCode, fontSize: 25)
                    if let account = activeAccounts.first(where: { $0.id == selectedAccountID }),
                       account.currency != (settings.salaryCurrency ?? settings.currency) {
                        Text(settings.languageCode == "ar"
                             ? "أدخل المبلغ بعملة الحساب \(account.currency). سيبقى مبلغ الراتب المتوقع بعملة \(settings.salaryCurrency ?? settings.currency)."
                             : "Enter the amount in the account currency (\(account.currency)). Expected salary remains in \(settings.salaryCurrency ?? settings.currency).")
                            .font(GhafTypography.body(12, languageCode: settings.languageCode))
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(settings.languageCode == "ar" ? "أودع في الحساب" : "DEPOSIT INTO")
                        .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(theme.secondaryText)

                    GhafMenuRow(title: settings.languageCode == "ar" ? "الحساب" : "Account", value: activeAccounts.first(where: { $0.id == selectedAccountID })?.name ?? "", theme: theme, languageCode: settings.languageCode) {
                        Picker(settings.languageCode == "ar" ? "الحساب" : "Account", selection: $selectedAccountID) {
                            ForEach(activeAccounts, id: \.id) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                    }
                }

                if showError {
                    Text(settings.languageCode == "ar" ? "أدخل مبلغاً واختر الحساب." : "Enter an amount and choose an account.")
                        .font(GhafTypography.body(12, languageCode: settings.languageCode))
                        .foregroundStyle(theme.over)
                }

                Spacer(minLength: 4)

                Button(settings.languageCode == "ar" ? "نعم، وصلني الراتب" : "Yes, salary received") {
                    confirmReceived()
                }
                .ghafProminentButton(theme: theme, languageCode: settings.languageCode)

                Button(settings.languageCode == "ar" ? "لم يصل بعد" : "Not received yet") {
                    recordNotReceived()
                }
                .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
            .padding(22)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(settings.languageCode == "ar" ? "تأكيد الراتب" : "Salary check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.languageCode == "ar" ? "إغلاق" : "Close") { dismiss() }
                }
            }
            .onAppear(perform: loadDefaults)
            .onChange(of: selectedAccountID) { _, _ in updateAmountForSelectedAccount() }
        }
    }

    private func loadDefaults() {
        selectedAccountID = settings.salaryAccountID
            ?? activeAccounts.first(where: \.isPrimary)?.id
            ?? activeAccounts.first?.id
        if amountText.isEmpty {
            let selectedCurrency = activeAccounts.first(where: { $0.id == selectedAccountID })?.currency
            let salaryCurrency = settings.salaryCurrency ?? settings.currency
            amountText = selectedCurrency == salaryCurrency
                ? (settings.salaryAmount.map(GhafFormat.decimal) ?? GhafFormat.decimal(settings.monthlyIncome))
                : ""
        }
    }

    private func updateAmountForSelectedAccount() {
        guard let account = activeAccounts.first(where: { $0.id == selectedAccountID }) else {
            amountText = ""
            return
        }
        let salaryCurrency = settings.salaryCurrency ?? settings.currency
        guard account.currency == salaryCurrency else {
            amountText = ""
            return
        }
        amountText = settings.salaryAmount.map(GhafFormat.decimal)
            ?? GhafFormat.decimal(settings.monthlyIncome)
    }

    private func confirmReceived() {
        guard let amount = Decimal(string: amountText), amount > 0,
              let accountID = selectedAccountID,
              let account = activeAccounts.first(where: { $0.id == accountID }) else {
            showError = true
            return
        }

        let fingerprint = "salary-\(periodKey)"
        let descriptor = FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )

        do {
            if try modelContext.fetch(descriptor).isEmpty {
                let parsed = ParsedTransaction(
                    amount: amount,
                    currency: account.currency,
                    merchant: settings.languageCode == "ar" ? "الراتب" : "Salary",
                    date: .now,
                    direction: .credit,
                    confidence: 1,
                    bank: account.institution
                )
                let transaction = GhafTransaction(
                    fingerprint: fingerprint,
                    parsed: parsed,
                    category: "Salary",
                    needsReview: false,
                    isReversal: false,
                    accountID: account.id
                )
                modelContext.insert(transaction)
            }

            settings.lastSalaryDecisionKey = periodKey
            settings.salaryAccountID = account.id
            if account.currency == (settings.salaryCurrency ?? settings.currency) {
                settings.salaryAmount = amount
            }
            try modelContext.save()
            dismiss()
        } catch {
            showError = true
        }
    }

    private func recordNotReceived() {
        settings.lastSalaryDecisionKey = periodKey
        do {
            try modelContext.save()
            dismiss()
        } catch {
            showError = true
        }
    }
}


struct GhafSalarySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]

    let settings: GhafSettings

    @State private var enabled = false
    @State private var salaryDay = 28
    @State private var amountText = ""
    @State private var salaryCurrency = "AED"
    @State private var accountID: UUID?
    @State private var reminderEnabled = true
    @State private var errorMessage = ""

    private var activeAccounts: [GhafAccount] {
        accounts.filter { !$0.isArchived }
    }

    private let supportedCurrencies = ["AED", "SAR", "OMR", "USD", "EUR", "GBP", "KWD", "BHD", "QAR"]

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GhafFormCard(theme: theme) {
                    GhafFormToggleRow(icon: "calendar.badge.clock", tint: theme.accent,
                                      title: settings.languageCode == "ar" ? "تفعيل دورة الراتب" : "Track my salary cycle",
                                      isOn: $enabled, theme: theme, languageCode: settings.languageCode)
                }
                Text(settings.languageCode == "ar"
                     ? "سيطلب منك غاف تأكيد وصول الراتب في يوم الاستحقاق."
                     : "Ghaf will ask you to confirm whether your salary arrived on its scheduled day.")
                    .font(GhafTypography.body(13, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText).padding(.horizontal, 4).padding(.bottom, 12)

                if enabled {
                    GhafFormCard(theme: theme) {
                        GhafFormMenuRow(icon: "calendar", tint: theme.accent,
                                        title: settings.languageCode == "ar" ? "يوم الراتب" : "Salary day",
                                        value: "\(salaryDay)", theme: theme, languageCode: settings.languageCode) {
                            Picker(settings.languageCode == "ar" ? "يوم الراتب" : "Salary day", selection: $salaryDay) {
                                ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                            }
                        }
                        GhafFormDivider(theme: theme)
                        GhafFormRow(icon: "banknote", tint: theme.comfortable,
                                    title: settings.languageCode == "ar" ? "المبلغ المتوقع" : "Expected",
                                    theme: theme, languageCode: settings.languageCode) {
                            GhafAmountField(value: $amountText,
                                            currency: salaryCurrency,
                                            label: "", theme: theme, languageCode: settings.languageCode, fontSize: 15,
                                            chromeless: true, trailingAligned: true, groupsDigits: true)
                                .environment(\.layoutDirection, .leftToRight)
                                .frame(width: 132)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        GhafFormDivider(theme: theme)
                        GhafFormMenuRow(icon: "wallet.pass", tint: theme.accent,
                                        title: settings.languageCode == "ar" ? "حساب الإيداع" : "Deposit account",
                                        value: activeAccounts.first(where: { $0.id == accountID })?.name ?? "",
                                        theme: theme, languageCode: settings.languageCode) {
                            Picker(settings.languageCode == "ar" ? "حساب الإيداع" : "Deposit account", selection: $accountID) {
                                ForEach(activeAccounts, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                        GhafFormDivider(theme: theme)
                        GhafFormMenuRow(icon: "dollarsign.circle", tint: theme.accent,
                                        title: settings.languageCode == "ar" ? "عملة الراتب" : "Salary currency",
                                        value: "\(salaryCurrency) · \(GhafCurrencyIcon.name(salaryCurrency, languageCode: settings.languageCode))",
                                        theme: theme, languageCode: settings.languageCode) {
                            ForEach(supportedCurrencies, id: \.self) { code in
                                Button {
                                    salaryCurrency = code
                                } label: {
                                    if let asset = GhafCurrencyIcon.assetName(code) {
                                        Label("\(code) · \(GhafCurrencyIcon.name(code, languageCode: settings.languageCode))", image: asset)
                                    } else {
                                        Text("\(code) · \(GhafCurrencyIcon.name(code, languageCode: settings.languageCode))")
                                    }
                                }
                            }
                        }
                        GhafFormDivider(theme: theme)
                        GhafFormToggleRow(icon: "bell.badge", tint: theme.close,
                                          title: settings.languageCode == "ar" ? "تذكيري في يوم الراتب" : "Notify me on salary day",
                                          isOn: $reminderEnabled, theme: theme, languageCode: settings.languageCode)
                    }
                    if activeAccounts.isEmpty {
                        Text(settings.languageCode == "ar" ? "أضف حساباً بنكياً أولاً من صفحة الحسابات." : "Add a bank account first from Accounts.")
                            .foregroundStyle(theme.secondaryText).padding(.horizontal, 4)
                    }
                }
                if !errorMessage.isEmpty { Text(errorMessage).foregroundStyle(theme.over).padding(.horizontal, 4) }
                Button(settings.languageCode == "ar" ? "حفظ إعدادات الراتب" : "Save salary settings", action: save)
                    .ghafProminentButton(theme: theme, languageCode: settings.languageCode)
            }
            .ghafScreenPadding().padding(.bottom, 40)
        }
        .ghafBackground(theme: theme).tint(theme.accent)
        .ghafPageTitle(settings.languageCode == "ar" ? "إعداد الراتب" : "Salary settings", languageCode: settings.languageCode, theme: theme)
        .onAppear(perform: load)
    }

    private func load() {
#if DEBUG
        enabled = GhafScreenshotFixture.enabled && GhafScreenshotFixture.screen == "salary-settings"
            ? true : (settings.salaryEnabled ?? false)
#else
        enabled = settings.salaryEnabled ?? false
#endif
        salaryDay = settings.salaryDay ?? 28
        amountText = settings.salaryAmount.map(GhafFormat.decimal)
            ?? GhafFormat.decimal(settings.monthlyIncome)
        salaryCurrency = settings.salaryCurrency ?? settings.currency
        accountID = settings.salaryAccountID
            ?? activeAccounts.first(where: \.isPrimary)?.id
            ?? activeAccounts.first?.id
        reminderEnabled = settings.salaryReminderEnabled ?? true
    }

    private func save() {
        if enabled && activeAccounts.isEmpty {
            errorMessage = settings.languageCode == "ar"
                ? "أضف حساباً بنكياً أو محفظة أولاً."
                : "Add an account before enabling the salary cycle."
            return
        }

        if enabled && !amountText.isEmpty && Decimal(string: amountText) == nil {
            errorMessage = settings.languageCode == "ar"
                ? "أدخل مبلغاً صحيحاً."
                : "Enter a valid salary amount."
            return
        }

        settings.salaryEnabled = enabled
        settings.salaryDay = enabled ? salaryDay : nil
        settings.salaryAmount = enabled ? Decimal(string: amountText) : nil
        settings.salaryAccountID = enabled ? (accountID ?? activeAccounts.first?.id) : nil
        settings.salaryCurrency = salaryCurrency
        settings.salaryReminderEnabled = enabled && reminderEnabled

        do {
            try modelContext.save()
            errorMessage = ""
            if enabled && reminderEnabled {
                Task {
                    _ = await GhafSalaryReminderService.requestPermission()
                    try? await GhafSalaryReminderService.scheduleNext(
                        salaryDay: salaryDay,
                        languageCode: settings.languageCode,
                        salaryAmount: settings.salaryAmount,
                        salaryCurrency: salaryCurrency
                    )
                }
            } else {
                GhafSalaryReminderService.cancel()
            }
        } catch {
            errorMessage = settings.languageCode == "ar"
                ? "تعذر حفظ إعدادات الراتب."
                : "Could not save salary settings."
        }
    }
}
