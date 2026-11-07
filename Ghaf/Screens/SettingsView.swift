import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum GhafSettingsPrompt: Identifiable {

    case deleteData
    case importBackup
    case message(String)

    var id: String {

        switch self {
        case .deleteData:
            return "delete"
        case .importBackup:
            return "import"
        case .message(let value):
            return "message-\(value)"
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

    private let currencies = [
        "AED", "USD", "EUR", "GBP", "SAR",
        "KWD", "BHD", "OMR", "QAR"
    ]

    private var theme: GhafTheme {

        GhafTheme.resolve(
            name: themeName,
            appearanceMode: appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    var body: some View {

        NavigationStack {

            Form {

                // MARK: Profile

                Section("Profile") {

                    TextField(
                        "Your name",
                        text: $name
                    )

                    Picker(
                        "Main currency",
                        selection: $currency
                    ) {

                        ForEach(currencies, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }

                Section("Language") {
                    Picker("App language", selection: $languageCode) {
                        Text("English").tag("en")
                        Text("العربية").tag("ar")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Bank connection") {
                    NavigationLink {
                        GhafAutomationGuideView(settings: settings)
                    } label: {
                        Label("Set up bank notifications", systemImage: "app.badge.checkmark")
                    }
                }

                // MARK: Appearance

                Section("Appearance") {

                    Picker(
                        "Theme",
                        selection: $themeName
                    ) {

                        Text("Dawn").tag("Dawn")
                        Text("Dusk").tag("Dusk")
                        Text("Oasis").tag("Oasis")
                    }

                    Picker(
                        "Appearance mode",
                        selection: $appearanceMode
                    ) {

                        Text("System").tag("System")
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                    }

                    HStack(spacing: 10) {

                        Circle()
                            .fill(
                                GhafTheme.resolve(
                                    name: themeName,
                                    appearanceMode: "Light",
                                    systemIsDark: false
                                ).accent
                            )
                            .frame(width: 18, height: 18)

                        Text("\(themeName) preview")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.primaryText)
                    }
                    .listRowBackground(theme.surface)
                }

                // MARK: Budget

                Section("Budget") {

                    Picker(
                        "Budget method",
                        selection: $budgetMode
                    ) {

                        Text("Daily limit").tag("Daily")
                        Text("Category budgets").tag("Category")
                    }

                    if budgetMode == "Daily" {

                        TextField(
                            "Monthly income",
                            text: $income
                        )
                        .keyboardType(.decimalPad)

                        TextField(
                            "Fixed monthly commitments",
                            text: $commitments
                        )
                        .keyboardType(.decimalPad)

                        Text("Daily budget = (income − commitments) ÷ days in month.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)

                    } else {

                        Text("Set a monthly budget for each category.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)

                        ForEach(
                            settings.categories,
                            id: \.self
                        ) { category in

                            HStack {

                                Text(category)
                                    .font(.system(size: 13))

                                Spacer()

                                TextField(
                                    "0",
                                    text: budgetBinding(for: category)
                                )
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            }
                        }
                    }
                }

                // MARK: Categories

                Section("Categories") {

                    ForEach(
                        settings.categories,
                        id: \.self
                    ) { category in

                        HStack {

                            Text(category)

                            Spacer()

                            Button(role: .destructive) {

                                removeCategory(category)

                            } label: {

                                Image(systemName: "minus.circle")
                            }
                        }
                    }

                    HStack {

                        TextField(
                            "New category",
                            text: $newCategory
                        )

                        Button("Add") {
                            addCategory()
                        }
                        .disabled(
                            newCategory.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                    }
                }

                // MARK: Saving

                Section {

                    Button("Save settings") {
                        saveSettings()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(theme.accent)
                }

                // MARK: Backup

                Section("Data and backup") {

                    Button {

                        createBackup()

                    } label: {

                        Label(
                            "Create JSON backup",
                            systemImage: "square.and.arrow.up"
                        )
                    }

                    if let backupURL {

                        ShareLink(
                            item: backupURL
                        ) {

                            Label(
                                "Share or save backup",
                                systemImage: "square.and.arrow.up.on.square"
                            )
                        }
                    }

                    Button {

                        showImporter = true

                    } label: {

                        Label(
                            "Import JSON backup",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                }

                // MARK: Delete Data

                Section("Danger zone") {

                    Button(
                        "Delete all Ghaf data",
                        role: .destructive
                    ) {

                        prompt = .deleteData
                    }

                    Text("This permanently deletes your local transactions, settings and learned merchant rules.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(theme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadSettings()
            }
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

                    prompt = .message(
                        "Import failed: \(error.localizedDescription)"
                    )
                }
            }
            .alert(item: $prompt) { selectedPrompt in

                switch selectedPrompt {

                case .deleteData:

                    return Alert(
                        title: Text("Delete all data?"),
                        message: Text(
                            "All transactions, settings and learned merchant rules will be permanently deleted."
                        ),
                        primaryButton: .destructive(
                            Text("Delete everything"),
                            action: deleteAllData
                        ),
                        secondaryButton: .cancel()
                    )

                case .importBackup:

                    return Alert(
                        title: Text("Replace current data?"),
                        message: Text(
                            "Importing this backup replaces all existing Ghaf records on this device."
                        ),
                        primaryButton: .destructive(
                            Text("Replace data"),
                            action: restoreBackup
                        ),
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

    // MARK: - Load

    private func loadSettings() {

        name = settings.userName
        languageCode = settings.languageCode
        currency = settings.currency

        income = GhafFormat.decimal(
            settings.monthlyIncome
        )

        commitments = GhafFormat.decimal(
            settings.fixedCommitments
        )

        themeName = settings.themeName
        appearanceMode = settings.appearanceMode
        budgetMode = settings.budgetMode

        for category in settings.categories {

            let value = settings.categoryBudgets[category]

            categoryBudgetTexts[category] = value.map {
                GhafFormat.decimal($0)
            } ?? ""
        }
    }

    // MARK: - Save

    private func saveSettings() {

        settings.userName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        settings.languageCode = languageCode
        settings.currency = currency

        settings.monthlyIncome = Decimal(
            string: income
        ) ?? 0

        settings.fixedCommitments = Decimal(
            string: commitments
        ) ?? 0

        settings.themeName = themeName
        settings.appearanceMode = appearanceMode
        settings.budgetMode = budgetMode

        var budgets: [String: Decimal] = [:]

        for (category, value) in categoryBudgetTexts {

            if let amount = Decimal(string: value),
               amount > 0 {

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

    // MARK: - Category Management

    private func budgetBinding(
        for category: String
    ) -> Binding<String> {

        Binding(
            get: {
                categoryBudgetTexts[category] ?? ""
            },
            set: {
                categoryBudgetTexts[category] = $0
            }
        )
    }

    private func addCategory() {

        let value = newCategory.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !value.isEmpty else {
            return
        }

        var categories = settings.categories

        guard !categories.contains(
            where: {
                $0.caseInsensitiveCompare(value) == .orderedSame
            }
        ) else {
            newCategory = ""
            return
        }

        categories.append(value)

        settings.categories = categories

        newCategory = ""

        try? modelContext.save()
    }

    private func removeCategory(
        _ category: String
    ) {

        var categories = settings.categories

        // Retain at least one category.
        guard categories.count > 1 else {
            return
        }

        categories.removeAll {
            $0 == category
        }

        settings.categories = categories

        categoryBudgetTexts.removeValue(
            forKey: category
        )

        var budgets = settings.categoryBudgets
        budgets.removeValue(forKey: category)

        settings.categoryBudgets = budgets

        try? modelContext.save()
    }

    // MARK: - Backup

    private func createBackup() {

        do {

            backupURL = try GhafBackupService.export(
                context: modelContext
            )

        } catch {

            prompt = .message(
                "Could not create backup: \(error.localizedDescription)"
            )
        }
    }

    private func restoreBackup() {

        guard let url = pendingImportURL else {
            return
        }

        do {

            try GhafBackupService.restore(
                from: url,
                context: modelContext
            )

            pendingImportURL = nil

            prompt = .message(
                "Backup restored successfully."
            )

        } catch {

            prompt = .message(
                "Could not restore backup: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Delete All

    private func deleteAllData() {

        do {

            let transactions = try modelContext.fetch(
                FetchDescriptor<GhafTransaction>()
            )

            let rules = try modelContext.fetch(
                FetchDescriptor<MerchantCategoryRule>()
            )

            let settings = try modelContext.fetch(
                FetchDescriptor<GhafSettings>()
            )

            transactions.forEach {
                modelContext.delete($0)
            }

            rules.forEach {
                modelContext.delete($0)
            }

            settings.forEach {
                modelContext.delete($0)
            }

            try modelContext.save()

        } catch {

            prompt = .message(
                "Could not delete all data."
            )
        }
    }
}
