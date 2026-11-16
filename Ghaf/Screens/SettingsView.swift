import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum GhafSettingsPrompt: Identifiable {
    case deleteData
    case importBackup
    case importExpend
    case message(String)

    var id: String {
        switch self {
        case .deleteData: return "delete"
        case .importBackup: return "import"
        case .importExpend: return "import-expend"
        case .message(let value): return "message-\(value)"
        }
    }
}

struct GhafSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]

    let settings: GhafSettings

    @State private var name = ""
    @State private var languageCode = "en"
    @State private var currency = "AED"
    @State private var income = ""
    @State private var commitments = ""
    @State private var themeName = "Abu Dhabi"
    @State private var appearanceMode = "System"
    @State private var budgetMode = "Daily"
    @State private var newCategory = ""
    @State private var categoryBudgetTexts: [String: String] = [:]
    @State private var backupURL: URL?
    @State private var pendingImportURL: URL?
    @State private var showImporter = false
    @State private var prompt: GhafSettingsPrompt?
    @State private var hasLoadedSettings = false

    private let currencies = ["AED", "SAR", "KWD", "BHD", "OMR", "QAR"]

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
                VStack(spacing: GhafMetrics.sectionSpacing) {
                    profileHeader

                    menuGroup(ar ? "المال" : "Money") {
                        menuRow(ar ? "الحسابات والمحافظ" : "Accounts & wallets", icon: "wallet.pass.fill") { GhafAccountsView(settings: settings) }
                        menuRow(ar ? "الميزانية والفئات" : "Budget & categories", icon: "chart.pie.fill") { subpage(ar ? "الميزانية" : "Budget") { budgetCard; categoriesCard } }
                        menuRow(ar ? "دورة الراتب" : "Salary cycle", icon: "calendar.badge.clock") { GhafSalarySettingsView(settings: settings) }
                        menuRow(ar ? "ربط البنك تلقائياً" : "Bank automation", icon: "bolt.fill") { GhafAutomationGuideView(settings: settings) }
                    }

                    menuGroup("Ghaf AI") {
                        menuRow(ar ? "ما تعلّمه غاف" : "What Ghaf learned", icon: "brain.head.profile") { GhafLearnedRulesView(settings: settings) }
                    }

                    menuGroup(ar ? "التطبيق" : "App") {
                        menuRow(ar ? "المظهر" : "Appearance", icon: "paintpalette.fill") { subpage(ar ? "المظهر" : "Appearance") { appearanceCard } }
                        menuRow(ar ? "الأمان والخصوصية" : "Security & privacy", icon: "lock.fill") { subpage(ar ? "الأمان" : "Security") { securityCard } }
                    }

                    menuGroup(ar ? "البيانات" : "Data") {
                        menuRow(ar ? "Google Drive والنسخ الاحتياطي" : "Google Drive & backup", icon: "externaldrive.fill.badge.icloud") { subpage(ar ? "النسخ الاحتياطي" : "Backup") { driveCard; backupCard } }
                        menuRow(ar ? "عن غاف" : "About Ghaf", icon: "leaf.fill") { GhafAboutView(settings: settings) }
                    }

                    Button(role: .destructive) { prompt = .deleteData } label: {
                        Label(ar ? "حذف جميع بيانات غاف" : "Delete all Ghaf data", systemImage: "trash")
                            .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                            .foregroundStyle(theme.over)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(theme.over.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.ghafPress)

                    Text(languageCode == "ar" ? "تبقى بياناتك على هذا الـ iPhone. لا يتصل غاف بخادم مالي." : "Your data stays on this iPhone. Ghaf does not connect to a financial server.")
                        .font(GhafTypography.body(12, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, GhafMetrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .tint(theme.accent)
        }  // Importer and alerts sit on the stack so they present from pushed pages too.
            .onAppear(perform: loadSettings)
            .onChange(of: languageCode) { _, _ in persistSettings() }
            .onChange(of: name) { _, _ in persistSettings() }
            .onChange(of: currency) { _, _ in persistSettings() }
            .onChange(of: income) { _, _ in persistSettings() }
            .onChange(of: commitments) { _, _ in persistSettings() }
            .onChange(of: themeName) { _, _ in persistSettings() }
            .onChange(of: appearanceMode) { _, _ in persistSettings() }
            .onChange(of: budgetMode) { _, _ in persistSettings() }
            .onChange(of: categoryBudgetTexts) { _, _ in persistSettings() }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { @MainActor in
                        do {
                            // Coordinated copy downloads iCloud files and keeps working after the picker's access ends.
                            let local = try Self.localCopy(of: url)
                            // An alert set while the picker is still closing is dropped on device; wait for it.
                            try? await Task.sleep(for: .milliseconds(450))
                            pendingImportURL = local
                            prompt = GhafExpendImportService.canImport(local) ? .importExpend : .importBackup
                        } catch {
                            try? await Task.sleep(for: .milliseconds(450))
                            prompt = .message(languageCode == "ar"
                                ? "تعذر قراءة الملف. إذا كان في iCloud Drive فانتظر حتى يكتمل تنزيله ثم حاول مرة أخرى."
                                : "Couldn't read that file. If it's in iCloud Drive, let it finish downloading and try again.")
                        }
                    }
                case .failure:
                    prompt = .message(languageCode == "ar" ? "تعذر استيراد النسخة الاحتياطية." : "Could not import the backup.")
                }
            }
            .alert(item: $prompt) { selectedPrompt in
                switch selectedPrompt {
                case .deleteData:
                    return Alert(
                        title: Text(languageCode == "ar" ? "حذف جميع البيانات؟" : "Delete all data?"),
                        message: Text(languageCode == "ar" ? "سيتم حذف جميع العمليات والإعدادات وقواعد تصنيف التجار المحفوظة نهائياً." : "All transactions, settings and learned merchant rules will be permanently deleted."),
                        primaryButton: .destructive(Text(languageCode == "ar" ? "حذف كل شيء" : "Delete everything"), action: deleteAllData),
                        secondaryButton: .cancel()
                    )
                case .importBackup:
                    return Alert(
                        title: Text(languageCode == "ar" ? "استعادة نسخة غاف؟" : "Restore Ghaf backup?"),
                        message: Text(languageCode == "ar"
                            ? "سيؤدي ذلك إلى استبدال السجلات المالية والإعدادات الحالية بالنسخة الاحتياطية."
                            : "This replaces the current Ghaf records and settings with the selected Ghaf backup."),
                        primaryButton: .destructive(Text(languageCode == "ar" ? "استعادة النسخة" : "Restore backup"), action: restoreBackup),
                        secondaryButton: .cancel()
                    )
                case .importExpend:
                    return Alert(
                        title: Text(languageCode == "ar" ? "استيراد بيانات Expend؟" : "Import Expend data?"),
                        message: Text(languageCode == "ar"
                            ? "سيتم استبدال بيانات غاف الحالية بمحافظ Expend وعملياته. سيتم التحقق من أرصدة المحافظ قبل اعتماد الاستيراد. تُضاف المدفوعات المتكررة كاشتراكات، ولا تُنقل الميزانيات حالياً."
                            : "This replaces current Ghaf records with Expend wallets and transactions. Wallet balances are checked before the import is committed. Recurring payments become subscriptions; budgets are not imported yet."),
                        primaryButton: .destructive(Text(languageCode == "ar" ? "استيراد واستبدال" : "Import and replace"), action: restoreBackup),
                        secondaryButton: .cancel()
                    )
                case .message(let message):
                    return Alert(
                        title: Text("Ghaf"),
                        message: Text(message),
                        dismissButton: .default(Text(languageCode == "ar" ? "حسناً" : "OK"))
                    )
                }
            }
    }

    private var ar: Bool { languageCode == "ar" }

    // MARK: Simple More layout

    private var initials: String {
        let value = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
        return value.isEmpty ? (ar ? "غ" : "G") : value.uppercased()
    }

    private var profileHeader: some View {
        NavigationLink {
            subpage(ar ? "الملف الشخصي" : "Profile") { profilePage }
        } label: {
            VStack(spacing: 10) {
                Text(initials)
                    .font(GhafTypography.display(30, languageCode: languageCode))
                    .foregroundStyle(theme.accentContrast)
                    .frame(width: 88, height: 88)
                    .background(theme.accent.gradient, in: Circle())
                    .shadow(color: theme.accent.opacity(0.35), radius: 14, y: 6)
                Text(name.isEmpty ? (ar ? "أضف اسمك" : "Add your name") : name)
                    .font(GhafTypography.display(26, languageCode: languageCode))
                    .foregroundStyle(theme.primaryText)
                HStack(spacing: 6) {
                    Text(ar ? "عرض الملف الشخصي" : "View profile")
                    Image(systemName: "chevron.forward").font(.system(size: 10, weight: .heavy))
                }
                .font(GhafTypography.body(14, languageCode: languageCode, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 16).frame(height: 36)
                .background(theme.surface, in: Capsule())
                .shadow(color: theme.shadow, radius: 8, y: 3)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .buttonStyle(.ghafPress)
    }

    private var profilePage: some View {
        VStack(spacing: 16) {
            profileCard
            languageCard
            VStack(spacing: 6) {
                Label(ar ? "تسجيل الدخول عبر Apple" : "Sign in with Apple", systemImage: "apple.logo")
                    .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
                Text(ar ? "قريباً — يتطلب حساب مطوّر Apple مدفوع." : "Coming soon. It needs a paid Apple Developer account.")
                    .font(GhafTypography.body(12, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .ghafCard(theme: theme, radius: 20)
        }
    }

    private func menuGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(GhafTypography.body(14, languageCode: languageCode, weight: .bold))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 8)
            VStack(spacing: 0) { content() }
                .padding(.vertical, 4)
                .ghafCard(theme: theme)
        }
    }

    private func menuRow<Destination: View>(_ title: String, icon: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            GhafListRow(icon: icon, tint: theme.accent, title: title, theme: theme,
                        languageCode: languageCode, chevron: true)
                .padding(.horizontal, 16)
        }
        .buttonStyle(.ghafPress)
    }

    private func subpage<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 16) { content() }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(theme.accent)
    }

    @StateObject private var drive = GhafGoogleDrive.shared

    private var driveCard: some View {
        settingsCard("Google Drive", subtitle: ar ? "نسخ احتياطي إلى حسابك في Google Drive" : "Back up to your own Google Drive") {
            if !drive.isConfigured {
                Text(ar ? "ربط Google غير مفعّل في هذه النسخة بعد. يحتاج المطوّر إلى إضافة معرّف Google OAuth."
                        : "Google sign-in isn't switched on in this build yet. The developer needs to add a Google OAuth client ID.")
                    .font(GhafTypography.body(13, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            } else if let email = drive.email {
                Label(email, systemImage: "checkmark.seal.fill")
                    .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.credit)
                Button { driveBackup() } label: {
                    settingsActionRow(ar ? "نسخ احتياطي الآن" : "Back up now", detail: ar ? "رفع نسخة جديدة إلى Drive" : "Upload a fresh copy to Drive", icon: "icloud.and.arrow.up")
                }
                .buttonStyle(.ghafPress).disabled(drive.isBusy)
                Button { driveRestore() } label: {
                    settingsActionRow(ar ? "استعادة آخر نسخة" : "Restore latest backup", detail: ar ? "تنزيل آخر نسخة من Drive" : "Download the newest copy from Drive", icon: "icloud.and.arrow.down")
                }
                .buttonStyle(.ghafPress).disabled(drive.isBusy)
                Button(ar ? "قطع الاتصال" : "Disconnect", role: .destructive) { drive.signOut() }
                    .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
            } else {
                Button { Task { await driveRun { try await drive.signIn() } } } label: {
                    Label(ar ? "تسجيل الدخول عبر Google" : "Sign in with Google", systemImage: "person.crop.circle.badge.plus")
                        .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(drive.isBusy)
            }
            if drive.isBusy { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    private func driveRun(_ work: () async throws -> Void) async {
        do { try await work() } catch GhafGoogleDrive.DriveError.cancelled {
        } catch {
            prompt = .message(error.localizedDescription)
        }
    }

    private func driveBackup() {
        Task {
            await driveRun {
                let url = try GhafBackupService.export(context: modelContext)
                try await drive.upload(fileAt: url)
                prompt = .message(ar ? "تم رفع النسخة الاحتياطية إلى Google Drive." : "Backup uploaded to Google Drive.")
            }
        }
    }

    private func driveRestore() {
        Task {
            await driveRun {
                pendingImportURL = try await drive.downloadLatest()
                prompt = .importBackup
            }
        }
    }

    private var profileCard: some View {
        let activeAccountCount = accounts.filter { !$0.isArchived }.count
        return VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(initials)
                    .font(GhafTypography.display(36, languageCode: languageCode))
                    .foregroundStyle(theme.accentContrast)
                    .frame(width: 96, height: 96)
                    .background(theme.accent, in: Circle())
                    .overlay(Circle().stroke(theme.accent.opacity(0.35), lineWidth: 6).padding(-6))
                Text(name.isEmpty ? (ar ? "مرحباً بك في غاف" : "Welcome to Ghaf") : name)
                    .font(GhafTypography.display(26, languageCode: languageCode))
                    .foregroundStyle(theme.primaryText)
                Text(ar ? "على هذا الـ iPhone فقط" : "Stored only on this iPhone")
                    .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                profileMetric(icon: "wallet.pass.fill", value: "\(activeAccountCount)", title: ar ? "الحسابات" : "ACCOUNTS")
                profileMetric(icon: "arrow.left.arrow.right", value: "\(transactions.count)", title: ar ? "العمليات" : "TRANSACTIONS")
            }

            settingsCard(ar ? "بياناتك" : "Your details", subtitle: ar ? "تُستخدم لتخصيص غاف" : "Used to personalise Ghaf") {
                settingsLabel(ar ? "اسمك" : "Your name")
                settingsField(ar ? "الاسم" : "Name", text: $name)
                HStack {
                    settingsLabel(ar ? "العملة الرئيسية" : "Main currency")
                    Spacer()
                    GhafCurrencyPicker(selection: $currency, currencies: currencies, languageCode: languageCode, tint: theme.accent)
                }
            }
        }
    }

    private func profileMetric(icon: String, value: String, title: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 30, height: 30)
                .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(GhafTypography.number(17, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text(title)
                    .font(GhafTypography.body(8, languageCode: languageCode, weight: .bold))
                    .tracking(languageCode == "ar" ? 0 : 0.8)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var languageCard: some View {
        settingsCard(languageCode == "ar" ? "اللغة" : "Language", subtitle: languageCode == "ar" ? "لغة الواجهة في جميع أجزاء غاف" : "The language used throughout Ghaf") {
            Picker(languageCode == "ar" ? "لغة التطبيق" : "App language", selection: $languageCode) {
                Text("English").tag("en")
                Text("العربية").tag("ar")
            }
            .pickerStyle(.segmented)
        }
    }

    private var appearanceCard: some View {
        settingsCard(languageCode == "ar" ? "المظهر" : "Appearance", subtitle: languageCode == "ar" ? "أنماط نظيفة بوضع فاتح وداكن" : "Clean themes, each in light and dark") {
            settingsLabel(languageCode == "ar" ? "النمط" : "Theme")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(GhafTheme.themeNames, id: \.self) { option in
                    let preview = GhafTheme.resolve(name: option, appearanceMode: appearanceMode,
                                                    systemIsDark: theme.isDark)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { themeName = option }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(preview.accent).frame(width: 34, height: 34)
                                if themeName == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .heavy))
                                        .foregroundStyle(preview.accentContrast)
                                }
                            }
                            Text(themeTitle(option))
                                .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 78)
                        .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(themeName == option ? theme.accent : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.ghafPress)
                    .sensoryFeedback(.selection, trigger: themeName)
                    .accessibilityLabel(themeTitle(option))
                    .accessibilityAddTraits(themeName == option ? .isSelected : [])
                }
            }

            settingsLabel(languageCode == "ar" ? "وضع المظهر" : "Appearance mode")
            Picker(languageCode == "ar" ? "وضع المظهر" : "Appearance mode", selection: $appearanceMode) {
                Text(languageCode == "ar" ? "حسب الجهاز" : "System").tag("System")
                Text(languageCode == "ar" ? "فاتح" : "Light").tag("Light")
                Text(languageCode == "ar" ? "داكن" : "Dark").tag("Dark")
            }
            .pickerStyle(.segmented)

            HStack(spacing: 9) {
                Circle().fill(theme.accent).frame(width: 16, height: 16)
                Text("\(themeName) · " + (languageCode == "ar" ? "معاينة" : "Preview"))
                    .font(GhafTypography.body(13, languageCode: languageCode, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                RoundedRectangle(cornerRadius: 6).fill(theme.accent).frame(width: 24, height: 16)
                RoundedRectangle(cornerRadius: 6).fill(theme.comfortable).frame(width: 24, height: 16)
            }
            .padding(.top, 4)
        }
    }

    private func themeTitle(_ name: String) -> String {
        guard ar else { return name }
        return ["Graphite": "جرافيت", "Abu Dhabi": "أبوظبي", "Dubai": "دبي", "Sharjah": "الشارقة", "Ajman": "عجمان",
                "Umm Al Quwain": "أم القيوين", "Ras Al Khaimah": "رأس الخيمة", "Fujairah": "الفجيرة",
                "Dawn": "الفجر", "Dusk": "الغسق", "Oasis": "الواحة"][name] ?? name
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
        settingsCard(languageCode == "ar" ? "الميزانية" : "Budget", subtitle: languageCode == "ar" ? "حدد طريقة حساب المبلغ المتاح" : "Choose how your available money is measured") {
            Picker(languageCode == "ar" ? "طريقة الميزانية" : "Budget method", selection: $budgetMode) {
                Text(languageCode == "ar" ? "حد يومي" : "Daily limit").tag("Daily")
                Text(languageCode == "ar" ? "ميزانيات الفئات" : "Category budgets").tag("Category")
            }
            .pickerStyle(.segmented)

            if budgetMode == "Daily" {
                settingsLabel(languageCode == "ar" ? "الدخل الشهري" : "Monthly income")
                settingsField(languageCode == "ar" ? "مثال: ٥٠٠٠" : "e.g. 5000", text: $income, numeric: true)

                settingsLabel(languageCode == "ar" ? "الالتزامات الشهرية الثابتة" : "Fixed monthly commitments")
                settingsField(languageCode == "ar" ? "مثال: ١٥٠٠" : "e.g. 1500", text: $commitments, numeric: true)

                Text(languageCode == "ar" ? "الميزانية اليومية = (الدخل − الالتزامات) ÷ عدد أيام الشهر." : "Daily budget = (income − commitments) ÷ days in month.")
                    .font(GhafTypography.body(12, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            } else {
                Text(languageCode == "ar" ? "حدد سقفاً شهرياً للإنفاق في كل فئة." : "Set a monthly spending limit for each category.")
                    .font(GhafTypography.body(13, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)

                ForEach(settings.categories, id: \.self) { category in
                    HStack(spacing: 12) {
                        Text(GhafLocalization.category(category, languageCode: languageCode))
                            .font(GhafTypography.body(14, languageCode: languageCode, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        TextField(languageCode == "ar" ? "٠" : "0", text: budgetBinding(for: category))
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
        settingsCard(languageCode == "ar" ? "الفئات" : "Categories", subtitle: languageCode == "ar" ? "خصص طريقة تصنيف مصروفاتك" : "Teach Ghaf how you group your spending") {
            ForEach(settings.categories, id: \.self) { category in
                HStack {
                    GhafCategoryIcon(category: category, tint: theme.accent)
                        .scaleEffect(0.7)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GhafLocalization.category(category, languageCode: languageCode))
                            .font(GhafTypography.body(14, languageCode: languageCode, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                        let subs = settings.subcategories(of: category)
                        if !subs.isEmpty {
                            Text(subs.joined(separator: " · "))
                                .font(GhafTypography.body(11, languageCode: languageCode))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(2)
                        }
                    }
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
                TextField(languageCode == "ar" ? "فئة جديدة" : "New category", text: $newCategory)
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
        settingsCard(languageCode == "ar" ? "البيانات والنسخ الاحتياطي" : "Data and backup", subtitle: languageCode == "ar" ? "تصدير نسخة من بياناتك أو استعادتها" : "Move or keep a copy of your local records") {
            Button(action: createBackup) {
                settingsActionRow(languageCode == "ar" ? "إنشاء نسخة احتياطية" : "Create JSON backup", detail: languageCode == "ar" ? "تصدير العمليات والإعدادات وقواعد التجار" : "Export transactions, settings and learned merchants", icon: "square.and.arrow.up")
            }
            .buttonStyle(.ghafPress)

            if let backupURL {
                ShareLink(item: backupURL) {
                    settingsActionRow(languageCode == "ar" ? "مشاركة النسخة أو حفظها" : "Share or save backup", detail: languageCode == "ar" ? "احفظها في iCloud Drive أو Google Drive عبر تطبيق الملفات" : "Save to iCloud Drive or Google Drive through the Files app", icon: "square.and.arrow.up.on.square")
                }
                .buttonStyle(.ghafPress)
            }

            Button { showImporter = true } label: {
                settingsActionRow(languageCode == "ar" ? "استيراد نسخة احتياطية" : "Import JSON backup", detail: languageCode == "ar" ? "استبدال البيانات المحلية بنسخة احتياطية" : "Replace the current local data with a backup", icon: "square.and.arrow.down")
            }
            .buttonStyle(.ghafPress)

            Text(languageCode == "ar"
                 ? "تنبيه: نسخة JSON الحالية غير مشفّرة، وتحتوي على بياناتك المالية. احفظها في مكان خاص."
                 : "Note: the current JSON backup is not encrypted and contains financial records. Store it somewhere private.")
                .font(GhafTypography.body(10, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        hasLoadedSettings = true
    }

    private func persistSettings() {
        guard hasLoadedSettings else { return }
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
        } catch {
            prompt = .message(languageCode == "ar" ? "تعذر حفظ التغييرات." : "Could not save your changes.")
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
            prompt = .message(languageCode == "ar" ? "تعذر إنشاء النسخة الاحتياطية." : "Could not create the backup.")
        }
    }

    /// Copies a picked file into the app's temporary folder through a file coordinator.
    private static func localCopy(of url: URL) throws -> URL {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString)-\(url.lastPathComponent)")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            do { try FileManager.default.copyItem(at: readable, to: destination) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        return destination
    }

    private func restoreBackup() {
        guard let url = pendingImportURL else { return }
        do {
            if GhafExpendImportService.canImport(url) {
                let result = try GhafExpendImportService.importFile(from: url, context: modelContext)
                pendingImportURL = nil

                let walletCount = GhafLocalization.count(
                    result.accountsImported,
                    singular: "حساب واحد",
                    dual: "حسابان",
                    plural: "حسابات",
                    afterTen: "حساباً",
                    languageCode: languageCode
                )
                let entryCount = GhafLocalization.count(
                    result.transactionsImported,
                    singular: "قيد واحد",
                    dual: "قيدان",
                    plural: "قيود",
                    afterTen: "قيداً",
                    languageCode: languageCode
                )
                let recurringCount = GhafLocalization.count(
                    result.recurringRulesNotImported,
                    singular: "جدولة متكررة واحدة",
                    dual: "جدولتان متكررتان",
                    plural: "جداول متكررة",
                    afterTen: "جدولة متكررة",
                    languageCode: languageCode
                )
                let budgetCount = GhafLocalization.count(
                    result.budgetsNotImported,
                    singular: "ميزانية واحدة",
                    dual: "ميزانيتان",
                    plural: "ميزانيات",
                    afterTen: "ميزانية",
                    languageCode: languageCode
                )

                var message = languageCode == "ar"
                    ? "تم استيراد \(walletCount) و\(entryCount) من Expend. تمت مطابقة الأرصدة مع الملف المصدر."
                    : "Imported \(result.accountsImported) wallets and \(result.transactionsImported) ledger entries from Expend. Wallet balances match the source export."

                if result.budgetsNotImported > 0 {
                    message += languageCode == "ar"
                        ? " لم يتم نقل \(budgetCount) لأن غاف لا يدعم استيراد ميزانيات Expend حالياً."
                        : " \(result.budgetsNotImported) budgets were not imported because Ghaf does not yet support Expend budget structures."
                }
                if result.recurringRulesNotImported > 0 {
                    message += languageCode == "ar"
                        ? " لم يتم نقل \(recurringCount) لأن غاف لا يدعم الجداول المتكررة حالياً."
                        : " \(result.recurringRulesNotImported) recurring schedules were not imported because Ghaf does not yet support recurring schedules."
                }
                if result.skippedTransactions > 0 {
                    message += languageCode == "ar"
                        ? " تم تجاوز \(result.skippedTransactions) من السجلات غير الصالحة أو المحذوفة."
                        : " \(result.skippedTransactions) deleted or invalid source records were skipped."
                }
                prompt = .message(message)
            } else {
                try GhafBackupService.restore(from: url, context: modelContext)
                pendingImportURL = nil
                prompt = .message(languageCode == "ar" ? "تمت استعادة نسخة غاف الاحتياطية بنجاح." : "Ghaf backup restored successfully.")
            }
        } catch {
            prompt = .message(languageCode == "ar"
                ? "تعذر استيراد الملف. لم يتم اعتماد الاستيراد. التفاصيل: \(error.localizedDescription)"
                : "Could not import the file. Details: \(error.localizedDescription)")
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
            prompt = .message(languageCode == "ar" ? "تعذر حذف جميع البيانات." : "Could not delete all data.")
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
                Image("GhafBrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .padding(.top, 24)

                Text(settings.languageCode == "ar" ? "غــــاف" : "Ghaf")
                    .font(GhafTypography.display(34, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)

                VStack(alignment: .leading, spacing: 10) {
                    Text(settings.languageCode == "ar" ? "من مشكلة صغيرة إلى فكرة للجميع" : "A small problem, an idea for everyone")
                        .font(GhafTypography.heading(19, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)

                    Text(settings.languageCode == "ar"
                         ? "بدأ غاف من حاجة شخصية إلى طريقة أبسط لمتابعة المصروفات وتنظيم المال والادخار. صُمم وطُوّر بالكامل بالذكاء الاصطناعي لمساعدة الناس على فهم أموالهم وتصنيف عملياتهم وتخطيط مدخراتهم بوضوح، مع تقليل الوقت الذي يقضونه في إدخال العمليات يدوياً."
                         : "Ghaf started with a small personal problem: keeping track of spending, organizing money and planning savings took too much manual effort. Designed and built entirely with AI to support people who want a clearer, simpler way to categorize transactions and plan their savings, while spending less time entering everything by hand.")
                        .font(GhafTypography.body(14, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(19)
                .ghafCard(theme: theme, radius: 20)

                VStack(alignment: .leading, spacing: 7) {
                    NavigationLink {
                        GhafPrivacyPolicyView(settings: settings)
                    } label: {
                        Label(
                            settings.languageCode == "ar" ? "سياسة الخصوصية" : "Privacy policy",
                            systemImage: "hand.raised"
                        )
                        .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .ghafCard(theme: theme, radius: 18)
                    }

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
        .ghafBackground(theme: theme)
        .navigationTitle(settings.languageCode == "ar" ? "عن غــــاف" : "About Ghaf")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: settings.languageCode))
        .environment(\.layoutDirection, settings.languageCode == "ar" ? .rightToLeft : .leftToRight)
    }
}
