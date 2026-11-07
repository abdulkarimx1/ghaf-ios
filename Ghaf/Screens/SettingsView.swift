import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum GhafSettingsPrompt: Identifiable {
    case deleteData
    case importBackup
    case message(String)

    var id: String {
        switch self {
        case .deleteData: return "delete"
        case .importBackup: return "import"
        case .message(let value): return "message-\(value)"
        }
    }
}

struct GhafSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme

    let settings: GhafSettings

    @State private var name = ""
    @State private var languageCode = "en"
    @State private var currency = "AED"
    @State private var income = ""
    @State private var commitments = ""
    @State private var themeName = "Oasis"
    @State private var appearanceMode = "System"
    @State private var budgetMode = "Daily"
    @State private var newCategory = ""
    @State private var categoryBudgetTexts: [String: String] = [:]
    @State private var backupURL: URL?
    @State private var pendingImportURL: URL?
    @State private var showImporter = false
    @State private var prompt: GhafSettingsPrompt?

    private let currencies = ["AED", "USD", "EUR", "GBP", "SAR", "KWD", "BHD", "OMR", "QAR"]

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: themeName,
            appearanceMode: appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeading

                    profileCard
                    languageCard
                    accountManagementCard
                    salaryManagementCard
                    automationCard
                    appearanceCard
                    securityCard
                    budgetCard
                    categoriesCard
                    backupCard
                    aboutCard
                    dangerCard

                    Button("Save settings", action: saveSettings)
                        .ghafProminentButton(theme: theme, languageCode: languageCode)
                        .padding(.top, 2)

                    Text("Your data stays on this iPhone. Ghaf does not connect to a financial server.")
                        .font(GhafTypography.body(12, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background.ignoresSafeArea())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .tint(theme.accent)
            .onAppear(perform: loadSettings)
            .onChange(of: languageCode) { _, newValue in
                settings.languageCode = newValue
                try? modelContext.save()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        pendingImportURL = url
                        prompt = .importBackup
                    }
                case .failure(let error):
                    prompt = .message("Import failed: \(error.localizedDescription)")
                }
            }
            .alert(item: $prompt) { selectedPrompt in
                switch selectedPrompt {
                case .deleteData:
                    return Alert(
                        title: Text("Delete all data?"),
                        message: Text("All transactions, settings and learned merchant rules will be permanently deleted."),
                        primaryButton: .destructive(Text("Delete everything"), action: deleteAllData),
                        secondaryButton: .cancel()
                    )
                case .importBackup:
                    return Alert(
                        title: Text("Replace current data?"),
                        message: Text("Importing this backup replaces all existing Ghaf records on this device."),
                        primaryButton: .destructive(Text("Replace data"), action: restoreBackup),
                        secondaryButton: .cancel()
                    )
                case .message(let message):
                    return Alert(
                        title: Text("Ghaf"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PREFERENCES")
                .font(GhafTypography.body(10, languageCode: languageCode, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(theme.secondaryText)
            Text(languageCode == "ar" ? "الإعدادات" : "Settings")
                .font(GhafTypography.display(34, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)
            Text(languageCode == "ar" ? "خصص غاف حسب طريقتك في إدارة المال." : "Make Ghaf work the way you manage money.")
                .font(GhafTypography.body(14, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.bottom, 4)
    }

    private var profileCard: some View {
        settingsCard("Profile", subtitle: "Your account display and primary currency") {
            settingsLabel("Your name")
            settingsField("Name", text: $name)

            settingsLabel("Main currency")
            Picker("Main currency", selection: $currency) {
                ForEach(currencies, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(theme.accent)
        }
    }

    private var languageCard: some View {
        settingsCard("Language", subtitle: "The language used throughout Ghaf") {
            Picker("App language", selection: $languageCode) {
                Text("English").tag("en")
                Text("العربية").tag("ar")
            }
            .pickerStyle(.segmented)
        }
    }

    private var accountManagementCard: some View {
        NavigationLink {
            GhafAccountsView(settings: settings)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "wallet.pass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
                    .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    Text(languageCode == "ar" ? "الحسابات والمحافظ" : "Accounts & wallets")
                        .font(GhafTypography.heading(16, languageCode: languageCode))
                        .foregroundStyle(theme.primaryText)
                    Text(languageCode == "ar"
                         ? "إدارة البطاقات والأرصدة والعملات"
                         : "Manage cards, balances and currencies")
                        .font(GhafTypography.body(12, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ghafLiquidGlass(theme: theme, radius: 19)
    }

    private var salaryManagementCard: some View {
        NavigationLink {
            GhafSalarySettingsView(settings: settings)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
                    .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    Text(languageCode == "ar" ? "دورة الراتب" : "Salary cycle")
                        .font(GhafTypography.heading(16, languageCode: languageCode))
                        .foregroundStyle(theme.primaryText)
                    Text(languageCode == "ar"
                         ? "حدد يوم الاستحقاق وتأكيد الإيداع"
                         : "Set payday and confirm each deposit")
                        .font(GhafTypography.body(12, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ghafLiquidGlass(theme: theme, radius: 19)
    }

    private var automationCard: some View {
        NavigationLink {
            GhafAutomationGuideView(settings: settings)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 48, height: 48)
                    .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Bank automation")
                        .font(GhafTypography.heading(18, languageCode: languageCode))
                        .foregroundStyle(theme.primaryText)
                    Text("Set up automatic transaction capture")
                        .font(GhafTypography.body(13, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ghafLiquidGlass(theme: theme, radius: 20)
    }

    private var appearanceCard: some View {
        settingsCard("Appearance", subtitle: "A quiet palette with clear contrast") {
            settingsLabel("Theme")
            Picker("Theme", selection: $themeName) {
                Text("Dawn").tag("Dawn")
                Text("Dusk").tag("Dusk")
                Text("Oasis").tag("Oasis")
            }
            .pickerStyle(.segmented)

            settingsLabel("Appearance mode")
            Picker("Appearance mode", selection: $appearanceMode) {
                Text("System").tag("System")
                Text("Light").tag("Light")
                Text("Dark").tag("Dark")
            }
            .pickerStyle(.segmented)

            HStack(spacing: 9) {
                Circle().fill(theme.accent).frame(width: 16, height: 16)
                Text("\(themeName) preview")
                    .font(GhafTypography.body(13, languageCode: languageCode, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                RoundedRectangle(cornerRadius: 6).fill(theme.accent).frame(width: 24, height: 16)
                RoundedRectangle(cornerRadius: 6).fill(theme.comfortable).frame(width: 24, height: 16)
            }
            .padding(.top, 4)
        }
    }

    private var securityCard: some View {
        settingsCard(
            languageCode == "ar" ? "الأمان والخصوصية" : "Security & privacy",
            subtitle: languageCode == "ar"
                ? "احمِ بياناتك المالية عند فتح التطبيق"
                : "Protect your financial data when opening Ghaf"
        ) {
            Toggle(isOn: Binding(
                get: { settings.biometricLockEnabled ?? false },
                set: { enabled in
                    settings.biometricLockEnabled = enabled
                    do {
                        try modelContext.save()
                    } catch {
                        prompt = .message(languageCode == "ar"
                            ? "تعذر حفظ إعداد الأمان."
                            : "Could not save the security setting.")
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageCode == "ar" ? "القفل بالبصمة أو رمز الجهاز" : "Require Face ID or device passcode")
                        .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(languageCode == "ar"
                        ? "يتطلب المصادقة عند فتح غاف أو العودة إليه."
                        : "Authenticate when opening Ghaf or returning to it.")
                        .font(GhafTypography.body(11, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .tint(theme.accent)

            Text(languageCode == "ar"
                ? "يستخدم غاف آلية المصادقة الآمنة في iOS. قد يطلب رمز دخول الجهاز إذا لم تكن البصمة متاحة."
                : "Ghaf uses iOS device authentication. Your device passcode may be requested when biometrics are unavailable.")
                .font(GhafTypography.body(11, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var budgetCard: some View {
        settingsCard("Budget", subtitle: "Choose how your available money is measured") {
            Picker("Budget method", selection: $budgetMode) {
                Text("Daily limit").tag("Daily")
                Text("Category budgets").tag("Category")
            }
            .pickerStyle(.segmented)

            if budgetMode == "Daily" {
                settingsLabel("Monthly income")
                settingsField("e.g. 5000", text: $income, numeric: true)

                settingsLabel("Fixed monthly commitments")
                settingsField("e.g. 1500", text: $commitments, numeric: true)

                Text("Daily budget = (income − commitments) ÷ days in month.")
                    .font(GhafTypography.body(12, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            } else {
                Text("Set a monthly spending limit for each category.")
                    .font(GhafTypography.body(13, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)

                ForEach(settings.categories, id: \.self) { category in
                    HStack(spacing: 12) {
                        Text(category)
                            .font(GhafTypography.body(14, languageCode: languageCode, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        TextField("0", text: budgetBinding(for: category))
                            .font(GhafTypography.number(14))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 106)
                            .padding(10)
                            .background(theme.background, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var categoriesCard: some View {
        settingsCard("Categories", subtitle: "Teach Ghaf how you group your spending") {
            ForEach(settings.categories, id: \.self) { category in
                HStack {
                    Text(category)
                        .font(GhafTypography.body(14, languageCode: languageCode, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    Button(role: .destructive) {
                        removeCategory(category)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 17, weight: .medium))
                    }
                }
                .padding(.vertical, 3)
            }

            HStack(spacing: 8) {
                TextField("New category", text: $newCategory)
                    .font(GhafTypography.body(14, languageCode: languageCode))
                    .padding(12)
                    .background(theme.background, in: RoundedRectangle(cornerRadius: 12))

                Button(action: addCategory) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.accentContrast)
                        .frame(width: 44, height: 44)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
    }

    private var backupCard: some View {
        settingsCard("Data and backup", subtitle: "Move or keep a copy of your local records") {
            Button(action: createBackup) {
                settingsActionRow("Create JSON backup", detail: "Export transactions, settings and learned merchants", icon: "square.and.arrow.up")
            }
            .buttonStyle(.plain)

            if let backupURL {
                ShareLink(item: backupURL) {
                    settingsActionRow("Share or save backup", detail: "Choose Files, AirDrop or another destination", icon: "square.and.arrow.up.on.square")
                }
                .buttonStyle(.plain)
            }

            Button { showImporter = true } label: {
                settingsActionRow("Import JSON backup", detail: "Replace the current local data with a backup", icon: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutCard: some View {
        NavigationLink {
            GhafAboutView(settings: settings)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "leaf")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
                    .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    Text(languageCode == "ar" ? "عن غــــاف" : "About Ghaf")
                        .font(GhafTypography.heading(16, languageCode: languageCode))
                        .foregroundStyle(theme.primaryText)
                    Text(languageCode == "ar" ? "القصة والمطور وحقوق التطبيق" : "The story, developer and app credits")
                        .font(GhafTypography.body(12, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ghafLiquidGlass(theme: theme, radius: 19)
    }

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Danger zone")
                .font(GhafTypography.heading(17, languageCode: languageCode))
                .foregroundStyle(theme.over)
            Text("Permanently remove transactions, settings and learned merchant rules from this iPhone.")
                .font(GhafTypography.body(13, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)

            Button(role: .destructive) {
                prompt = .deleteData
            } label: {
                Label("Delete all Ghaf data", systemImage: "trash")
                    .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(theme.over.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.over.opacity(0.30), lineWidth: 1))
    }

    private func settingsCard<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(GhafTypography.heading(18, languageCode: languageCode))
                    .foregroundStyle(theme.primaryText)
                Text(subtitle)
                    .font(GhafTypography.body(12, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme, radius: 20)
    }

    private func settingsLabel(_ title: String) -> some View {
        Text(title)
            .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
    }

    private func settingsField(
        _ placeholder: String,
        text: Binding<String>,
        numeric: Bool = false
    ) -> some View {
        TextField(placeholder, text: text)
            .font(GhafTypography.body(15, languageCode: languageCode))
            .keyboardType(numeric ? .decimalPad : .default)
            .padding(13)
            .background(theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.outline, lineWidth: 1))
    }

    private func settingsActionRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(detail)
                    .font(GhafTypography.body(11, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func loadSettings() {
        name = settings.userName
        languageCode = settings.languageCode
        currency = settings.currency
        income = GhafFormat.decimal(settings.monthlyIncome)
        commitments = GhafFormat.decimal(settings.fixedCommitments)
        themeName = settings.themeName
        appearanceMode = settings.appearanceMode
        budgetMode = settings.budgetMode

        for category in settings.categories {
            let value = settings.categoryBudgets[category]
            categoryBudgetTexts[category] = value.map(GhafFormat.decimal) ?? ""
        }
    }

    private func saveSettings() {
        settings.userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.languageCode = languageCode
        settings.currency = currency
        settings.monthlyIncome = Decimal(string: income) ?? 0
        settings.fixedCommitments = Decimal(string: commitments) ?? 0
        settings.themeName = themeName
        settings.appearanceMode = appearanceMode
        settings.budgetMode = budgetMode

        var budgets: [String: Decimal] = [:]
        for (category, value) in categoryBudgetTexts {
            if let amount = Decimal(string: value), amount > 0 {
                budgets[category] = amount
            }
        }
        settings.categoryBudgets = budgets

        do {
            try modelContext.save()
            prompt = .message("Settings saved successfully.")
        } catch {
            prompt = .message("Could not save settings.")
        }
    }

    private func budgetBinding(for category: String) -> Binding<String> {
        Binding(
            get: { categoryBudgetTexts[category] ?? "" },
            set: { categoryBudgetTexts[category] = $0 }
        )
    }

    private func addCategory() {
        let value = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        var categories = settings.categories
        guard !categories.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
            newCategory = ""
            return
        }

        categories.append(value)
        settings.categories = categories
        newCategory = ""
        try? modelContext.save()
    }

    private func removeCategory(_ category: String) {
        var categories = settings.categories
        guard categories.count > 1 else { return }

        categories.removeAll { $0 == category }
        settings.categories = categories
        categoryBudgetTexts.removeValue(forKey: category)

        var budgets = settings.categoryBudgets
        budgets.removeValue(forKey: category)
        settings.categoryBudgets = budgets
        try? modelContext.save()
    }

    private func createBackup() {
        do {
            backupURL = try GhafBackupService.export(context: modelContext)
        } catch {
            prompt = .message("Could not create backup: \(error.localizedDescription)")
        }
    }

    private func restoreBackup() {
        guard let url = pendingImportURL else { return }
        do {
            try GhafBackupService.restore(from: url, context: modelContext)
            pendingImportURL = nil
            prompt = .message("Backup restored successfully.")
        } catch {
            prompt = .message("Could not restore backup: \(error.localizedDescription)")
        }
    }

    private func deleteAllData() {
        do {
            let transactions = try modelContext.fetch(FetchDescriptor<GhafTransaction>())
            let rules = try modelContext.fetch(FetchDescriptor<MerchantCategoryRule>())
            let settings = try modelContext.fetch(FetchDescriptor<GhafSettings>())

            transactions.forEach { modelContext.delete($0) }
            rules.forEach { modelContext.delete($0) }
            settings.forEach { modelContext.delete($0) }

            try modelContext.save()
        } catch {
            prompt = .message("Could not delete all data.")
        }
    }
}


// MARK: - About Ghaf

struct GhafAboutView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(theme.accent.opacity(0.10))
                        .frame(width: 104, height: 104)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 43, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
                .padding(.top, 24)

                Text(settings.languageCode == "ar" ? "غــــاف" : "Ghaf")
                    .font(GhafTypography.display(34, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)

                VStack(alignment: .leading, spacing: 10) {
                    Text(settings.languageCode == "ar" ? "من مشكلة صغيرة إلى فكرة للجميع" : "A small problem, an idea for everyone")
                        .font(GhafTypography.heading(19, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)

                    Text(settings.languageCode == "ar"
                         ? "بدأ غاف من حاجة شخصية إلى طريقة أبسط لمتابعة المصروفات وتنظيم المال والادخار. صُمم وطُوّر بالاستعانة بالذكاء الاصطناعي بهدف مساعدة الناس على فهم أموالهم وتخطيطها بوضوح، مع تقليل الوقت الذي يقضونه في إدخال العمليات يدوياً."
                         : "Ghaf started with a small personal problem: keeping track of spending, organizing money and planning savings took too much manual effort. Built with the help of AI to support people who want a clearer, simpler way to categorize transactions and plan their savings, while spending less time entering everything by hand.")
                        .font(GhafTypography.body(14, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(19)
                .ghafCard(theme: theme, radius: 20)

                VStack(alignment: .leading, spacing: 7) {
                    Text(settings.languageCode == "ar" ? "المطور" : "Developer")
                        .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                        .foregroundStyle(theme.secondaryText)
                    Text("Abdulkarim Bayassi")
                        .font(GhafTypography.heading(17, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(19)
                .ghafCard(theme: theme, radius: 20)

                Text(settings.languageCode == "ar"
                     ? "جميع الحقوق وحقوق النشر محفوظة لعبدالكريم بياسي."
                     : "All rights and copyrights reserved to Abdulkarim Bayassi.")
                    .font(GhafTypography.body(11, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(settings.languageCode == "ar" ? "عن غــــاف" : "About Ghaf")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: settings.languageCode))
        .environment(\.layoutDirection, settings.languageCode == "ar" ? .rightToLeft : .leftToRight)
    }
}
