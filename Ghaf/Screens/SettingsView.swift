import SwiftUI
import GhafCore
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import UIKit

private enum GhafSettingsPrompt: Identifiable {
    case importBackup
    case importOtherBudgetApp
    case message(String)

    var id: String {
        switch self {
        case .importBackup: return "import"
        case .importOtherBudgetApp: return "import-other-budget-app"
        case .message(let value): return "message-\(value)"
        }
    }
}

struct GhafSettingsView: View {
    private struct SavedPlace: Decodable { let name: String; let latitude: Double; let longitude: Double; let address: String?; let phone: String? }
    private struct PlaceSummary: Identifiable { let name: String; let count: Int; let totals: [String: Decimal]; var id: String { name } }
    @Environment(\.modelContext) private var modelContext
    @Environment(GhafTabRouter.self) private var router
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]

    let settings: GhafSettings

    @State private var name = ""
    @State private var arabicName = ""
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
    @State private var showBackupShare = false
    @State private var pendingImportURL: URL?
    @State private var showImportSheet = false
    /// Weekly totals everywhere follow this; the region's first weekday until the user picks one.
    @AppStorage(GhafCalendar.weekStartKey) private var weekStart = Calendar.current.firstWeekday
    @AppStorage("ghaf.glass.enabled") private var glassEnabled = true
    @AppStorage("ghaf.glass.intensity") private var glassIntensity = "balanced"
    @AppStorage("ghaf.glass.grain") private var glassGrain = true
    @AppStorage("ghaf.glass.glow") private var glassGlow = true
    @AppStorage("ghaf.glass.tilt") private var glassTilt = true
    @AppStorage("ghaf.glass.rim") private var glassRim = "thick"
    @AppStorage("ghaf.inAppSounds") private var inAppSounds = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var photoItem: PhotosPickerItem?
    @State private var hasPhoto = GhafProfilePhoto.load() != nil
    @State private var showPhotoMenu = false
    @State private var showBudgetCharacterInfo = false
    @State private var showBudgetFromCharacter = false
    @State private var showCameraPicker = false
    @State private var isEditingProfileName = false
    @State private var draftProfileName = ""
    @State private var draftArabicName = ""
    @FocusState private var profileNameFocused: Bool
    @State private var prompt: GhafSettingsPrompt?
    @State private var showDeleteConfirmation = false
    @State private var hasLoadedSettings = false
    @State private var profileStreak = 0
    @State private var profileStreakKey: String?
    @State private var cachedPlaceSummaries: [PlaceSummary] = []
    @State private var categoryToRemove: String?
    @State private var subcategoryToRemove: String?
    @State private var editingCategory: String?
    @State private var categoryDraftName = ""
    @State private var showCategories = false
    @State private var proUnlocked = GhafProAccess.hasAccess
    @State private var selectedMilestone: Int?
    @State private var showPendingMilestoneProfile = false
    @State private var showProSheet = false
    @State private var redeemingVoucher = false
    @AppStorage("ghaf.ai.voiceCharacter") private var voiceCharacter = ""
    @AppStorage("ghaf.pad.mirrored") private var padMirrored = false
#if DEBUG
    @State private var fixtureGlassPresented = false
    @State private var fixtureProfilePresented = false
    @State private var fixtureProPresented = false
    @State private var fixtureAboutPresented = false
    @State private var fixtureDrivePresented = false
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
                // Not Lazy: a LazyVStack here spun the main thread in layout once scrolled (UI tests never idled); ~8 cards.
                VStack(spacing: GhafMetrics.sectionSpacing) {
                    // Owner 1.31: this tab opens Profile; the gear (beside the avatar, not on its own row) opens Settings.
                    profilePage.overlay(alignment: .topTrailing) {
                        NavigationLink {
                            GhafDeferredView { subpage(ar ? "الإعدادات" : "Settings") { settingsList } }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                                .frame(width: 44, height: 44)
                                .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Circle())
                        }
                        .buttonStyle(.ghafPress)
                        .accessibilityLabel(ar ? "الإعدادات" : "Settings")
                    }
                    // Owner #54: the wallet, in the same spot and style as Home's header button.
                    .overlay(alignment: .topLeading) {
                        NavigationLink { GhafAccountsView(settings: settings) } label: {
                            Image(systemName: "wallet.bifold.fill")
                                .foregroundStyle(theme.primaryText)
                                .frame(width: 44, height: 44)
                                .background(theme.surface, in: Circle())
                        }
                        .buttonStyle(.ghafPress)
                        .accessibilityLabel(ar ? "الحسابات" : "Accounts")
                    }

                    if proUnlocked {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").foregroundStyle(theme.accent)
                            Text(ar ? "أنت مشترك في غاف برو" : "You're on Pro")
                                .font(GhafTypography.heading(22, languageCode: languageCode)).foregroundStyle(theme.primaryText)
                            Spacer()
                        }
                        .padding(GhafMetrics.cardPadding)
                        .ghafCard(theme: theme)
                    } else {
                        Button { showProSheet = true } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ghaf Pro")
                                        .font(GhafTypography.heading(25, languageCode: languageCode).weight(.bold))
                                        .foregroundStyle(theme.primaryText)
                                    Text(ar ? "مساحة أوسع للتخطيط وإدارة أموالك." : "More room to plan and manage your money.")
                                        .font(GhafTypography.body(13, languageCode: languageCode))
                                        .foregroundStyle(theme.primaryText.opacity(0.78))
                                        .lineLimit(1).minimumScaleFactor(0.76)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(theme.primaryText)
                                    .frame(width: 34, height: 30)
                                    .background(theme.primaryText.opacity(0.12), in: Capsule())
                            }
                            .padding(.horizontal, 18).padding(.vertical, 20)
                            .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
                            .background {
                                ZStack {
                                    GhafProBannerGlow(theme: theme)
                                    theme.background.opacity(theme.isDark ? 0.25 : 0.16)
                                }.clipShape(RoundedRectangle(cornerRadius: GhafMetrics.cardRadius, style: .continuous))
                            }
                            .overlay(RoundedRectangle(cornerRadius: GhafMetrics.cardRadius, style: .continuous).stroke(theme.outline.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(.ghafPress)
                        .ghafProSheet(isPresented: $showProSheet, settings: settings)
                    }

                    inviteCard
                }
                .ghafScreenPadding()
                .padding(.top, 8)
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
            .navigationDestination(isPresented: $fixtureDrivePresented) {
                subpage(ar ? "النسخ الاحتياطي" : "Backup") { driveCard; backupCard }
            }
