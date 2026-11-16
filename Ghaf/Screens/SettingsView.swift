import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

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
    @State private var pickedImportURL: URL?
    /// Weekly totals everywhere follow this; the region's first weekday until the user picks one.
    @AppStorage(GhafCalendar.weekStartKey) private var weekStart = Calendar.current.firstWeekday
    @State private var photoItem: PhotosPickerItem?
    @State private var hasPhoto = GhafProfilePhoto.load() != nil
    @State private var prompt: GhafSettingsPrompt?
    @State private var hasLoadedSettings = false
    @State private var categoryToRemove: String?

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
                        menuRow(ar ? "الميزانية والفئات" : "Budget & categories", icon: "chart.pie.fill") { subpage(ar ? "الميزانية والفئات" : "Budget & categories") { categoriesCard; budgetCard } }
                        menuRow(ar ? "دورة الراتب" : "Salary cycle", icon: "calendar.badge.clock") { GhafSalarySettingsView(settings: settings) }
                        menuRow(ar ? "ربط البنك تلقائياً" : "Bank automation", icon: "bolt.fill") { GhafAutomationGuideView(settings: settings) }
                    }

                    menuGroup("Ghaf AI") {
                        menuRow(ar ? "ما تعلّمه غاف" : "What Ghaf learned", icon: "brain.head.profile") { GhafLearnedRulesView(settings: settings) }
                    }

                    menuGroup(ar ? "التطبيق" : "App") {
                        menuRow(ar ? "التخصيص" : "Customization", icon: "paintpalette.fill") {
                            subpage(ar ? "التخصيص" : "Customization") { languageCard; currencyCard; appearanceCard }
                        }
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
            .ghafKeyboardDone()
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
            // UIKit's picker in copy mode: iOS downloads iCloud files and hands over a local copy, and the
            // confirm alert waits for the sheet to close. Any data file is selectable; contents are validated.
            // iOS may report the pick before or after the sheet finishes closing; ask in whichever comes last.
            .sheet(isPresented: $showImporter, onDismiss: askToImportPickedFile) {
                GhafDocumentPicker { url in
                    pickedImportURL = url
                    if !showImporter { askToImportPickedFile() }
                }
                .ignoresSafeArea()
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
                GhafAvatar(initials: initials, theme: theme, languageCode: languageCode)
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
            VStack(spacing: 6) {
                Label(ar ? "تسجيل الدخول عبر Apple أو Google" : "Sign in with Apple or Google", systemImage: "person.badge.key.fill")
                    .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
                Text(ar ? "قريباً مع المزامنة بين أجهزتك. حتى ذلك الحين تبقى بياناتك على هذا الـ iPhone فقط."
                        : "Coming with sync across your devices. Until then, your data stays on this iPhone only.")
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
        .ghafKeyboardDone()
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
                PhotosPicker(selection: $photoItem, matching: .images) {
                    GhafAvatar(initials: initials, theme: theme, languageCode: languageCode, size: 104)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(theme.accentContrast)
                                .frame(width: 32, height: 32)
                                .background(theme.accent, in: Circle())
                                .overlay(Circle().stroke(theme.surface, lineWidth: 3))
                        }
                }
                .buttonStyle(.ghafPress)
                .accessibilityLabel(ar ? "اختيار صورة الملف الشخصي" : "Choose profile photo")
                .onChange(of: photoItem) { _, item in
                    Task {
                        guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                        do { try GhafProfilePhoto.save(image); hasPhoto = true }
                        catch { prompt = .message(ar ? "تعذر حفظ الصورة." : "Couldn't save the photo.") }
                    }
                }
                if hasPhoto {
                    Button(ar ? "إزالة الصورة" : "Remove photo", role: .destructive) {
                        GhafProfilePhoto.remove(); hasPhoto = false; photoItem = nil
                    }
                    .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                }
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

    private var currencyCard: some View {
        settingsCard(ar ? "العملة الرئيسية" : "Main currency",
                     subtitle: ar ? "للإجماليات والميزانية. لا تتغير عملة عملياتك السابقة." : "Used for totals and budgets. Past transactions keep their own currency.") {
            HStack {
                settingsLabel(ar ? "العملة" : "Currency")
                Spacer()
                GhafCurrencyPicker(selection: $currency, currencies: currencies, languageCode: languageCode, tint: theme.accent)
            }
        }
    }

    private var languageCard: some View {
        settingsCard(languageCode == "ar" ? "اللغة" : "Language", subtitle: languageCode == "ar" ? "لغة الواجهة في جميع أجزاء غاف" : "The language used throughout Ghaf") {
            Picker(languageCode == "ar" ? "لغة التطبيق" : "App language", selection: $languageCode) {
                Text("English").tag("en")
                Text("العربية").tag("ar")
            }
            .pickerStyle(.segmented)

            settingsLabel(languageCode == "ar" ? "بداية الأسبوع" : "Week starts on")
            Picker(languageCode == "ar" ? "بداية الأسبوع" : "Week starts on", selection: $weekStart) {
                Text(languageCode == "ar" ? "السبت" : "Saturday").tag(7)
                Text(languageCode == "ar" ? "الأحد" : "Sunday").tag(1)
                Text(languageCode == "ar" ? "الإثنين" : "Monday").tag(2)
            }
            .pickerStyle(.segmented)
            Text(languageCode == "ar" ? "يُستخدم لـ«هذا الأسبوع» في غاف AI والرسوم. الرئيسية تعرض آخر ٧ أيام."
                                      : "Used for \"this week\" in Ghaf AI and charts. Home shows the last 7 days.")
                .font(GhafTypography.body(12, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var appearanceCard: some View {
        settingsCard(languageCode == "ar" ? "المظهر" : "Appearance", subtitle: languageCode == "ar" ? "سبع مدن، كلٌّ بوضع فاتح وداكن" : "Seven cities, each in light and dark") {
            settingsLabel(languageCode == "ar" ? "النمط" : "Theme")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(GhafTheme.themeNames, id: \.self) { option in
                    let preview = GhafTheme.resolve(name: option, appearanceMode: appearanceMode,
                                                    systemIsDark: theme.isDark)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { themeName = option }
                    } label: {
                        VStack(spacing: 6) {
                            // The city's own skyline, in its colours; Graphite keeps a plain swatch.
                            ZStack(alignment: .topTrailing) {
                                if option == "Graphite" {
                                    Circle().fill(LinearGradient(colors: [preview.accent, preview.glow],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 34, height: 34)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                } else {
                                    GhafCitySkyline(city: option)
                                        .fill(LinearGradient(colors: [preview.accent, preview.glow], startPoint: .top, endPoint: .bottom))
                                        .frame(height: 44)
                                }
                                if themeName == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(preview.accent)
                                        .background(Circle().fill(preview.background))
                                }
                            }
                            Text(themeTitle(option))
                                .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                                .foregroundStyle(preview.primaryText)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 8)
                        .frame(maxWidth: .infinity, minHeight: 86)
                        .background(preview.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                Text(themeTitle(themeName) + " · " + {
                    let city = GhafTheme.cities[GhafTheme.canonical(themeName)]
                    return (languageCode == "ar" ? city?.ar : city?.en) ?? ""
                }())
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
        let spent = categorySpendThisMonth
        return settingsCard(ar ? "الفئات" : "Categories",
                            subtitle: ar ? "اضغط مطولاً على فئة لحذفها" : "Long-press a category to remove it") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(settings.categories, id: \.self) { category in
                    categoryTile(category, spent: spent[category] ?? 0)
                }
            }
            HStack(spacing: 8) {
                TextField(ar ? "فئة جديدة" : "New category", text: $newCategory)
                    .font(GhafTypography.body(15, languageCode: languageCode))
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(theme.background, in: Capsule())
                    .onSubmit(addCategory)
                Button(action: addCategory) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.accentContrast)
                        .frame(width: 48, height: 48)
                        .background(theme.accent, in: Circle())
                }
                .accessibilityLabel(ar ? "إضافة فئة" : "Add category")
                .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
        .confirmationDialog(ar ? "حذف هذه الفئة؟" : "Remove this category?",
                            isPresented: Binding(get: { categoryToRemove != nil }, set: { if !$0 { categoryToRemove = nil } }),
                            titleVisibility: .visible) {
            Button(ar ? "حذف" : "Remove", role: .destructive) {
                if let category = categoryToRemove { withAnimation(.snappy) { removeCategory(category) } }
            }
        } message: {
            Text(ar ? "تبقى العمليات المسجلة بها كما هي." : "Transactions already in it keep their category.")
        }
    }

    /// Spending per category this calendar month, in the main currency only.
    private var categorySpendThisMonth: [String: Decimal] {
        guard let month = Calendar.current.dateInterval(of: .month, for: .now) else { return [:] }
        var totals: [String: Decimal] = [:]
        for transaction in transactions where month.contains(transaction.date)
            && transaction.currency == currency && transaction.isSpendingOrIncome && transaction.isExpense {
            totals[transaction.category, default: 0] += transaction.spendingAmount
        }
        return totals
    }

    private func categoryTile(_ category: String, spent: Decimal) -> some View {
        let subs = settings.subcategories(of: category)
        return VStack(alignment: .leading, spacing: 10) {
            GhafCategoryIcon(category: category, tint: theme.accent)
            Text(GhafLocalization.category(category, languageCode: languageCode))
                .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                GhafMoneyLabel(amount: spent, currency: currency, languageCode: languageCode, size: 12)
                if !subs.isEmpty {
                    Text("· \(subs.count)")
                    Image(systemName: "square.stack").font(.system(size: 10, weight: .semibold))
                }
            }
            .font(GhafTypography.body(12, languageCode: languageCode))
            .foregroundStyle(theme.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            if settings.categories.count > 1 {
                Button(role: .destructive) { categoryToRemove = category } label: {
                    Label(ar ? "حذف الفئة" : "Remove category", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: ar ? "حذف الفئة" : "Remove category") { categoryToRemove = category }
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
        themeName = GhafTheme.canonical(settings.themeName)
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

    private func askToImportPickedFile() {
        guard let url = pickedImportURL else { return }
        pickedImportURL = nil
        pendingImportURL = url
        prompt = GhafExpendImportService.canImport(url) ? .importExpend : .importBackup
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


/// Document picker that imports a copy, so the app never depends on access to the original file.
private struct GhafDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .text, .data], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
