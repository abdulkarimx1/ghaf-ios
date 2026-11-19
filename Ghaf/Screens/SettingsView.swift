import SwiftUI
import GhafCore
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

private enum GhafSettingsPrompt: Identifiable {
    case importBackup
    case importExpend
    case message(String)

    var id: String {
        switch self {
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
    @AppStorage("ghaf.glass.enabled") private var glassEnabled = true
    @AppStorage("ghaf.glass.intensity") private var glassIntensity = "balanced"
    @AppStorage("ghaf.glass.grain") private var glassGrain = true
    @AppStorage("ghaf.glass.glow") private var glassGlow = true
    @AppStorage("ghaf.glass.tilt") private var glassTilt = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var photoItem: PhotosPickerItem?
    @State private var hasPhoto = GhafProfilePhoto.load() != nil
    @State private var prompt: GhafSettingsPrompt?
    @State private var showDeleteConfirmation = false
    @State private var hasLoadedSettings = false
    @State private var categoryToRemove: String?
    @State private var editingCategory: String?
    @State private var categoryDraftName = ""
    @State private var showCategories = false
    @State private var proUnlocked = UserDefaults.standard.bool(forKey: "ghaf.pro.testUnlocked")
#if DEBUG
    @State private var fixtureGlassPresented = false
    @State private var fixtureProfilePresented = false
    @State private var fixtureProPresented = false
    @State private var fixtureAboutPresented = false
#endif

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

                    if proUnlocked {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").foregroundStyle(theme.accent)
                            Text(ar ? "أنت مشترك في Pro" : "You're on Pro")
                                .font(GhafTypography.heading(22, languageCode: languageCode)).foregroundStyle(theme.primaryText)
                            Spacer()
                        }
                        .padding(GhafMetrics.cardPadding)
                        .ghafCard(theme: theme)
                    } else {
                        NavigationLink { AnyView(GhafProView(settings: settings, showsClose: false)) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Ghaf Pro")
                                    .font(GhafTypography.heading(22, languageCode: languageCode).weight(.bold))
                                    .foregroundStyle(theme.primaryText)
                                Text(ar ? "تقارير أعمق وأدوات إضافية لإدارة أموالك." : "Deeper reports and more tools to manage your money.")
                                    .font(GhafTypography.body(14, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                                Text(ar ? "عرض الخطط" : "See plans")
                                    .font(GhafTypography.body(17, languageCode: languageCode, weight: .semibold))
                                    .foregroundStyle(theme.accentContrast)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .background(theme.accent, in: Capsule())
                            }
                            .padding(GhafMetrics.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.accent.opacity(theme.isDark ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: GhafMetrics.cardRadius, style: .continuous))
                            .ghafCard(theme: theme)
                        }
                        .buttonStyle(.ghafPress)
                    }

                    menuGroup(ar ? "المال" : "Money") {
                        menuRow(ar ? "الحسابات والمحافظ" : "Accounts & wallets", icon: "wallet.pass.fill") { GhafAccountsView(settings: settings) }
                        menuRow(ar ? "الميزانية والفئات" : "Budget & categories", icon: "chart.pie.fill") { subpage(ar ? "الميزانية والفئات" : "Budget & categories") { budgetPage } }
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
                        menuRow(ar ? "الإشعارات" : "Notifications", icon: "bell.badge.fill") { GhafNotificationSettingsView(settings: settings) }
                        menuRow(ar ? "الأمان والخصوصية" : "Security & privacy", icon: "lock.fill") { subpage(ar ? "الأمان" : "Security") { securityCard } }
                    }

                    menuGroup(ar ? "البيانات" : "Data") {
                        menuRow(ar ? "Google Drive والنسخ الاحتياطي" : "Google Drive & backup", icon: "externaldrive.fill.badge.icloud") { subpage(ar ? "النسخ الاحتياطي" : "Backup") { driveCard; backupCard } }
                        menuRow(ar ? "عن غاف" : "About Ghaf", icon: "leaf.fill") { GhafAboutView(settings: settings) }
                    }

                    Button(role: .destructive) { showDeleteConfirmation = true } label: {
                        Label(ar ? "حذف جميع بيانات غاف" : "Delete all Ghaf data", systemImage: "trash")
                            .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                            .foregroundStyle(theme.over)
                            .frame(maxWidth: .infinity, minHeight: GhafMetrics.buttonHeight)
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
                .ghafScreenPadding()
                .padding(.top, 40)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .ghafStatusBarFade(theme: theme)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ghafKeyboardDone()
            .toolbar(.hidden, for: .navigationBar)
            .tint(theme.accent)
#if DEBUG
            .navigationDestination(isPresented: $fixtureGlassPresented) {
                subpage(ar ? "الزجاج" : "Glass") { glassSettings }
            }
            .navigationDestination(isPresented: $fixtureProfilePresented) {
                subpage(ar ? "الملف الشخصي" : "Profile") { profilePage }
            }
            .navigationDestination(isPresented: $fixtureProPresented) {
                GhafProView(settings: settings, showsClose: false)
            }
            .navigationDestination(isPresented: $fixtureAboutPresented) {
                GhafAboutView(settings: settings)
            }
#endif
        }  // Importer and alerts sit on the stack so they present from pushed pages too.
            .onAppear {
                loadSettings()
                proUnlocked = UserDefaults.standard.bool(forKey: "ghaf.pro.testUnlocked")
#if DEBUG
                if GhafScreenshotFixture.enabled {
                    switch GhafScreenshotFixture.destination {
                    case "settings-glass": fixtureGlassPresented = true
                    case "profile-proof": fixtureProfilePresented = true
                    case "pro-page-proof": fixtureProPresented = true
                    case "about-proof": fixtureAboutPresented = true
                    default: break
                    }
                }
#endif
            }
            .onChange(of: glassEnabled) { _, _ in GhafWidgetSync.refresh(context: modelContext) }
            .onChange(of: languageCode) { _, _ in persistSettings() }
            .onChange(of: weekStart) { _, _ in GhafDigestNotifications.reschedule(context: modelContext) }
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
            .confirmationDialog(languageCode == "ar" ? "حذف كل شيء من هذا الـ iPhone؟" : "Delete everything on this iPhone?",
                                isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button(languageCode == "ar" ? "إنشاء نسخة احتياطية أولاً" : "Export a backup first") {
                    createBackup()
                    prompt = .message(languageCode == "ar"
                        ? "أُنشئت النسخة. افتح البيانات والنسخ الاحتياطي لمشاركتها أو حفظها قبل الحذف."
                        : "The backup is ready. Open Data and backup to save or share it before deleting.")
                }
                Button(languageCode == "ar" ? "حذف كل شيء" : "Delete everything", role: .destructive, action: deleteAllData)
                Button(languageCode == "ar" ? "إلغاء" : "Cancel", role: .cancel) {}
            } message: {
                Text(languageCode == "ar"
                     ? "سيتم حذف الحسابات والعمليات والإعدادات والسمات وذاكرة الذكاء الاصطناعي. لا يمكن التراجع. يُنصح بتصدير نسخة احتياطية أولاً."
                     : "Accounts, transactions, settings, themes and AI memory will be erased. This can't be undone. Export a backup first if you want to keep a copy.")
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
                .padding(.horizontal, 18).frame(minHeight: GhafMetrics.compactButtonHeight)
                .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .buttonStyle(.ghafPress)
    }

    private var profilePage: some View { profileCard }

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

    // The page is type-erased: each row carrying its whole page in its type made More's type so deep
    // that resolving it at launch overflowed the main thread's stack on iOS 27.
    private func menuRow<Destination: View>(_ title: String, icon: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink { AnyView(destination()) } label: {
            GhafListRow(icon: icon, tint: theme.accent, title: title, theme: theme,
                        languageCode: languageCode, chevron: true)
                .padding(.horizontal, 16)
        }
        .buttonStyle(.ghafPress)
    }

    private func subpage<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 16) { content() }
                .ghafScreenPadding().padding(.top, 8).padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .ghafKeyboardDone()
        .ghafPageTitle(title, languageCode: languageCode, theme: theme)
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
                    .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .buttonStyle(.bordered)
            } else {
                Button { Task { await driveRun { try await drive.signIn() } } } label: {
                    Label(ar ? "تسجيل الدخول عبر Google" : "Sign in with Google", systemImage: "person.crop.circle.badge.plus")
                        .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .padding(.vertical, 12)
                }
                .ghafProminentButton(theme: theme, languageCode: languageCode)
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
        let streak = GhafLoggingStreak.count(transactions.filter { !$0.needsReview }.map(\.date), through: .now, calendar: Calendar.current)
        return VStack(spacing: 24) {
            VStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    GhafAvatar(initials: initials, theme: theme, languageCode: languageCode, size: 104)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(theme.accentContrast)
                                .frame(width: 44, height: 44)
                                .background(theme.accent, in: Circle())
                                .overlay(Circle().stroke(theme.surface, lineWidth: 3))
                        }
                        .frame(width: 104, height: 104)
                        .contentShape(Circle())
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
                    .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: GhafMetrics.buttonHeight)
                }
                TextField(ar ? "اسمك" : "Your name", text: $name)
                    .font(GhafTypography.display(26, languageCode: languageCode))
                    .foregroundStyle(theme.primaryText)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                Text(ar ? "على هذا الـ iPhone فقط" : "Stored only on this iPhone")
                    .font(GhafTypography.body(13, languageCode: languageCode, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                profileMetric(value: "\(streak)", title: ar ? "أيام متتالية" : "Logging streak")
                profileMetric(value: "\(transactions.count)", title: ar ? "العمليات" : "Transactions")
                profileMetric(value: "\(activeAccountCount)", title: ar ? "الحسابات" : "Accounts")
            }

            VStack(spacing: 12) {
                Text(ar ? "الإنجازات" : "Milestones")
                    .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    ForEach([7, 30, 100], id: \.self) { days in
                        VStack(spacing: 6) {
                            Text("\(days)")
                                .font(GhafTypography.number(16, weight: .bold))
                                .foregroundStyle(streak >= days ? theme.accentContrast : theme.secondaryText)
                                .frame(width: 56, height: 56)
                                .background(streak >= days ? theme.accent : theme.secondaryText.opacity(0.12), in: Circle())
                            Text(ar ? "يوم" : "days")
                                .font(GhafTypography.body(12, languageCode: languageCode))
                                .foregroundStyle(theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(GhafMetrics.cardPadding)
            .ghafCard(theme: theme)
        }
    }

    private func profileMetric(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(GhafTypography.number(19, weight: .bold)).foregroundStyle(theme.primaryText)
            Text(title).font(GhafTypography.body(11, languageCode: languageCode, weight: .medium))
                .foregroundStyle(theme.secondaryText).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .padding(.horizontal, 5)
        .background(theme.surface, in: Capsule())
        .accessibilityElement(children: .combine)
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
        settingsCard(ar ? "اللغة" : "Language", subtitle: ar ? "لغة الواجهة في جميع أجزاء غاف" : "The language used throughout Ghaf") {
            HStack(spacing: 10) {
                choiceButton("English", detail: "Left to right", selected: languageCode == "en") { languageCode = "en" }
                choiceButton("العربية", detail: "من اليمين لليسار", selected: languageCode == "ar") { languageCode = "ar" }
            }

            settingsLabel(ar ? "بداية الأسبوع" : "Week starts on")
            HStack(spacing: 8) {
                ForEach([(7, ar ? "السبت" : "Saturday"), (1, ar ? "الأحد" : "Sunday"), (2, ar ? "الإثنين" : "Monday")], id: \.0) { day, title in
                    choiceButton(title, detail: nil, selected: weekStart == day) { weekStart = day }
                }
            }
            Text(ar ? "يحدد «هذا الأسبوع» و«الأسبوع الماضي» في غاف AI والرسوم، وموعد الملخص الأسبوعي. الرئيسية تعرض آخر ٧ أيام."
                    : "Sets \"this week\" and \"last week\" in Ghaf AI and charts, and when the weekly summary arrives. Home shows the last 7 days.")
                .font(GhafTypography.body(12, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    /// A large, high-contrast option: filled accent when selected, a quiet tile otherwise.
    private func choiceButton(_ title: String, detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            VStack(spacing: 2) {
                Text(title).font(GhafTypography.body(16, languageCode: languageCode, weight: .bold))
                if let detail { Text(detail).font(GhafTypography.body(11, languageCode: languageCode)).opacity(0.8) }
            }
            .foregroundStyle(selected ? theme.accentContrast : theme.primaryText)
            .frame(maxWidth: .infinity, minHeight: detail == nil ? 50 : 62)
            .background(selected ? theme.accent : theme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? .clear : theme.outline, lineWidth: 1)
            }
        }
        .buttonStyle(.ghafPress)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var appearanceCard: some View {
        settingsCard(languageCode == "ar" ? "المظهر" : "Appearance", subtitle: languageCode == "ar" ? "سبع مدن، كلٌّ بوضع فاتح وداكن" : "Seven cities, each in light and dark") {
            settingsLabel(languageCode == "ar" ? "النمط" : "Theme")
            // One swipeable row instead of a tall grid: the page fits without scrolling past seven cities.
            ScrollViewReader { proxy in
            ScrollView(.horizontal) {
              HStack(spacing: 10) {
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
                                        .frame(width: 44, height: 44)
                                        .frame(maxWidth: .infinity, minHeight: 100)
                                } else {
                                    GhafCityScene(city: option, accent: preview.accent, glow: preview.glow)
                                        .frame(height: 100)
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
                        .frame(width: 112, height: 140)
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
                    .id(option)
                }
              }
              .padding(2)
            }
            .scrollIndicators(.hidden)
            // Open on the chosen city (also keeps Arabic from starting at the far end of the row).
            .onAppear { proxy.scrollTo(themeName, anchor: .center) }
            }

            settingsLabel(languageCode == "ar" ? "وضع المظهر" : "Appearance mode")
HStack(spacing: 8) {
                ForEach([("System", ar ? "حسب الجهاز" : "System"), ("Light", ar ? "فاتح" : "Light"), ("Dark", ar ? "داكن" : "Dark")], id: \.0) { mode, title in
                    choiceButton(title, detail: nil, selected: appearanceMode == mode) { appearanceMode = mode }
                }
            }

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

            glassSettings
        }
    }

    private var glassSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            GhafGlassPreview(theme: theme)
            VStack(spacing: 0) {
                Toggle(ar ? "تأثير الزجاج" : "Glass effect", isOn: $glassEnabled)
                    .frame(minHeight: 56)
                glassDivider
                HStack {
                    Text(ar ? "الشدة" : "Intensity").foregroundStyle(theme.primaryText)
                    Spacer(minLength: 12)
                    GhafSegmented(options: [("subtle", ar ? "خفيف" : "Subtle"), ("balanced", ar ? "متوازن" : "Balanced"), ("bold", ar ? "قوي" : "Bold")], selection: $glassIntensity, theme: theme, languageCode: languageCode)
                }
                .frame(minHeight: 64)
                .disabled(!glassEnabled)
            if reduceTransparency { Text(ar ? "الزجاج متوقف بسبب إعداد تسهيلات الاستخدام." : "Glass is off because Reduce Transparency is enabled.").font(.caption).foregroundStyle(theme.secondaryText) }
            if glassEnabled {
                glassDivider
                Toggle(ar ? "ملمس حبيبي" : "Film grain", isOn: $glassGrain)
                    .frame(minHeight: 56)
                glassDivider
                Toggle(ar ? "توهج خلفي" : "Ambient glow", isOn: $glassGlow)
                    .frame(minHeight: 56)
                glassDivider
                Toggle(ar ? "يتحرك مع ميل الجهاز" : "Move with tilt", isOn: $glassTilt)
                    .frame(minHeight: 56)
            }
            }
            .padding(16)
            .ghafCard(theme: theme)
            Text(ar ? "يتوقف في نمط الطاقة المنخفضة وعند تفعيل تقليل الحركة. يستخدم مستشعر الحركة فقط أثناء فتح غاف." : "Pauses in Low Power Mode and when Reduce Motion is on. Uses the motion sensor only while Ghaf is open.")
                .font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
        }
        .toggleStyle(GhafToggleStyle(theme: theme, languageCode: languageCode))
        .disabled(reduceTransparency)
    }

    private var glassDivider: some View { Divider().overlay(theme.outline) }

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
                        .font(GhafTypography.body(16, languageCode: languageCode, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                    Text(languageCode == "ar"
                        ? "يتطلب المصادقة عند فتح غاف أو العودة إليه."
                        : "Authenticate when opening Ghaf or returning to it.")
                        .font(GhafTypography.body(13, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .tint(theme.accent)
            .frame(minHeight: 52)

            Text(languageCode == "ar"
                ? "يستخدم غاف آلية المصادقة الآمنة في iOS. قد يطلب رمز دخول الجهاز إذا لم تكن البصمة متاحة."
                : "Ghaf uses iOS device authentication. Your device passcode may be requested when biometrics are unavailable.")
                .font(GhafTypography.body(11, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    /// Budget and categories behind two big tabs, so the page is one card tall instead of two.
    private var budgetPage: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                choiceButton(ar ? "الميزانية" : "Budget", detail: nil, selected: !showCategories) { showCategories = false }
                choiceButton(ar ? "الفئات" : "Categories", detail: nil, selected: showCategories) { showCategories = true }
            }
            if showCategories { categoriesCard } else { budgetCard }
        }
    }

    private var budgetCard: some View {
        settingsCard(ar ? "الميزانية" : "Budget",
                     subtitle: ar ? "الميزانية هي المبلغ الذي تخطط أن تصرفه. يقارن غاف صرفك الفعلي بها ويخبرك إن كنت مرتاحاً أو قريباً من الحد أو تجاوزته."
                                  : "A budget is how much you plan to spend. Ghaf compares what you actually spend with it and tells you if you're comfortable, close or over.") {
            HStack(spacing: 10) {
                budgetChoice("Daily", ar ? "حد يومي" : "Daily limit",
                             ar ? "مبلغ لكل يوم من دخلك" : "One amount a day from your income", icon: "sun.max.fill")
                budgetChoice("Category", ar ? "حسب الفئة" : "By category",
                             ar ? "سقف شهري لكل فئة" : "A monthly cap per category", icon: "square.grid.2x2.fill")
            }

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
                        GhafAmountField(value: budgetBinding(for: category), currency: settings.currency,
                                        label: GhafLocalization.category(category, languageCode: languageCode),
                                        theme: theme, languageCode: languageCode)
                            .frame(width: 132)
                    }
                }
            }
        }
    }

    private func budgetChoice(_ value: String, _ title: String, _ detail: String, icon: String) -> some View {
        let selected = budgetMode == value
        return Button { withAnimation(.snappy) { budgetMode = value } } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? theme.accentContrast : theme.accent)
                Text(title).font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                Text(detail).font(GhafTypography.body(12, languageCode: languageCode)).opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selected ? theme.accentContrast : theme.primaryText)
            .padding(GhafMetrics.cardPadding)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(selected ? theme.accent : theme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.ghafPress)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var categoriesCard: some View {
        let spent = categorySpendThisMonth
        return settingsCard(ar ? "الفئات" : "Categories",
                            subtitle: ar ? "اضغط على فئة لتعديل اسمها أو حذفها" : "Tap a category to rename or remove it") {
            ForEach(categoryGroups, id: \.title) { group in
                if !group.names.isEmpty {
                    settingsLabel(group.title)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(group.names, id: \.self) { category in
                            Button { editingCategory = category; categoryDraftName = GhafLocalization.category(category, languageCode: languageCode) } label: {
                                categoryTile(category, spent: spent[category] ?? 0)
                            }
                            .buttonStyle(.ghafPress)
                        }
                    }
                }
            }
            Label(ar ? "يتعلم غاف من تعديلاتك: عندما تغيّر فئة عملية، يتذكر التاجر ويقترح نفس الفئة في المرة القادمة. يُحفظ ذلك على جهازك ويمكنك مراجعته في «ما تعلّمه غاف»."
                     : "Ghaf learns from your edits: change a transaction's category and it remembers that merchant for next time. This stays on your iPhone; review it in What Ghaf learned.",
                  systemImage: "brain.head.profile")
                .font(GhafTypography.body(12, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
            HStack(spacing: 8) {
                GhafTextField(text: $newCategory, placeholder: ar ? "فئة جديدة" : "New category", theme: theme,
                              languageCode: languageCode, onSubmit: addCategory)
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
        .sheet(item: Binding(get: { editingCategory.map(GhafEditingCategory.init) }, set: { editingCategory = $0?.name })) { item in
            categoryEditor(item.name)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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

    /// Expenses, income and transfers apart, so the list reads like the money it describes.
    private var categoryGroups: [(title: String, names: [String])] {
        let transfers = settings.categories.filter { $0.localizedCaseInsensitiveContains("transfer") }
        let income = settings.categories.filter { name in
            !transfers.contains(name) && (CategoryTaxonomy.category(named: name)?.isIncome ?? false
                || ["Salary", "Other Income", "Income"].contains(name))
        }
        let expenses = settings.categories.filter { !transfers.contains($0) && !income.contains($0) }
        return [(ar ? "المصروفات" : "Expenses", expenses), (ar ? "الدخل" : "Income", income), (ar ? "التحويلات" : "Transfers", transfers)]
    }

    private func categoryEditor(_ category: String) -> some View {
        let builtIn = CategoryTaxonomy.category(named: category) != nil
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                GhafCategoryIcon(category: category, tint: theme.accent, theme: theme)
                Text(GhafLocalization.category(category, languageCode: languageCode))
                    .font(GhafTypography.heading(20, languageCode: languageCode))
                    .foregroundStyle(theme.primaryText)
            }
            settingsLabel(ar ? "الاسم" : "Name")
            settingsField(ar ? "اسم الفئة" : "Category name", text: $categoryDraftName)
            Text(ar ? "تبقى العمليات والتجار الذين تعلّمهم غاف في هذه الفئة بعد تغيير الاسم."
                    : "Its transactions and the merchants Ghaf learned stay with it under the new name.")
                .font(GhafTypography.body(12, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
            HStack(spacing: 10) {
                if settings.categories.count > 1 {
                    Button(ar ? "حذف" : "Remove", role: .destructive) { categoryToRemove = category; editingCategory = nil }
                        .ghafGlassButton(theme: theme, languageCode: languageCode)
                }
                Button(ar ? "حفظ" : "Save") {
                    renameCategory(category, to: categoryDraftName)
                    editingCategory = nil
                }
                .ghafProminentButton(theme: theme, languageCode: languageCode)
                .disabled(categoryDraftName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if builtIn {
                Text(ar ? "فئة أساسية: تغيير اسمها ينشئ فئة باسمك وينقل إليها كل شيء." : "A built-in category: renaming creates yours and moves everything to it.")
                    .font(GhafTypography.body(11, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(GhafMetrics.gutter)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.background)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    /// Moves a category to a new name everywhere it is used: the list, budgets, subcategories,
    /// transactions and learned merchant rules. Nothing else changes.
    private func renameCategory(_ old: String, to rawNew: String) {
        let new = rawNew.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != old, new != GhafLocalization.category(old, languageCode: languageCode) else { return }
        guard !settings.categories.contains(new) else {
            prompt = .message(ar ? "توجد فئة بهذا الاسم." : "A category with that name already exists.")
            return
        }
        settings.categories = settings.categories.map { $0 == old ? new : $0 }
        var meta = settings.categoryMeta
        if let value = meta.removeValue(forKey: old) { meta[new] = value }
        settings.categoryMeta = meta
        var budgets = settings.categoryBudgets
        if let value = budgets.removeValue(forKey: old) { budgets[new] = value }
        settings.categoryBudgets = budgets
        if let text = categoryBudgetTexts.removeValue(forKey: old) { categoryBudgetTexts[new] = text }
        for transaction in transactions where transaction.category == old { transaction.category = new }
        if let rules = try? modelContext.fetch(FetchDescriptor<MerchantCategoryRule>()) {
            for rule in rules where rule.category == old { rule.category = new }
        }
        do { try modelContext.save() } catch {
            modelContext.rollback()
            prompt = .message(ar ? "تعذر تغيير الاسم." : "Couldn't rename the category.")
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
            GhafCategoryIcon(category: category, tint: theme.accent, theme: theme)
            Text(GhafLocalization.category(category, languageCode: languageCode))
                .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                GhafMoneyLabel(amount: spent, currency: currency, languageCode: languageCode, size: 12)
                if !subs.isEmpty {
                    Text("· \(subs.count)")
                    Image(systemName: "square.stack").font(.system(size: 11, weight: .semibold))
                }
            }
            .font(GhafTypography.body(12, languageCode: languageCode))
            .foregroundStyle(theme.secondaryText)
        }
        .padding(GhafMetrics.cardPadding)
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
                settingsActionRow(languageCode == "ar" ? "إنشاء نسخة احتياطية" : "Create JSON backup", detail: languageCode == "ar" ? "تصدير الحسابات والعمليات والاشتراكات والإعدادات والذاكرة والتفضيلات" : "Export accounts, transactions, subscriptions, settings, memories and preferences", icon: "square.and.arrow.up")
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
                .font(GhafTypography.body(11, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(languageCode == "ar" ? "ملاحظة: لا تتضمن النسخة محادثات غاف AI المحفوظة." : "Saved Ghaf AI conversations are not included in backups.")
                .font(GhafTypography.body(11, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            #if DEBUG
            Button {
                Task {
                    do {
                        let result = try await GhafBackupService.debugRoundTripCheck(context: modelContext)
                        prompt = .message("Backup round-trip: \(result)")
                    } catch {
                        prompt = .message(error.localizedDescription)
                    }
                }
            } label: {
                settingsActionRow(languageCode == "ar" ? "فحص النسخ الاحتياطي (للتطوير)" : "Run backup round-trip check (Debug)",
                                  detail: languageCode == "ar" ? "يصدر نسخة ثم يمسح بيانات هذا المحاكي ويستعيدها للتحقق" : "Exports, resets this simulator's Ghaf data, restores it, then compares models and preferences",
                                  icon: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.ghafPress)
            #endif
        }
    }

    private func settingsCard<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> AnyView {
        // Erased so a page holding several cards keeps a shallow type (see menuRow).
        AnyView(VStack(alignment: .leading, spacing: 14) {
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
        .ghafCard(theme: theme, radius: 20))
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
        Group {
            if numeric {
                GhafAmountField(value: text, currency: settings.currency, label: placeholder,
                                theme: theme, languageCode: languageCode)
            } else {
                GhafTextField(text: text, placeholder: placeholder, theme: theme, languageCode: languageCode)
            }
        }
    }

    private func settingsActionRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(GhafTypography.body(16, languageCode: languageCode, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text(detail)
                    .font(GhafTypography.body(13, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(minHeight: 60)
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
        let arabic = languageCode == "ar"
        Task {
            do {
                let issues = try await GhafResetService.run(context: modelContext)
                prompt = issues.isEmpty ? nil : .message(arabic
                    ? "حُذفت البيانات، لكن تعذّر حذف بعض ملفات الجهاز أو عناصر سلسلة المفاتيح: \(issues.joined(separator: ", "))"
                    : "Data was deleted, but some device files or keychain items could not be removed: \(issues.joined(separator: ", "))")
            } catch {
                prompt = .message(arabic ? "تعذر حذف جميع البيانات: \(error.localizedDescription)" : "Could not delete all data: \(error.localizedDescription)")
            }
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

private struct GhafEditingCategory: Identifiable {
    let name: String
    var id: String { name }
}