#endif
            .navigationDestination(isPresented: $showBudgetFromCharacter) { GhafBudgetView(settings: settings) }
            .navigationDestination(isPresented: $showPendingMilestoneProfile) {
                subpage(ar ? "الملف الشخصي" : "Profile") { profilePage }
            }
        }  // Importer and alerts sit on the stack so they present from pushed pages too.
            .onAppear {
                loadSettings()
                proUnlocked = GhafProAccess.hasAccess
                Task {
                    _ = await GhafAITier.refreshVerifiedEntitlement()
                    proUnlocked = GhafProAccess.hasAccess
                }
                refreshProfileStreakIfNeeded()
                if let days = router.pendingMilestone {
                    router.pendingMilestone = nil
                    selectedMilestone = days
                    showPendingMilestoneProfile = true
                }
#if DEBUG
                if GhafScreenshotFixture.enabled {
                    switch GhafScreenshotFixture.destination {
                    case "settings-glass": fixtureGlassPresented = true
                    case "profile-proof": fixtureProfilePresented = true
                    case "pro-page-proof": fixtureProPresented = true
                    case "about-proof": fixtureAboutPresented = true
                    case "drive-proof": fixtureDrivePresented = true
                    case "milestone-proof": fixtureProfilePresented = true; selectedMilestone = 7
                    default: break
                    }
                }
#endif
            }
            .onChange(of: "\(transactions.count)-\(router.ledgerRevision)") { _, _ in refreshProfileStreakIfNeeded() }
            .onChange(of: glassEnabled) { _, _ in GhafWidgetSync.refresh(context: modelContext) }
            .onChange(of: languageCode) { _, _ in persistSettings() }
            .onChange(of: weekStart) { _, _ in GhafDigestNotifications.reschedule(context: modelContext) }
            .onChange(of: currency) { _, _ in persistSettings() }
            .onChange(of: income) { _, _ in persistSettings() }
            .onChange(of: commitments) { _, _ in persistSettings() }
            .onChange(of: themeName) { _, _ in persistSettings() }
            .onChange(of: appearanceMode) { _, _ in persistSettings() }
            .onChange(of: budgetMode) { _, _ in persistSettings() }
            .onChange(of: categoryBudgetTexts) { _, _ in persistSettings() }
            .sheet(isPresented: $showImportSheet) { GhafImportSheet(settings: settings) }
            .sheet(isPresented: $showBackupShare) {
                if let backupURL { GhafSettingsShareSheet(items: [backupURL]) }
            }
            .sheet(isPresented: $showCameraPicker) {
                GhafCameraPicker { image in
                    do { try GhafProfilePhoto.save(image); hasPhoto = true }
                    catch { prompt = .message(ar ? "تعذر حفظ الصورة." : "Couldn't save the photo.") }
                }
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
                case .importOtherBudgetApp:
                    return Alert(
                        title: Text(languageCode == "ar" ? "استيراد بيانات تطبيق ميزانية آخر؟" : "Import another budgeting app's data?"),
                        message: Text(languageCode == "ar"
                            ? "سيتم استبدال بيانات غاف الحالية بالحسابات والعمليات من الملف. تُضاف المدفوعات المتكررة كاشتراكات، ولا تُنقل الميزانيات حالياً."
                            : "This replaces current Ghaf records with the accounts and transactions in this file. Recurring payments become subscriptions; budgets are not imported yet."),
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

    @ViewBuilder private var settingsList: some View {
                    menuGroup(ar ? "المال" : "Money") {
                        menuRow(ar ? "الميزانية والفئات" : "Budget & categories", icon: "chart.pie.fill") { subpage(ar ? "الميزانية والفئات" : "Budget & categories") { budgetPage } }
                        menuRow(ar ? "دورة الراتب" : "Salary cycle", icon: "calendar.badge.clock") { GhafSalarySettingsView(settings: settings) }
                        menuRow(ar ? "ربط البنك تلقائياً" : "Bank automation", icon: "bolt.fill") { GhafAutomationGuideView(settings: settings) }
                    }

                    menuGroup("Ghaf AI") {
                        menuRow(ar ? "ما تعلّمه غاف" : "What Ghaf learned", icon: "brain.head.profile") { GhafLearnedRulesView(settings: settings) }
                        menuRow(ar ? "الصوت" : "Voice", icon: "waveform", value: voiceCharacter.isEmpty ? "Hamad" : voiceCharacter) {
                            GhafAIVoiceSettingsView(settings: settings, firstChoiceRequired: false)
                        }
                    }

                    menuGroup(ar ? "التطبيق" : "App") {
                        menuRow(ar ? "الودجات" : "Widgets", icon: "square.grid.2x2.fill") { GhafWidgetGalleryView(settings: settings) }
                        menuRow(ar ? "التخصيص" : "Customization", icon: "paintpalette.fill") {
                            subpage(ar ? "التخصيص" : "Customization") { languageCard; sexCard; currencyCard; keypadCard; mapsCard; soundCard; appearanceCard }
                        }
                        menuRow(ar ? "الإشعارات" : "Notifications", icon: "bell.badge.fill") { GhafNotificationSettingsView(settings: settings) }
                        menuRow(ar ? "النشاط المباشر" : "Live Activity", icon: "livephoto") { GhafLiveActivitySettingsView(settings: settings) }
                        menuRow(ar ? "الأمان والخصوصية" : "Security & privacy", icon: "lock.fill") { subpage(ar ? "الأمان" : "Security") { securityCard } }
                    }

                    menuGroup(ar ? "البيانات" : "Data") {
                        menuRow(ar ? "Google Drive والنسخ الاحتياطي" : "Google Drive & backup", icon: "externaldrive.fill.badge.icloud") { subpage(ar ? "النسخ الاحتياطي" : "Backup") { driveCard; backupCard } }
                        menuRow(ar ? "عن غاف" : "About Ghaf", icon: "info.circle.fill") { GhafAboutView(settings: settings) }
                    }

                    Button(role: .destructive) { showDeleteConfirmation = true } label: {
                        Label(ar ? "حذف جميع بيانات غاف" : "Delete all Ghaf data", systemImage: "trash")
                    }
                    .ghafDestructiveButton(theme: theme, languageCode: languageCode)

                    Text(languageCode == "ar" ? "تبقى بياناتك على هذا الـ iPhone.\nلا يتصل غاف بخادم مالي." : "Your data stays on this iPhone.\nGhaf does not connect to a financial server.")
                        .font(GhafTypography.body(12, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: 320, alignment: .center)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
    }

    /// V16: the user's sex picks the Arabic forms Ghaf's voices and replies use; changes apply immediately.
    private var sexCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ar ? "الجنس" : "Sex")
                .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            GhafSegmented(options: [("male", ar ? "ذكر" : "Male"), ("female", ar ? "أنثى" : "Female")],
                          selection: Binding(get: { ["male", "female"].contains(settings.userSex ?? "") ? settings.userSex! : "" },
                                             set: { settings.userSex = $0; GhafCloudVoice.matchVoice(toSex: $0); try? modelContext.save() }),
                          theme: theme, languageCode: languageCode)
            Text(ar ? "يخاطبك غاف بالصيغة المناسبة." : "Ghaf speaks to you in the matching Arabic forms.")
                .font(GhafTypography.body(12, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(GhafMetrics.cardPadding)
        .ghafCard(theme: theme)
    }

    /// Invite: shares a message for now. shortcut: no referral discount until there's an App Store developer account.
    private var inviteCard: some View {
        ShareLink(item: ar ? "أستخدم غاف لتتبّع مصاريفي وحساباتي بالعربي والإنجليزي. جرّبه!" : "I use Ghaf to track my spending and accounts in Arabic and English. Try it!") {
            HStack(spacing: 14) {
                Image(systemName: "gift.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44).background(theme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(ar ? "ادعُ صديقاً" : "Invite a friend")
                        .font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
                    Text(ar ? "شارك غاف مع من تهتم لأمرهم." : "Share Ghaf with someone who'd use it.")
                        .font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up").foregroundStyle(theme.secondaryText)
            }
            .padding(GhafMetrics.cardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.ghafPress)
        .ghafCard(theme: theme)
    }

    private var initials: String {
        let value = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
        return value.isEmpty ? (ar ? "غ" : "G") : value.uppercased()
    }

    private var profilePage: some View { profileCard.offerCodeRedemption(isPresented: $redeemingVoucher) }

    private var profileDisplayName: String {
        let arabic = settings.arabicName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ar && !arabic.isEmpty ? arabic : name
    }

    private func saveProfileName() {
        name = draftProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        arabicName = draftArabicName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.userName = name
        settings.arabicName = arabicName
        do { try modelContext.save() }
        catch { prompt = .message(ar ? "تعذر حفظ الاسم." : "Couldn't save the name.") }
        isEditingProfileName = false
        profileNameFocused = false
    }

    private func discardProfileName() {
        guard isEditingProfileName else { return }
        draftProfileName = name
        draftArabicName = arabicName
        isEditingProfileName = false
        profileNameFocused = false
    }

    private var photoActionsSheet: some View {
        VStack(spacing: 10) {
            Capsule().fill(theme.secondaryText.opacity(0.35)).frame(width: 36, height: 5).padding(.top, 8)
            Text(ar ? "صورة الملف الشخصي" : "Profile photo")
                .font(GhafTypography.heading(18, languageCode: languageCode)).foregroundStyle(theme.primaryText)
                .padding(.bottom, 2)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(ar ? "اختيار صورة" : "Choose photo", systemImage: "photo")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.ghafPress).ghafCard(theme: theme)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showPhotoMenu = false; showCameraPicker = true } label: {
                    Label(ar ? "التقاط صورة" : "Take photo", systemImage: "camera")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.ghafPress).ghafCard(theme: theme)
            }
            if hasPhoto {
                Button(role: .destructive) {
                    GhafProfilePhoto.remove(); hasPhoto = false; photoItem = nil; showPhotoMenu = false
                } label: {
                    Label(ar ? "إزالة الصورة" : "Remove photo", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.ghafPress).ghafCard(theme: theme)
            }
            Button(ar ? "إلغاء" : "Cancel") { showPhotoMenu = false }
                .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.accent).frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
        .ghafBottomCard(theme: theme, languageCode: languageCode)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var budgetCharacterSheet: some View {
        let preset = BudgetAllocation.Preset(rawValue: settings.allocationPresetRaw) ?? .balanced
        let shares = preset.shares
        let split = "\(NSDecimalNumber(decimal: (shares[.needs] ?? 0) * 100).intValue)/\(NSDecimalNumber(decimal: (shares[.wants] ?? 0) * 100).intValue)/\(NSDecimalNumber(decimal: (shares[.savings] ?? 0) * 100).intValue)"
        let description = budgetCharacterLine
        return VStack(spacing: 14) {
            Text(budgetCharacterName).font(GhafTypography.heading(19, languageCode: languageCode)).foregroundStyle(theme.primaryText)
            Text(description).font(GhafTypography.body(14, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(ar ? "الاحتياجات / الرغبات / الادخار · \(split)٪" : "Needs / wants / savings · \(split)%")
                .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
            // V13: a sheet is outside the parent's NavigationStack, so close it and push Budget from the parent.
            Button {
                showBudgetCharacterInfo = false
                Task { try? await Task.sleep(for: .milliseconds(350)); showBudgetFromCharacter = true }
            } label: {
                Text(ar ? "تغيير الميزانية" : "Change in Budget").frame(maxWidth: .infinity)
            }.ghafProminentButton(theme: theme, languageCode: languageCode)
        }
        .padding(24)
        .ghafBottomCard(theme: theme, languageCode: languageCode)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    /// The character's personality line, under its name on Profile (owner 1.31) and in its sheet.
    private var budgetCharacterLine: String {
        let preset = BudgetAllocation.Preset(rawValue: settings.allocationPresetRaw) ?? .balanced
        return switch preset {
        // Owner #47: describe the character, not the split.
        case .balanced: ar ? "هادي ومتّزن، تعطي كل شي حقّه بدون مبالغة." : "Calm and even-handed, you give everything its fair share."
        case .highRentCity: ar ? "تخطّط قبل لا تصرف، وكل درهم يعرف مكانه." : "You plan before you spend, and every dirham knows its place."
        case .essentialsFirst: ar ? "تحب التجربة وتعيش يومك، والادخار يمشي معك على مهله." : "You enjoy trying new things, and saving keeps pace at its own speed."
        case .guardian: ar ? "حذر وثابت، تحمي الأساسيات قبل أي شي ثاني." : "Careful and steady, you protect the basics before anything else."
        }
    }

    private var budgetCharacterName: String {
        let preset = BudgetAllocation.Preset(rawValue: settings.allocationPresetRaw) ?? .balanced
        if !ar { return preset.name }
        return switch preset {
        case .balanced: "البطل"
        case .highRentCity: "الاستراتيجي"
        case .essentialsFirst: "المستكشف"
        case .guardian: "الحارس"
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

    // The page is type-erased: each row carrying its whole page in its type made More's type so deep
    // that resolving it at launch overflowed the main thread's stack on iOS 27.
    private func menuRow<Destination: View>(_ title: String, icon: String, value: String? = nil, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink { GhafDeferredView { AnyView(destination()) } } label: {
            GhafListRow(icon: icon, tint: theme.accent, title: title, theme: theme,
                        languageCode: languageCode, chevron: true) {
                if let value {
                    Text(value).font(GhafTypography.body(14, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                }
            }
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
            if drive.isConnected, let email = drive.email {
                HStack(spacing: 12) {
                    if let avatar = drive.avatarURL, let url = URL(string: avatar) {
                        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(theme.secondaryText)
                        }
                        .frame(width: 48, height: 48).clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(theme.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(email).font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
                        Text(ar ? "متصل بحساب Google" : "Connected to Google")
                            .font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.credit)
                    }
                    Spacer()
                    Image("Brand-google").resizable().renderingMode(.template).foregroundStyle(theme.primaryText).scaledToFit().frame(width: 24, height: 24)
                }.padding(.vertical, 6)
                HStack {
                    Text(ar ? "آخر نسخة احتياطية" : "Last backup")
                    Spacer()
                    Text(drive.lastBackupDate?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(GhafLocale.locale(identifier: languageCode))) ?? (ar ? "لا توجد نسخة بعد" : "No backup yet"))
                }.font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                Button { driveBackup() } label: {
                    settingsActionRow(ar ? "نسخ احتياطي الآن" : "Back up now", detail: ar ? "رفع نسخة جديدة إلى Drive" : "Upload a fresh copy to Drive", icon: "icloud.and.arrow.up")
                }
                .buttonStyle(.ghafPress).disabled(drive.isBusy)
                Button { driveRestore() } label: {
                    settingsActionRow(ar ? "استعادة آخر نسخة" : "Restore latest backup", detail: ar ? "تنزيل آخر نسخة من Drive" : "Download the newest copy from Drive", icon: "icloud.and.arrow.down")
                }
                .buttonStyle(.ghafPress).disabled(drive.isBusy)
                Button(ar ? "قطع الاتصال" : "Disconnect", role: .destructive) { drive.signOut() }
                    .ghafDestructiveButton(theme: theme, languageCode: languageCode)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(theme.secondaryText)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ar ? "حساب Google" : "Google account").font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
                            Text(ar ? "ستظهر تفاصيل الاتصال هنا" : "Your connection details will appear here")
                                .font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                        Image("Brand-google").resizable().renderingMode(.template).foregroundStyle(theme.primaryText).scaledToFit().frame(width: 24, height: 24)
                    }
                    HStack {
                        Text(ar ? "آخر نسخة احتياطية" : "Last backup"); Spacer()
                        Text(ar ? "لا توجد نسخة بعد" : "No backup yet")
                    }.font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                    Button { Task { await driveRun { try await drive.signIn() } } } label: {
                        HStack(spacing: 12) {
                            Image("Brand-google").renderingMode(.template).resizable().scaledToFit().frame(width: 20, height: 20)
                            Text(ar ? "تسجيل الدخول عبر Google" : "Sign in with Google")
                        }
                    }
                    .ghafGlassButton(theme: theme, languageCode: languageCode)
                    .disabled(!drive.isConfigured || drive.isBusy)
                }
            }
            Toggle(ar ? "النسخ التلقائي" : "Automatic backup", isOn: .constant(false))
                .disabled(true).opacity(0.4)
            Text(ar ? "قريباً" : "Coming soon")
                .font(GhafTypography.body(11, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
            Text(ar ? "تنتقل النسخة مباشرةً من iPhone إلى حسابك في Google Drive، ولا يطّلع عليها غاف."
                    : "Your backup goes straight from your iPhone to your own Google Drive. Ghaf never sees it.")
                .font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
        let streak = profileStreak
        return VStack(spacing: 18) {
            VStack(spacing: 10) {
                GhafAvatar(initials: initials, theme: theme, languageCode: languageCode, size: 104)
                    .overlay { GhafStreakRing(streak: streak, theme: theme, ar: ar).padding(-10).allowsHitTesting(false) }
                    .overlay(alignment: .bottomTrailing) {
                        Button { showPhotoMenu = true } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(theme.accentContrast)
                                .frame(width: 44, height: 44)
                                .background(theme.accent, in: Circle())
                                .overlay(Circle().stroke(theme.surface, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ar ? "صورة الملف الشخصي" : "Profile photo options")
                    }
                    .frame(width: 104, height: 104)
                    .padding(10) // owner #48: room for the streak ring, which draws 10 pt outside the avatar
                    .padding(.top, 14)
                    .accessibilityLabel(ar ? "صورة الملف الشخصي" : "Profile photo options")
                    .onChange(of: photoItem) { _, item in
                        Task {
                            guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                            do { try GhafProfilePhoto.save(image); hasPhoto = true }
                            catch { prompt = .message(ar ? "تعذر حفظ الصورة." : "Couldn't save the photo.") }
                        }
                    }
                HStack(spacing: 5) {
                    if isEditingProfileName {
                        TextField(ar ? "اسمك" : "Your name", text: $draftProfileName)
                            .font(GhafTypography.display(23, languageCode: languageCode)).foregroundStyle(theme.primaryText)
                            .multilineTextAlignment(.center).textInputAutocapitalization(.words).submitLabel(.done)
                            .focused($profileNameFocused)
                            .onChange(of: draftProfileName) { _, value in if value.count > 20 { draftProfileName = String(value.prefix(20)) } }
                        Button(ar ? "تم" : "Done", action: saveProfileName)
                            .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.accent)
                    } else {
                        Text(profileDisplayName.isEmpty ? (ar ? "أضف اسمك" : "Add your name") : profileDisplayName)
                            .font(GhafTypography.display(26, languageCode: languageCode)).foregroundStyle(theme.primaryText)
                            .lineLimit(2).minimumScaleFactor(0.8)
                            // The pencil hangs off the name's trailing edge so the name itself stays centred (mirrors in RTL).
                            .overlay(alignment: .trailing) {
                        Button {
                            draftProfileName = name
                            draftArabicName = arabicName
                            isEditingProfileName = true
                            profileNameFocused = true
                        } label: { Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)) }
                            .foregroundStyle(theme.accent).frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel(ar ? "تعديل الاسم" : "Edit name")
                            .alignmentGuide(.trailing) { d in d[.leading] + 6 }
                            }
                    }
                }
                if isEditingProfileName {
                    TextField(ar ? "الاسم بالعربية (اختياري)" : "Name in Arabic (optional)", text: $draftArabicName)
                        .font(GhafTypography.body(16, languageCode: "ar")).foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.center).submitLabel(.done)
                        .accessibilityLabel(ar ? "الاسم بالعربية" : "Name in Arabic")
                        .onChange(of: draftArabicName) { _, value in if value.count > 20 { draftArabicName = String(value.prefix(20)) } }
                    Text(ar ? "\(draftProfileName.count)/20 حرفًا" : "\(draftProfileName.count)/20 characters")
                        .font(GhafTypography.body(11, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                        .opacity(draftProfileName.count >= 16 || draftArabicName.count >= 16 ? 1 : 0)
                }
                // V11: the character reads as an identity badge (tinted capsule + chevron), not just bigger text.
                Button { showBudgetCharacterInfo = true } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Text(budgetCharacterName)
                                .font(GhafTypography.heading(16, languageCode: languageCode))
                            Image(systemName: "chevron.forward").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 16).frame(minHeight: 40)
                        .background(theme.accent.opacity(0.12), in: Capsule())
                        Text(budgetCharacterLine)
                            .font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("budget-character")
                Text(ar ? "على هذا الـ iPhone فقط" : "Stored only on this iPhone")
                    .font(GhafTypography.body(13, languageCode: languageCode, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $showPhotoMenu) { photoActionsSheet }
            .sheet(isPresented: $showBudgetCharacterInfo) { budgetCharacterSheet }
            .onDisappear(perform: discardProfileName)

            HStack(spacing: 8) {
                profileMetric(value: "\(streak)", title: ar ? "أيام متتالية" : "Logging streak")
                NavigationLink { GhafTransactionsView(settings: settings).ghafPushedBack(theme: theme, languageCode: languageCode) } label: {
                    profileMetric(value: "\(transactions.count)", title: ar ? "العمليات" : "Transactions")
                }.buttonStyle(.plain)
                NavigationLink { GhafAccountsView(settings: settings) } label: {
                    profileMetric(value: "\(activeAccountCount)", title: ar ? "الحسابات" : "Accounts")
                }.buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                Text(ar ? "الإنجازات" : "Milestones")
                    .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack(spacing: 8) {
                    ForEach(GhafLoggingStreak.milestones, id: \.self) { days in
                        Button { selectedMilestone = days } label: {
                          VStack(spacing: 6) {
                            Text("\(days)")
                                .font(GhafTypography.number(16, weight: .bold))
                                .foregroundStyle(streak >= days ? theme.accentContrast : theme.secondaryText)
                                .frame(width: 52, height: 52)
                                .background(streak >= days ? theme.accent : theme.secondaryText.opacity(0.12), in: Circle())
                            Text(ar ? "يوم" : "days")
                                .font(GhafTypography.body(12, languageCode: languageCode))
                                .foregroundStyle(theme.secondaryText)
                          }
                          .frame(maxWidth: .infinity)
                        }.buttonStyle(.ghafPress)
                         .accessibilityLabel(ar ? "إنجاز \(GhafLocalization.arabicDays(days))" : "\(days)-day milestone")
                    }
                }
                Text(ar ? "سجّل كل يوم عملية لا تنتظر المراجعة؛ وإذا فاتك يوم، يبدأ التسلسل من جديد. للمتعة فقط."
                        : "Log a transaction daily; entries awaiting review don’t count. Miss a day and the streak restarts. Just for fun.")
                    .font(GhafTypography.body(12, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .ghafCard(theme: theme)
            .sheet(isPresented: Binding(get: { selectedMilestone != nil }, set: { if !$0 { selectedMilestone = nil } })) {
                if let days = selectedMilestone { milestoneSheet(days: days, streak: streak) }
            }
            streakVoucherCard(streak: streak)
            placesCard
        }
    }

    private func refreshProfileStreakIfNeeded() {
        let key = "\(transactions.count)-\(router.ledgerRevision)"
        guard key != profileStreakKey else { return }
#if DEBUG
        (profileStreak, cachedPlaceSummaries) = GhafPerformanceProbe.measure("more-summary") {
            (
                GhafLoggingStreak.count(transactions.filter { !$0.needsReview }.map(\.date),
                                        through: GhafClock.now, calendar: Calendar.current),
                buildPlaceSummaries()
            )
        }
#else
        profileStreak = GhafLoggingStreak.count(transactions.filter { !$0.needsReview }.map(\.date),
                                               through: GhafClock.now, calendar: Calendar.current)
        cachedPlaceSummaries = buildPlaceSummaries()
#endif
        profileStreakKey = key
    }

    private func buildPlaceSummaries() -> [PlaceSummary] {
        guard let data = UserDefaults.standard.data(forKey: "ghaf.places.byTransaction"),
              let places = try? JSONDecoder().decode([String: SavedPlace].self, from: data),
              let month = Calendar.current.dateInterval(of: .month, for: GhafClock.now) else { return [] }
        let purchases = transactions.filter { $0.direction == "debit" && !$0.isReversal && month.contains($0.date) }
        let grouped = Dictionary(grouping: purchases.compactMap { transaction -> (String, GhafTransaction)? in
            guard let place = places[transaction.id.uuidString] else { return nil }
            let address = place.address?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            let area = address.count > 1 ? address[address.count - 2] : place.name
            return (area, transaction)
        }, by: \.0)
        return grouped.map { name, rows in
            var totals: [String: Decimal] = [:]
            for (_, row) in rows { totals[row.currency, default: 0] += row.amount }
            return PlaceSummary(name: name, count: rows.count, totals: totals)
        }
        // Row 13: ties were broken by dictionary order, so any refresh (e.g. changing sex) reshuffled the top 3.
        .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        .prefix(3).map { $0 }
    }

    private var placesCard: some View {
        let summaries = cachedPlaceSummaries
        return GhafProFeatureMask(isUnlocked: proUnlocked, theme: theme, languageCode: languageCode, action: { showProSheet = true }) {
          VStack(alignment: .leading, spacing: 12) {
            Label(ar ? "أماكن إنفاقك" : "Places you spent", systemImage: "mappin.and.ellipse")
                .font(GhafTypography.heading(18, languageCode: languageCode)).foregroundStyle(theme.primaryText)
            if summaries.isEmpty {
                Text(ar ? "تظهر الأماكن هنا بعد تسجيل عملية مع موقعها." : "Places appear here after a transaction is saved with a location.")
                    .font(GhafTypography.body(14, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
            } else {
                ForEach(summaries) { place in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name).font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
                            Text(ar ? "\(place.count) عملية" : "\(place.count) transactions").font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(place.totals.keys.sorted(), id: \.self) { code in
                                GhafMoneyLabel(amount: place.totals[code] ?? 0, currency: code, languageCode: languageCode, size: 14)
                                    .foregroundStyle(theme.primaryText)
                            }
                        }
                    }
                }
            }
        }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .ghafCard(theme: theme)
        }
        .accessibilityHint(ar ? "تُحفظ بيانات الأماكن على هذا الجهاز فقط." : "Place data stays on this iPhone.")
    }

    private func streakVoucherCard(streak: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ar ? "مكافآت الاستمرارية" : "Streak rewards")
                .font(GhafTypography.heading(18, languageCode: languageCode)).foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset - 6, to: GhafClock.now) ?? GhafClock.now
                    let logged = transactions.contains { Calendar.current.isDate($0.date, inSameDayAs: date) && !$0.needsReview }
                    VStack(spacing: 5) {
                        Text(date.formatted(.dateTime.weekday(.narrow).locale(GhafLocale.locale(identifier: languageCode))))
                            .font(GhafTypography.body(11, languageCode: languageCode, weight: .medium)).foregroundStyle(theme.secondaryText)
                        Circle().fill(logged ? theme.accent : theme.secondaryText.opacity(0.12)).frame(width: 28, height: 28)
                            .overlay { if logged { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(theme.accentContrast) } }
                    }.frame(maxWidth: .infinity)
                }
            }
            ForEach(Array([7, 30, 90].enumerated()), id: \.offset) { item in
                let days = item.element
                let percent = [10, 25, 50][item.offset]
                HStack(spacing: 10) {
                    Button { selectedMilestone = days } label: {
                        HStack(spacing: 10) {
                            Image(systemName: streak >= days ? "checkmark.seal.fill" : "lock.circle")
                                .foregroundStyle(streak >= days ? theme.accent : theme.secondaryText)
                            Text(ar ? "\(GhafLocalization.arabicDays(days)) · خصم \(percent)٪" : "\(days) days · \(percent)% off")
                                .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Spacer()
                    Button(ar ? "استرداد" : "Claim") { redeemingVoucher = true }
                        .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                        .foregroundStyle(theme.secondaryText).padding(.horizontal, 15).frame(minHeight: 40)
                        .background(theme.secondaryText.opacity(0.08), in: Capsule())
                        .disabled(!GhafFeatureFlags.appStoreAccount || streak < days)
                        .opacity(GhafFeatureFlags.appStoreAccount && streak >= days ? 1 : 0.4)
                }.frame(minHeight: 48)
            }
            Text(ar ? "تتوفر رموز الخصم مرة واحدة لكل إنجاز بعد إطلاق غاف في App Store." : "One-time offer codes will be available for each milestone when Ghaf is on the App Store.")
                .font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)
        }.padding(18).frame(maxWidth: .infinity).ghafCard(theme: theme)
    }

    private func milestoneSheet(days: Int, streak: Int) -> some View {
        ViewThatFits(in: .vertical) {
            milestoneContent(days: days, streak: streak)
            ScrollView { milestoneContent(days: days, streak: streak) }
        }
        .ghafBottomCard(theme: theme, languageCode: languageCode)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private func milestoneContent(days: Int, streak: Int) -> some View {
          VStack(spacing: 16) {
            let locked = streak < days
            let previous = [7, 30, 90].last { $0 < days }
            Image(systemName: locked ? "lock.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 36)).foregroundStyle(theme.accent)
                    Text(ar ? "إنجاز \(GhafLocalization.arabicDays(days))" : "\(days)-day milestone")
                .font(GhafTypography.heading(22, languageCode: languageCode)).foregroundStyle(theme.primaryText)
            Text(locked
                 ? (previous.map { ar ? "أكمل سلسلة \(GhafLocalization.arabicDays($0)) أولاً لتفتح خصماً أكبر. سلسلتك الآن \(GhafLocalization.arabicDays(streak))."
                                      : "Finish the \($0)-day streak first to unlock a bigger discount. Your streak is now \(streak) days." }
                    ?? (ar ? "سجّل عملية كل يوم لمدة \(GhafLocalization.arabicDays(days)) لتفتح هذا الخصم. سلسلتك الآن \(GhafLocalization.arabicDays(streak))."
                           : "Track your money \(days) days in a row to unlock this discount. Your streak is now \(streak) days."))
                 : (ar ? "سجّلت عملية كل يوم لمدة \(GhafLocalization.arabicDays(days)). أنت الآن في سلسلة من \(GhafLocalization.arabicDays(streak))."
                       : "You tracked your money for \(days) days in a row. Your streak is now \(streak) days."))
                .font(GhafTypography.body(15, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(ar ? "تم" : "Done") { selectedMilestone = nil }
                .ghafProminentButton(theme: theme, languageCode: languageCode)
          }
          .padding(.horizontal, 24).padding(.bottom, 16).frame(maxWidth: .infinity)
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
            Text(ar ? "يحدد «هذا الأسبوع» و«الأسبوع الماضي» في غاف AI والرسوم، وموعد الملخص الأسبوعي. الرئيسية تعرض آخر 7 أيام."
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

    private var mapsCard: some View {
        settingsCard(ar ? "تطبيق الخرائط" : "Maps app",
                     subtitle: ar ? "يفتح زر الاتجاهات هذا التطبيق." : "The Directions button opens this app.") {
            GhafMapsAppPicker(settings: settings)
                .onChange(of: settings.mapsAppPreference) { _, _ in
                    do { try modelContext.save() }
                    catch { modelContext.rollback(); prompt = .message(ar ? "تعذر حفظ الإعداد." : "Couldn't save this setting.") }
                }
        }
    }

    private var keypadCard: some View {
        settingsCard(ar ? "إدخال العمليات" : "Transaction entry",
                     subtitle: ar ? "اختر طريقة ظهور لوحة الأرقام عند إضافة عملية." : "Choose whether the number pad opens when you add a transaction.") {
            Toggle(isOn: Binding(get: { settings.showKeypadOnAdd }, set: { value in
                settings.showKeypadOnAdd = value
                do { try modelContext.save() }
                catch { modelContext.rollback(); prompt = .message(ar ? "تعذر حفظ الإعداد." : "Couldn't save this setting.") }
            })) {
                Text(ar ? "إظهار لوحة الأرقام عند الإضافة" : "Show keypad when adding")
                    .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
            }
            .toggleStyle(GhafToggleStyle(theme: theme, languageCode: languageCode))
            .frame(minHeight: 56)
            Toggle(isOn: $padMirrored) {
                Text(ar ? "لوحة أرقام من اليمين لليسار" : "Right-to-left keypad")
                    .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
            }
            .toggleStyle(GhafToggleStyle(theme: theme, languageCode: languageCode))
            .frame(minHeight: 56)
        }
    }

    private var soundCard: some View {
        settingsCard(ar ? "الأصوات" : "Sounds",
                     subtitle: ar ? "أصوات هادئة لتأكيد بعض الإجراءات داخل التطبيق." : "Quiet cues for a few in-app actions.") {
            Toggle(isOn: $inAppSounds) {
                Text(ar ? "أصوات التطبيق" : "In-app sounds")
                    .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
            }
            .toggleStyle(GhafToggleStyle(theme: theme, languageCode: languageCode))
            .frame(minHeight: 56)
        }
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
            GhafGlassPreview(theme: theme, arabic: ar)
            VStack(spacing: 0) {
                Toggle(ar ? "تأثير الزجاج" : "Glass effect", isOn: $glassEnabled)
                    .frame(minHeight: 56)
                glassDivider
                VStack(alignment: .leading, spacing: 10) {
                    Text(ar ? "الشدة" : "Intensity").foregroundStyle(theme.primaryText)
                    GhafSegmented(options: [("subtle", ar ? "خفيف" : "Subtle"), ("balanced", ar ? "متوازن" : "Balanced"), ("bold", ar ? "قوي" : "Bold")], selection: $glassIntensity, theme: theme, languageCode: languageCode)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.frame(maxWidth: .infinity).padding(.vertical, 10)
                .disabled(!glassEnabled)
            if reduceTransparency { Text(ar ? "الزجاج متوقف بسبب إعداد تسهيلات الاستخدام." : "Glass is off because Reduce Transparency is enabled.").font(.caption).foregroundStyle(theme.secondaryText) }
            if glassEnabled {
                glassDivider
                Toggle(ar ? "ملمس الحبيبات" : "Film grain", isOn: $glassGrain)
                    .frame(minHeight: 56)
                glassDivider
                Toggle(ar ? "توهج خلفي" : "Ambient glow", isOn: $glassGlow)
                    .frame(minHeight: 56)
                glassDivider
                Toggle(ar ? "يتحرك مع ميل الجهاز" : "Move with tilt", isOn: $glassTilt)
                    .frame(minHeight: 56)
                glassDivider
                VStack(alignment: .leading, spacing: 10) {
                    Text(ar ? "سماكة الحافة" : "Edge").foregroundStyle(theme.primaryText)
                    GhafSegmented(options: [("thin", ar ? "رفيعة" : "Thin"), ("medium", ar ? "متوسطة" : "Medium"), ("thick", ar ? "سميكة" : "Thick")], selection: $glassRim, theme: theme, languageCode: languageCode)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.frame(maxWidth: .infinity).padding(.vertical, 10)
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
                settingsField(languageCode == "ar" ? "مثال: 5000" : "e.g. 5000", text: $income, numeric: true)

                settingsLabel(languageCode == "ar" ? "الالتزامات الشهرية الثابتة" : "Fixed monthly commitments")
                settingsField(languageCode == "ar" ? "مثال: 1500" : "e.g. 1500", text: $commitments, numeric: true)

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
                .ghafSheetFrame(theme: theme)
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
        return [(ar ? "المصروف" : "Expenses", expenses), (ar ? "الدخل" : "Income", income), (ar ? "التحويلات" : "Transfers", transfers)]
    }

    private func categoryEditor(_ category: String) -> some View {
        let builtIn = CategoryTaxonomy.category(named: category) != nil
        return ScrollView {
          VStack(alignment: .leading, spacing: 16) {
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
                        .ghafDestructiveButton(theme: theme, languageCode: languageCode)
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
            if !settings.subcategories(of: category).isEmpty {
                settingsLabel(ar ? "الفئات الفرعية" : "Subcategories")
                ForEach(settings.subcategories(of: category), id: \.self) { subcategory in
                    HStack {
                        Text(GhafLocalization.category(subcategory, languageCode: languageCode))
                            .font(GhafTypography.body(14, languageCode: languageCode)).foregroundStyle(theme.primaryText)
                        Spacer()
                        Button(ar ? "حذف" : "Remove", role: .destructive) { subcategoryToRemove = subcategory }
                            .font(GhafTypography.body(12, languageCode: languageCode))
                            .frame(minHeight: 44)
                    }.frame(minHeight: 44)
                }
            }
        }
        .padding(GhafMetrics.gutter)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.background)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        }
        .padding(.vertical, 8)
        .confirmationDialog(ar ? "حذف هذه الفئة الفرعية؟" : "Remove this subcategory?",
                            isPresented: Binding(get: { subcategoryToRemove != nil }, set: { if !$0 { subcategoryToRemove = nil } }),
                            titleVisibility: .visible) {
            Button(ar ? "حذف" : "Remove", role: .destructive) {
                if let subcategory = subcategoryToRemove {
                    settings.deleteSubcategory(subcategory, from: category)
                    try? modelContext.save()
                }
                subcategoryToRemove = nil
            }
        } message: {
            Text(ar ? "تبقى العمليات المسجلة بها كما هي." : "Transactions already using it keep their category.")
        }
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
        let existingCategories = settings.categories
        var deleted = settings.deletedCategoryKeys
        deleted.insert(CategoryTaxonomy.deletionKey(category: old))
        settings.deletedCategoryKeys = deleted
        settings.categories = existingCategories.map { $0 == old ? new : $0 }
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
        guard let month = Calendar.current.dateInterval(of: .month, for: GhafClock.now) else { return [:] }
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
                Label(languageCode == "ar" ? "إنشاء نسخة JSON" : "Create JSON backup", systemImage: "square.and.arrow.up")
            }
            .ghafProminentButton(theme: theme, languageCode: languageCode)
            Text(languageCode == "ar" ? "صدّر الحسابات والعمليات والاشتراكات والإعدادات إلى ملف يمكنك حفظه أو مشاركته." : "Export accounts, transactions, subscriptions and settings to a file you can save or share.")
                .font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button { showImportSheet = true } label: {
                settingsActionRow(languageCode == "ar" ? "استيراد بيانات" : "Import data", detail: languageCode == "ar" ? "نسخة غاف أو نسخة من تطبيق ميزانية آخر" : "A Ghaf backup or a backup from another budgeting app", icon: "square.and.arrow.down")
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
        arabicName = settings.arabicName
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
        settings.arabicName = arabicName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard settings.categories.count > 1 else { return }

        settings.deleteCategory(category)
        categoryBudgetTexts.removeValue(forKey: category)

        var budgets = settings.categoryBudgets
        budgets.removeValue(forKey: category)
        settings.categoryBudgets = budgets
        try? modelContext.save()
    }

    private func createBackup() {
        do {
            backupURL = try GhafBackupService.export(context: modelContext)
            showBackupShare = true
        } catch {
            prompt = .message(languageCode == "ar" ? "تعذر إنشاء النسخة الاحتياطية." : "Could not create the backup.")
        }
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
                    ? "تم استيراد \(walletCount) و\(entryCount) من تطبيق ميزانية آخر. تمت مطابقة الأرصدة مع الملف المصدر."
                    : "Imported \(result.accountsImported) accounts and \(result.transactionsImported) entries from another budgeting app. Balances match the source file."

                if result.budgetsNotImported > 0 {
                    message += languageCode == "ar"
                        ? " لم تُنقل \(budgetCount) لأن غاف لا يدعم استيراد هذه الميزانيات حالياً."
                        : " \(result.budgetsNotImported) budgets were not imported because Ghaf does not yet support this budget format."
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
                let result = try GhafBackupService.restore(from: url, context: modelContext)
                pendingImportURL = nil
                prompt = .message(languageCode == "ar"
                    ? "اكتمل الاستيراد · الحسابات: \(result.accountsImported) · المعاملات: \(result.transactionsImported) · الاشتراكات: \(result.subscriptionsImported)"
                    : "Import complete · Accounts: \(result.accountsImported) · Transactions: \(result.transactionsImported) · Subscriptions: \(result.subscriptionsImported)")
            }
        } catch {
            prompt = .message(languageCode == "ar"
                ? "تعذر استيراد الملف. لم يتم اعتماد الاستيراد. التفاصيل: \(error.localizedDescription)"
                : "Could not import the file. Details: \(error.localizedDescription.replacingOccurrences(of: "Expend", with: "another budgeting app"))")
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

private struct GhafProBannerGlow: View {
    let theme: GhafTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    private var motionIsEnabled: Bool {
#if DEBUG
        !reduceMotion && !GhafScreenshotFixture.snapshotTestingEnabled
#else
        !reduceMotion
#endif
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isVisible || !motionIsEnabled)) { timeline in
            let phase = motionIsEnabled ? timeline.date.timeIntervalSinceReferenceDate : 0
            let x = Float(sin(phase * 0.24))
            let y = Float(cos(phase * 0.19))
            if #available(iOS 18.0, *) {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5 + 0.08 * x, 0], [1, 0],
                    [0, 0.5 + 0.07 * y], [0.5 + 0.12 * x, 0.5 + 0.10 * y], [1, 0.5 - 0.07 * x],
                    [0, 1], [0.5 - 0.08 * y, 1], [1, 1]
                ], colors: [
                    theme.accent.opacity(0.56), theme.glow.opacity(0.74), theme.surface,
                    theme.glow.opacity(0.82), theme.accent.opacity(0.34), theme.surface,
                    theme.surface, theme.accent.opacity(0.45), theme.glow.opacity(0.62)
                ])
            } else {
                LinearGradient(colors: [theme.accent, theme.glow, theme.surface, theme.accent.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

private struct GhafSettingsShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = UIView()
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct GhafCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, dismiss: dismiss) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction
        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) { self.onImage = onImage; self.dismiss = dismiss }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onImage(image) }
            dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { dismiss() }
    }
}


private struct GhafEditingCategory: Identifiable {
    let name: String
    var id: String { name }
}

/// NavigationLink builds its destination when the link is created, so More rebuilt every subpage (profile,
/// streak, places…) on each render. This defers building the page until the destination is shown.
private struct GhafDeferredView<Content: View>: View {
    let build: () -> Content
    init(@ViewBuilder _ build: @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}

/// Row 10: progress toward the next streak tier (7, 30, 100, 365 days) as a glowing accent ring around the avatar.
private struct GhafStreakRing: View {
    let streak: Int
    let theme: GhafTheme
    let ar: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var target: Double {
        let tiers = [0] + GhafLoggingStreak.milestones
        guard let next = tiers.first(where: { $0 > streak }), let prev = tiers.last(where: { $0 <= streak }) else { return 1 }
        return Double(streak - prev) / Double(next - prev)
    }

    var body: some View {
        // Owner #49: clock-driven so the motion never stops (an onAppear repeatForever froze after returning to Profile).
        TimelineView(.animation(paused: reduceMotion || streak == 0)) { context in
            ring(time: context.date.timeIntervalSinceReferenceDate)
        }
        .onAppear { set(target) }
        .onChange(of: target) { _, value in set(value) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ar ? "سلسلة \(streak) يوماً" : "\(streak) day streak")
        .accessibilityHidden(streak == 0)
    }

    private func ring(time: Double) -> some View {
        let sweep = (time / 4.5).truncatingRemainder(dividingBy: 1)
        let breath = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(time * 2 * .pi / 3.2)
        return ZStack {
            Circle().stroke(theme.accent.opacity(0.14), lineWidth: 5)
            Circle().trim(from: 0, to: max(shown, streak > 0 ? 0.02 : 0))
                .stroke(AngularGradient(colors: [theme.accent.opacity(0.45), theme.accent], center: .center, startAngle: .zero, endAngle: .degrees(360 * max(shown, 0.02))),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.accent.opacity(0.35 + 0.3 * breath), radius: 4 + 5 * breath)
            // Row 10: a soft light travels round the filled arc so the ring feels alive (theme tint kept).
            if !reduceMotion && streak > 0 {
                Circle().trim(from: 0, to: 0.12)
                    .stroke(AngularGradient(colors: [.white.opacity(0), .white.opacity(0.85), .white.opacity(0)], center: .center,
                                            startAngle: .zero, endAngle: .degrees(43)),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .blur(radius: 1.2)
                    .rotationEffect(.degrees(-90 + sweep * 360))
                    .mask(Circle().trim(from: 0, to: max(shown, 0.02)).stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90)))
            }
        }
    }

    private func set(_ value: Double) {
        if reduceMotion { shown = value } else { withAnimation(.easeOut(duration: 0.6)) { shown = value } }
    }
}
