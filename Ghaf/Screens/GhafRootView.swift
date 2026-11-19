import SwiftUI
import SwiftData
import LocalAuthentication
import UserNotifications
import AVFoundation
import Speech
import UniformTypeIdentifiers

struct GhafRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settings: [GhafSettings]

    @State private var showAutomationIntro = false
    @State private var appliedLanguage = ""
    @State private var showLaunch = true
    @State private var launchHasStarted = false
    @State private var isUnlocked = true
    @State private var authenticationMessage: String?
    @State private var authenticationInProgress = false

    private var requiresAuthentication: Bool {
        settings.first?.hasCompletedOnboarding == true &&
        settings.first?.biometricLockEnabled == true
    }

    private var languageCode: String {
        settings.first?.languageCode ?? "en"
    }

    var body: some View {
        ZStack {
            rootContent
                .id(appliedLanguage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear.ignoresSafeArea())

            if showLaunch {
                GhafWelcomeLaunchScreen(settings: settings.first)
                    .transition(.opacity)
                    .zIndex(10)
            }

            if requiresAuthentication && !isUnlocked && !showLaunch {
                authenticationLockScreen
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .toggleStyle(GhafToggleStyle(theme: GhafTheme.resolve(name: settings.first?.themeName ?? "Abu Dhabi", appearanceMode: settings.first?.appearanceMode ?? "System", systemIsDark: systemColorScheme == .dark), languageCode: languageCode))
        .environment(\.locale, Locale(identifier: languageCode))
        .environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear.ignoresSafeArea())
        .scrollBounceBehavior(.basedOnSize)
        // UIKit parts (navigation bars, back arrows, swipe-back, menus, pickers) ignore SwiftUI's
        // direction; set theirs first, then rebuild the screens so they pick it up.
        .onChange(of: languageCode, initial: true) { _, code in
            UIView.appearance().semanticContentAttribute = code == "ar" ? .forceRightToLeft : .forceLeftToRight
            appliedLanguage = code
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: beginLaunch)
        .onChange(of: scenePhase) { _, phase in
            // Leaving Ghaf: refresh the morning/evening/weekly notes with today's numbers.
            if phase == .background {
                GhafDigestNotifications.reschedule(context: modelContext)
                GhafWidgetSync.refresh(context: modelContext)
            }
            if phase == .active {
                // Also on open, so widgets get numbers even if Ghaf is never sent to the background cleanly.
                GhafWidgetSync.refresh(context: modelContext)
                Task { await GhafWidgetSync.endStale() }
            }
            if phase == .active { Task { await GhafExchangeRates.refreshIfStale() } }
            if phase != .active {
                if requiresAuthentication { isUnlocked = false }
            } else if requiresAuthentication {
                authenticateUser()
            }
        }
        .onChange(of: settings.first?.biometricLockEnabled) { _, enabled in
            if enabled == true {
                isUnlocked = false
                authenticateUser()
            } else {
                isUnlocked = true
                authenticationMessage = nil
            }
        }
        .onChange(of: settings.first?.hasCompletedOnboarding) { _, completed in
            if completed == true {
                presentAutomationIntroIfNeeded()
            }
        }
        .sheet(isPresented: $showAutomationIntro, onDismiss: markAutomationIntroSeen) {
            if let currentSettings = settings.first {
                NavigationStack {
                    GhafAutomationGuideView(settings: currentSettings)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(currentSettings.languageCode == "ar" ? "تم" : "Done") {
                                    showAutomationIntro = false
                                }
                            }
                        }
                }
            }
        }
    }

    private var authenticationLockScreen: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "faceid")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.primary)
                Text(languageCode == "ar" ? "غاف محمي" : "Ghaf is protected")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(languageCode == "ar"
                    ? "أكد هويتك للوصول إلى بياناتك المالية."
                    : "Authenticate to access your financial information.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let authenticationMessage {
                    Text(authenticationMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button(action: authenticateUser) {
                    Text(languageCode == "ar" ? "فتح غاف" : "Unlock Ghaf")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 30)
                        .frame(height: 48)
                        .background(Color.accentColor, in: Capsule())
                }
                .padding(.top, 4)
            }
            .padding(32)
            .frame(maxWidth: 360)
        }
        .environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
    }

    private func authenticateUser() {
        guard requiresAuthentication, !isUnlocked, !authenticationInProgress else { return }
        authenticationInProgress = true
        let context = LAContext()
        context.localizedCancelTitle = languageCode == "ar" ? "إلغاء" : "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationInProgress = false
            authenticationMessage = languageCode == "ar"
                ? "تعذر بدء المصادقة. تحقق من إعدادات رمز دخول الجهاز."
                : "Authentication is unavailable. Check your device passcode settings."
            return
        }

        let reason = languageCode == "ar"
            ? "افتح غاف للوصول إلى بياناتك المالية."
            : "Unlock Ghaf to access your financial information."
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evaluationError in
            Task { @MainActor in
                authenticationInProgress = false
                if success {
                    isUnlocked = true
                    authenticationMessage = nil
                } else {
                    isUnlocked = false
                    authenticationMessage = evaluationError?.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if let currentSettings = settings.first {
            if currentSettings.hasCompletedOnboarding {
                GhafTabView(settings: currentSettings)
            } else {
                GhafOnboardingView(settings: currentSettings)
            }
        } else {
            ProgressView()
                .tint(.white)
                .task {
                    do {
                        _ = try GhafPersistence.settings(in: modelContext)
                    } catch {
                        print("Ghaf initialization error: \(error)")
                    }
                }
        }
    }

    private func beginLaunch() {
        guard !launchHasStarted else { return }
        launchHasStarted = true
        launchStartedAt = .now

        Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(2.4)
            while settings.first == nil, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(40)) }
            let minimum = settings.first?.hasCompletedOnboarding == true ? 1.6 : 2.6
            let elapsed = Date.now.timeIntervalSince(launchStartedAt)
            if elapsed < minimum { try? await Task.sleep(for: .seconds(minimum - elapsed)) }
            withAnimation(.easeOut(duration: 0.42)) {
                showLaunch = false
            }
            if requiresAuthentication {
                isUnlocked = false
                authenticateUser()
            }
            presentAutomationIntroIfNeeded()
        }
    }

    @State private var launchStartedAt = Date.now

    private func presentAutomationIntroIfNeeded() {
        guard let currentSettings = settings.first,
              currentSettings.hasCompletedOnboarding,
              !currentSettings.hasSeenAutomationIntro else {
            return
        }
        showAutomationIntro = true
    }

    private func markAutomationIntroSeen() {
        guard let currentSettings = settings.first,
              !currentSettings.hasSeenAutomationIntro else {
            return
        }
        currentSettings.hasSeenAutomationIntro = true
        if UserDefaults.standard.double(forKey: GhafAutomationStatus.setupCompletedKey) == 0 {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: GhafAutomationStatus.setupCompletedKey)
        }
        try? modelContext.save()
    }
}

// MARK: - Main Tab Navigation

@Observable
final class GhafTabRouter {
    var selectedTab = 0
    /// Bumped when Home is tapped while already open; Home cycles Daily, Weekly, Monthly.
    var homeReselects = 0
}

struct GhafTabView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ghafGlass) private var glass
    @Query(filter: #Predicate<GhafTransaction> { $0.needsReview }) private var reviewItems: [GhafTransaction]
    /// Current frame of the Ghaf AI icon's tap animation (0 = at rest).
    @State private var aiFrame = 0
    /// A stable reference in the environment: switching tabs never changes the tabs' inputs.
    @State private var router = GhafTabRouter()
    /// Decoded once, not on every tab switch, so category icons are not invalidated needlessly.
    @State private var categoryMeta: [String: GhafCategoryMeta] = [:]

    let settings: GhafSettings

    var body: some View {
        let theme = GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
        let reviewCount = reviewItems.count

        // Tapping Home again while it's open switches its period instead of doing nothing.
        let selection = Binding(get: { router.selectedTab }, set: { tab in
            if tab == 0 && router.selectedTab == 0 { router.homeReselects += 1 }
            router.selectedTab = tab
        })
        TabView(selection: selection) {
            GhafHomeView(settings: settings).ghafTabEntrance(selected: router.selectedTab == 0, initialTab: true, reduceMotion: reduceMotion)
                .tabItem { tabIcon(Image(systemName: "house.fill"), settings.languageCode == "ar" ? "الرئيسية" : "Home") }
                .tag(0)

            GhafTransactionsView(settings: settings).ghafTabEntrance(selected: router.selectedTab == 3, initialTab: false, reduceMotion: reduceMotion)
                .tabItem { tabIcon(Image(systemName: "arrow.left.arrow.right"), settings.languageCode == "ar" ? "العمليات" : "Transactions") }
                .badge(reviewCount)
                .tag(3)

            GhafAIView(settings: settings).ghafTabEntrance(selected: router.selectedTab == 1, initialTab: false, reduceMotion: reduceMotion)
                // A full-colour Ghaf tree as the tab's own icon: unlike the monochrome tabs, and placed by iOS
                // exactly where the tab is on every iPhone and tab bar layout.
                .tabItem {
                    tabIcon(Image(uiImage: GhafAITabIcon.image(theme: theme, selected: router.selectedTab == 1, frame: aiFrame)),
                            settings.languageCode == "ar" ? "غاف AI" : "Ghaf AI")
                }
                .tag(1)

            GhafStatsView(settings: settings).ghafTabEntrance(selected: router.selectedTab == 2, initialTab: false, reduceMotion: reduceMotion)
                .tabItem { tabIcon(Image(systemName: "chart.bar.xaxis"), settings.languageCode == "ar" ? "الإحصائيات" : "Stats") }
                .tag(2)

            GhafSettingsView(settings: settings).ghafTabEntrance(selected: router.selectedTab == 4, initialTab: false, reduceMotion: reduceMotion)
                .tabItem { tabIcon(Image(systemName: "ellipsis"), settings.languageCode == "ar" ? "المزيد" : "More") }
                .tag(4)
        }
        .modifier(GhafTabBarGlass(enabled: glass.enabled))
        .tint(theme.accent)
        .sensoryFeedback(.selection, trigger: router.selectedTab)
        .task(id: router.selectedTab) {
            // Opening Ghaf AI plays the tree's grow-and-sway once, frame by frame (tab icons can't animate otherwise).
            guard router.selectedTab == 1, !reduceMotion else { return }
            for frame in 1...GhafAITabIcon.frameCount {
                aiFrame = frame
                try? await Task.sleep(for: .milliseconds(28))
                if Task.isCancelled { break }
            }
            aiFrame = 0
        }
        .environment(router)
        .environment(\.ghafCategoryMeta, categoryMeta)
        .onChange(of: settings.categoryMetaJSON, initial: true) { categoryMeta = settings.categoryMeta }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .preferredColorScheme(
            settings.appearanceMode == "Dark" ? .dark :
                settings.appearanceMode == "Light" ? .light : nil
        )
    }
}

private struct GhafTabBarGlass: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) { content }
        else if enabled { content.toolbarBackground(.ultraThinMaterial, for: .tabBar) }
        else { content }
    }
}

private struct GhafTabEntrance: ViewModifier {
    let selected: Bool
    let initialTab: Bool
    let reduceMotion: Bool
    @State private var visible = false
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: reduceMotion || visible ? 0 : 8)
            .onAppear {
                appeared = true
                if initialTab { visible = true }
                else if selected { withAnimation(.easeOut(duration: 0.24)) { visible = true } }
            }
            .onChange(of: selected) { _, isSelected in
                guard appeared else { return }
                if isSelected {
                    withAnimation(.easeOut(duration: 0.24)) { visible = true }
                } else {
                    visible = false
                }
            }
    }
}

private extension View {
    func ghafTabEntrance(selected: Bool, initialTab: Bool, reduceMotion: Bool) -> some View {
        modifier(GhafTabEntrance(selected: selected, initialTab: initialTab, reduceMotion: reduceMotion))
    }
}

extension GhafTabView {
    /// Tabs show icons only; the title is still what VoiceOver reads.
    fileprivate func tabIcon(_ image: Image, _ title: String) -> some View {
        image.accessibilityLabel(title)
    }
}

// MARK: - Onboarding

/// Intro illustration built from shapes and SF Symbols: a glowing disc, a hero glyph,
/// and three orbiting badges that drift gently (still under Reduce Motion).
struct GhafOnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme

    let settings: GhafSettings

    @State private var step = 0
    @State private var languageCode = "en"
    @State private var showAutomationGuide = false
    @State private var name = ""
    @State private var currency = "AED"
    @State private var income = ""
    @State private var commitments = ""
    @State private var balanceSetupMode = "zero"
    // Start empty: don't silently create a zero-balance cash wallet for users
    // who only want to track their bank accounts and cards.
    @State private var accountDrafts: [GhafAccountDraft] = []
    @State private var salaryEnabled = false
    @State private var salaryDay = 28
    @State private var salaryAmountText = ""
    @State private var salaryReminderEnabled = true
    @State private var salaryAccountDraftID: UUID?
    @State private var accountSetupError = false
    @State private var showBackupImporter = false
    @State private var backupImportError: String?

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private let currencies = [
        "AED", "SAR", "KWD", "BHD", "OMR", "QAR"
    ]

    init(settings: GhafSettings) {
        self.settings = settings
        _languageCode = State(initialValue: settings.languageCode)
        _name = State(initialValue: settings.userName)
        _currency = State(initialValue: settings.currency)
        _income = State(initialValue: GhafFormat.decimal(settings.monthlyIncome))
        _commitments = State(initialValue: GhafFormat.decimal(settings.fixedCommitments))
        _salaryAmountText = State(initialValue: GhafFormat.decimal(settings.monthlyIncome))
    }

    private let stepCount = 8
    /// Steps 1-4 are full-bleed story cards; the rest are forms.
    private var isStory: Bool { (1...4).contains(step) }

    var body: some View {
        Group {
            if isStory { storyBody } else { formBody }
        }
        .onChange(of: languageCode) { _, newValue in
            settings.languageCode = newValue
            try? modelContext.save()
        }
        .sheet(isPresented: $showAutomationGuide, onDismiss: {
            settings.hasSeenAutomationIntro = true
            if UserDefaults.standard.double(forKey: GhafAutomationStatus.setupCompletedKey) == 0 {
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: GhafAutomationStatus.setupCompletedKey)
            }
            try? modelContext.save()
        }) {
            NavigationStack {
                GhafAutomationGuideView(settings: settings)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(localized("Done", "تم")) { showAutomationGuide = false }
                        }
                    }
            }
        }
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                try GhafBackupService.restore(from: url, context: modelContext)
                if let restored = try modelContext.fetch(FetchDescriptor<GhafSettings>()).first {
                    restored.hasCompletedOnboarding = true
                    try modelContext.save()
                }
            } catch {
                backupImportError = error.localizedDescription
            }
        }
        .alert(localized("Could not import backup", "تعذر استيراد النسخة"), isPresented: Binding(
            get: { backupImportError != nil }, set: { if !$0 { backupImportError = nil } }
        )) {
            Button(localized("OK", "حسناً"), role: .cancel) { backupImportError = nil }
        } message: { Text(backupImportError ?? "") }
    }

    private var formBody: some View {
        VStack(spacing: 0) {
            // Progress: one capsule per step, the current one stretched.
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? theme.accent : theme.secondaryText.opacity(0.2))
                        .frame(width: index == step ? 26 : 8, height: 8)
                }
            }
            .animation(.snappy(duration: 0.3), value: step)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localized("Step \(step + 1) of \(stepCount)", "الخطوة \(step + 1) من \(stepCount)"))

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        if step == 0 {
                            languageSelectionPage
                        } else if step == 5 {
                            setupPage
                        } else if step == 6 {
                            accountsAndSalaryPage
                        } else {
                            connectionPage
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
                    .padding(24)
                    .frame(minHeight: geometry.size.height, alignment: .topLeading)
                }
            }

            VStack(spacing: 10) {
                Button(step == 7 ? localized("Start using Ghaf", "ابدأ استخدام غاف") : localized("Continue", "متابعة")) {
                    withAnimation(.snappy) { advance() }
                }
                .ghafProminentButton(theme: theme, languageCode: languageCode)

                if step > 0 {
                    Button(localized("Back", "رجوع")) { withAnimation(.snappy) { step -= 1 } }
                        .font(GhafTypography.body(14, languageCode: languageCode, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .background(theme.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }

    // MARK: Story cards

    private struct StoryCard {
        let eyebrow: String
        let title: String
        let body: String
        let colors: [Color]
        var symbol: String? = nil
    }

    private var storyCard: StoryCard {
        switch step {
        case 1: StoryCard(eyebrow: localized("Welcome to Ghaf · Made in the UAE", "أهلاً بك في غاف · صُنع في الإمارات"),
                          title: localized("Your money,\nclearly.", "فلوسك،\nبكل وضوح."),
                          body: localized("Every account, card and dirham of cash in one calm place, in your language and currency.",
                                          "كل حساباتك وبطاقاتك وكاشك في مكان واحد، بلغتك وعملتك."),
                          colors: brandNight)
        case 2: StoryCard(eyebrow: localized("Automatic", "تلقائي"),
                          title: localized("Bank alerts\nlog themselves.", "رسايل البنك\nتسجّل نفسها."),
                          body: localized("Install Ghaf's shortcut once: purchases are recorded, ads and OTPs are ignored. Cash stays a quick entry.",
                                          "ثبّت اختصار غاف مرة وحدة: تنسجّل المشتريات، وتنتجاهل الإعلانات ورموز التحقق. الكاش يبقى إدخال سريع."),
                          colors: brandNight)
        case 3: StoryCard(eyebrow: "Ghaf AI",
                          title: localized("Ask in Arabic\nor English.", "اسأله بالعربي\nأو بالإنجليزي."),
                          body: localized("\"How much did I spend this week?\" Ghaf answers from your own records, never a guess.",
                                          "«كم صرفت هالأسبوع؟» غاف يجاوبك من سجلك أنت، مب من تخمين."),
                          colors: brandNight)
        default: StoryCard(eyebrow: localized("Private by design", "الخصوصية أولاً"),
                           title: localized("A few permissions.", "بعض الأذونات."),
                           body: localized("Your records stay on this iPhone. iOS asks for each permission next; change them anytime in Settings.",
                                           "سجلاتك تبقى على جهازك. iOS بيطلب كل إذن الحين، وتقدر تغيّرها متى ما تبي من الإعدادات."),
                           colors: brandNight,
                           symbol: "lock.shield")
        }
    }

    /// The feature each card talks about, drawn with Ghaf's own pieces above the text.
    @ViewBuilder
    private var storyVisual: some View {
        switch step {
        case 1:
            ZStack {
                ForEach(Array(["mashreq-neo-cashback-card-product-card-360x220", "mbank-jaywan-debit", "cash-aed-100"].enumerated()), id: \.offset) { index, id in
                    GhafCardFace(account: nil, design: GhafCardDesign(rawValue: id), width: 250)
                        .rotationEffect(.degrees(Double(index - 1) * 9))
                        .offset(x: CGFloat(index - 1) * 34, y: CGFloat(index) * 26)
                }
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill").font(.system(size: 13, weight: .bold))
                    GhafMoneyLabel(amount: 12_450, currency: "AED", languageCode: languageCode, size: 18, hidden: false)
                }
                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(storyInk, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                .offset(x: languageCode == "ar" ? -60 : 60, y: 150)
            }
        case 2:
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(red: 0.95, green: 0.52, blue: 0.18))
                        .frame(width: 38, height: 38)
                        .overlay(Text("M").font(.system(size: 18, weight: .black)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mashreq").font(.system(size: 14, weight: .bold))
                        Text(localized("Purchase of AED 45.00 at Carrefour was made with card ending 1234.",
                                       "تم شراء بمبلغ 45.00 درهم لدى كارفور ببطاقتك المنتهية بـ 1234."))
                            .font(.system(size: 13)).lineLimit(2)
                    }
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                }
                .padding(14)
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Image(systemName: "arrow.down").font(.system(size: 20, weight: .bold)).foregroundStyle(storyInk.opacity(0.7))
                HStack(spacing: 12) {
                    GhafCategoryIcon(category: "Groceries", tint: storyInk, theme: theme)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Carrefour", "كارفور")).font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                        Text(localized("Groceries · Mashreq", "بقالة · المشرق")).font(GhafTypography.body(12, languageCode: languageCode)).opacity(0.7)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.55))
                }
                .foregroundStyle(storyInk)
                .padding(14)
                .background(storyInk.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(.horizontal, 24)
        case 3:
            VStack(spacing: 12) {
                Text(localized("How much did I spend this week?", "كم صرفت هالأسبوع؟"))
                    .font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(storyInk, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                VStack(alignment: .leading, spacing: 12) {
                    Text(localized("You spent AED 482 this week, mostly on your car.", "صرفت ٤٨٢ درهم هالأسبوع، أكثرها على السيارة."))
                        .font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                    HStack(alignment: .bottom, spacing: 7) {
                        ForEach(Array([0.35, 0.6, 0.25, 0.9, 0.5, 0.3, 0.7].enumerated()), id: \.offset) { index, value in
                            Capsule().fill(storyInk.opacity(index == 3 ? 1 : 0.4)).frame(width: 16, height: 70 * value)
                        }
                    }
                    .frame(height: 70, alignment: .bottom)
                }
                .foregroundStyle(storyInk)
                .padding(16)
                .background(storyInk.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
        default:
            EmptyView()
        }
    }

    /// The first card asks to sign in; accounts are not available yet, so "Skip for now" continues.
    private var signInPanel: some View {
        VStack(spacing: 12) {
            Text(localized("Ready to start?", "جاهز تبدأ؟"))
                .font(GhafTypography.heading(18, languageCode: languageCode))
            Button {} label: {
                Label(localized("Continue with Apple", "المتابعة باستخدام Apple"), systemImage: "apple.logo")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 56)
            }
            .ghafProminentButton(theme: theme, languageCode: languageCode)
            .disabled(true)
            Button { showBackupImporter = true } label: {
                Label(localized("Import Ghaf backup", "استيراد نسخة غاف الاحتياطية"), systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity).frame(height: 56)
            }
            .ghafGlassButton(theme: theme, languageCode: languageCode)
            if let backupImportError {
                Text(backupImportError).font(GhafTypography.body(13, languageCode: languageCode)).foregroundStyle(.red)
            }
            Text(localized("Ghaf accounts arrive soon. Until then everything stays on this iPhone.",
                           "حسابات غاف قريباً. لين ذاك الوقت كل شي يبقى على جهازك."))
                .font(GhafTypography.body(12, languageCode: languageCode))
                .multilineTextAlignment(.center)
                .opacity(0.7)
            Button(localized("Skip for now", "تخطَّ الآن")) { withAnimation(.snappy) { advance() } }
                .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                .frame(minHeight: 44)
        }
        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
        .padding(18)
        .background(storyInk, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private let storyInk = Color(red: 0.97, green: 0.94, blue: 0.89)

    /// Every welcome card uses the theme's own night palette, the same colours as the app in dark mode,
    /// so Ghaf looks like one brand from the first screen on. The light shifts across cards; the colours don't.
    private var brandNight: [Color] {
        let night = GhafTheme.resolve(name: settings.themeName, appearanceMode: "Dark", systemIsDark: true)
        return [night.background, night.accent.opacity(0.85)]
    }

    private var storyBody: some View {
        let card = storyCard
        // The artwork is a background so a fill-cropped image can never widen the layout and push text off-screen;
        // the text scrolls on small screens or large text sizes instead of being cut off.
        return GeometryReader { geometry in
            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 0)
                if step == 4 { permissionList }
                if true {
                Text(card.eyebrow)
                    .font(GhafTypography.body(15, languageCode: languageCode))
                    .foregroundStyle(storyInk.opacity(0.75))
                Text(card.title)
                    .font(GhafTypography.display(36, languageCode: languageCode))
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(storyInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.body)
                    .font(GhafTypography.body(16, languageCode: languageCode))
                    .foregroundStyle(storyInk.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 5) {
                    ForEach(1...4, id: \.self) { index in
                        Capsule().fill(storyInk.opacity(index == step ? 1 : 0.35))
                            .frame(width: index == step ? 24 : 10, height: 3)
                    }
                }
                .padding(.top, 6)
                .accessibilityHidden(true)
                Group {
                    if step == 1 { signInPanel } else { storyControls }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(width: geometry.size.width, alignment: .leading)
            .frame(minHeight: geometry.size.height, alignment: .bottom)
            .id(step)
            .transition(.opacity.combined(with: .offset(y: 16)))
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { storyBackground(card) }
        .animation(.snappy(duration: 0.4), value: step)
    }

    @ViewBuilder
    private func storyBackground(_ card: StoryCard) -> some View {
        ZStack {
            LinearGradient(colors: card.colors, startPoint: .top, endPoint: .bottom)
            // A soft light source, then a scrim so the text always reads.
            RadialGradient(colors: [card.colors[1].opacity(0.55), .clear],
                           center: .init(x: [0.3, 0.7, 0.3, 0.7][max(0, min(3, step - 1))], y: 0.32),
                           startRadius: 0, endRadius: 360)
                .allowsHitTesting(false)
            AnyView(storyVisual)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 90)
                .accessibilityHidden(true)
            if let symbol = card.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 190, weight: .ultraLight))
                    .foregroundStyle(storyInk.opacity(0.1))
                    .offset(x: 70, y: -170)
                    .accessibilityHidden(true)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var storyControls: some View {
        HStack(spacing: 12) {
            // The permission card offers only the button that opens the system alerts (HIG privacy, pre-alert screens).
            if step != 4 {
                Button { withAnimation(.snappy) { step -= 1 } } label: {
                    Image(systemName: languageCode == "ar" ? "arrow.right" : "arrow.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 56, height: 56)
                        .overlay(Circle().stroke(storyInk.opacity(0.45), lineWidth: 1))
                }
                .foregroundStyle(storyInk)
                .accessibilityLabel(localized("Back", "رجوع"))
            }
            Button {
                if step == 4 {
                    Task {
                        await requestPermissions()
                        withAnimation(.snappy) { step = 5 }
                    }
                } else {
                    withAnimation(.snappy) { advance() }
                }
            } label: {
                HStack {
                    Text(step == 1 ? localized("Start", "ابدأ") : localized("Continue", "متابعة"))
                        .font(GhafTypography.body(17, languageCode: languageCode, weight: .semibold))
                    Spacer()
                    Image(systemName: languageCode == "ar" ? "arrow.left" : "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(storyInk, in: Capsule())
                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
            }
            .buttonStyle(.ghafPress)
        }
    }

    private var permissionList: some View {
        VStack(alignment: .leading, spacing: 16) {
            permissionRow("bell.badge.fill", localized("Notifications", "الإشعارات"),
                          localized("Subscription reminders and transactions to review.", "تذكير الاشتراكات والعمليات التي تحتاج مراجعة."))
            permissionRow("mic.fill", localized("Microphone", "الميكروفون"),
                          localized("Say a purchase instead of typing it.", "قل عمليتك بدلاً من كتابتها."))
            permissionRow("waveform", localized("Speech recognition", "التعرّف على الكلام"),
                          localized("Turns your voice into text for Ghaf.", "يحوّل صوتك إلى نص لغاف."))
        }
        .padding(18)
        .background(storyInk.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.bottom, 10)
    }

    private func permissionRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(storyInk.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                Text(detail).font(GhafTypography.body(13, languageCode: languageCode)).opacity(0.75)
            }
        }
        .foregroundStyle(storyInk)
        .accessibilityElement(children: .combine)
    }

    /// Asked once, in order, after the explanation card. Each call shows the system alert only the first time.
    private func requestPermissions() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        _ = await AVAudioApplication.requestRecordPermission()
        _ = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private var languageSelectionPage: some View {
        VStack(spacing: 22) {
            Image(systemName: "globe").font(.system(size: 44, weight: .semibold)).foregroundStyle(theme.accent)
                .frame(width: 64, height: 64)
                .padding(18)
                .background(theme.accent.opacity(0.1), in: Circle())
                .padding(.top, 20)
            Text("Choose your language.")
                .multilineTextAlignment(.center)
                .font(GhafTypography.display(34, languageCode: "en"))
                .foregroundStyle(theme.primaryText)
            Text("اختر لغة التطبيق.")
                .font(GhafTypography.display(31, languageCode: "ar"))
                .foregroundStyle(theme.primaryText)
            Text(localized(
                "Your choice will refresh the entire app, including typography, alignment and content.",
                "سيتم تحديث التطبيق بالكامل وفقاً لاختيارك، بما في ذلك الخطوط والمحاذاة وجميع النصوص."
            ))
            .font(GhafTypography.body(14, languageCode: languageCode))
            .foregroundStyle(theme.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.bottom, 8)

            Button {
                languageCode = "en"
            } label: {
                HStack(spacing: 14) {
                    Text("EN")
                        .font(GhafTypography.number(19, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("English")
                            .font(GhafTypography.heading(18, languageCode: "en"))
                        Text("Continue in English")
                            .font(GhafTypography.body(12, languageCode: "en"))
                            .foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: languageCode == "en" ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(theme.accent)
                }
                .foregroundStyle(theme.primaryText)
                .padding(16)
                .ghafLiquidGlass(theme: theme, radius: 20)
            }
            .buttonStyle(.ghafPress)

            Button {
                languageCode = "ar"
            } label: {
                HStack(spacing: 14) {
                    Text("ع")
                        .font(GhafTypography.display(24, languageCode: "ar"))
                        .frame(width: 46, height: 46)
                        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("العربية")
                            .font(GhafTypography.heading(19, languageCode: "ar"))
                        Text("متابعة باللغة العربية")
                            .font(GhafTypography.body(12, languageCode: "ar"))
                            .foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: languageCode == "ar" ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(theme.accent)
                }
                .foregroundStyle(theme.primaryText)
                .padding(16)
                .ghafLiquidGlass(theme: theme, radius: 20)
            }
            .buttonStyle(.ghafPress)
            Spacer(minLength: 10)
        }
    }

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localized("Let's set up your budget.", "لنُعدّ ميزانيتك."))
                .font(GhafTypography.display(32, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)

            Text(localized("These numbers help calculate a realistic daily spending limit.", "تساعد هذه البيانات على حساب حد إنفاق يومي واقعي."))
                .font(GhafTypography.body(15, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)

            formLabel(localized("Your name", "اسمك"))
            onboardingField(localized("Name", "الاسم"), text: $name)

            formLabel(localized("Main currency", "العملة الرئيسية"))
            GhafCurrencyPicker(selection: $currency, currencies: currencies, languageCode: languageCode, tint: theme.accent)

            formLabel(localized("Monthly income", "الدخل الشهري"))
            onboardingField(localized("e.g. 5000", "مثال: ٥٠٠٠"), text: $income, numeric: true)

            formLabel(localized("Fixed monthly commitments", "الالتزامات الشهرية الثابتة"))
            onboardingField(localized("e.g. 1500", "مثال: ١٥٠٠"), text: $commitments, numeric: true)

            Text(localized("You can change all of these values later in Settings.", "يمكنك تعديل جميع هذه البيانات لاحقاً من الإعدادات."))
                .font(GhafTypography.body(13, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var accountsAndSalaryPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(languageCode == "ar" ? "أين تحتفظ بأموالك؟" : "Where do you keep your money?")
                .font(GhafTypography.display(31, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)

            Text(languageCode == "ar"
                 ? "أضف محفظتك النقدية وبطاقاتك وحساباتك. كل رصيد سيبقى منفصلاً بعملته."
                 : "Add your cash wallet, cards and bank accounts. Each balance stays separate in its own currency.")
                .font(GhafTypography.body(14, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)

            VStack(alignment: .leading, spacing: 8) {
                onboardingLabel(languageCode == "ar" ? "كيف تريد بدء الأرصدة؟" : "HOW SHOULD BALANCES START?")
                GhafSegmented(options: [("zero", languageCode == "ar" ? "ابدأ من الصفر" : "Start at zero"), ("manual", languageCode == "ar" ? "أدخل الأرصدة الحالية" : "Enter current balances")], selection: $balanceSetupMode, theme: theme, languageCode: languageCode)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    onboardingLabel(languageCode == "ar" ? "حساباتك" : "YOUR ACCOUNTS")
                    Spacer()
                    Text("\(accountDrafts.count)")
                        .font(GhafTypography.number(12, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }

                ForEach($accountDrafts) { $draft in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: $draft.type.wrappedValue.symbol)
                                .foregroundStyle(theme.accent)
                            TextField(
                                languageCode == "ar" ? "اسم الحساب" : "Account name",
                                text: $draft.name
                            )
                            .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                            Spacer()
                            Button(role: .destructive) {
                                accountDrafts.removeAll { $0.id == draft.id }
                                if salaryAccountDraftID == draft.id {
                                    salaryAccountDraftID = accountDrafts.first?.id
                                }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.ghafPress)
                            .accessibilityLabel(languageCode == "ar" ? "حذف الحساب" : "Remove account")
                        }

                        TextField(
                            languageCode == "ar" ? "اسم البنك (اختياري)" : "Bank or issuer (optional)",
                            text: $draft.institution
                        )
                        .font(GhafTypography.body(13, languageCode: languageCode))

                        GhafMenuRow(title: languageCode == "ar" ? "نوع الحساب" : "Account type", value: accountTypeTitle(draft.type), theme: theme, languageCode: languageCode) {
                            Picker(languageCode == "ar" ? "نوع الحساب" : "Account type", selection: $draft.type) {
                                ForEach(GhafAccountType.allCases) { type in
                                    Text(accountTypeTitle(type)).tag(type)
                                }
                            }
                        }

                        HStack {
                            GhafCurrencyPicker(selection: $draft.currency, currencies: currencies, languageCode: languageCode, tint: theme.accent)

                            Spacer()

                            if balanceSetupMode == "manual" {
                                GhafAmountField(value: $draft.startingBalance, currency: draft.currency,
                                                label: localized("Starting balance", "الرصيد الافتتاحي"),
                                                theme: theme, languageCode: languageCode, fontSize: 18)
                                    .frame(width: 170)
                            } else {
                                HStack(spacing: 7) {
                                    GhafCurrencyIcon(currency: draft.currency, size: 16)
                                    Text(currencyZeroLabel(for: draft.currency))
                                        .font(GhafTypography.number(13, weight: .semibold))
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), fallback: theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.outline, lineWidth: 1))
                }

                Button {
                    accountDrafts.append(
                        GhafAccountDraft(
                            name: languageCode == "ar" ? "حساب جديد" : "New account",
                            type: .debit,
                            currency: currency,
                            startingBalance: "0"
                        )
                    )
                } label: {
                    Label(
                        accountDrafts.isEmpty
                            ? (languageCode == "ar" ? "أضف حسابك الأول" : "Add your first account")
                            : (languageCode == "ar" ? "إضافة بطاقة أو حساب" : "Add another account"),
                        systemImage: "plus"
                    )
                    .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
            }

            VStack(alignment: .leading, spacing: 11) {
                Toggle(isOn: $salaryEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(languageCode == "ar" ? "إعداد يوم الراتب" : "Set my salary day")
                            .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                        Text(languageCode == "ar"
                             ? "سيطلب منك غاف تأكيد استلام الراتب في هذا اليوم."
                             : "Ghaf will ask you to confirm whether it arrived on that date.")
                            .font(GhafTypography.body(12, languageCode: languageCode))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .tint(theme.accent)

                if salaryEnabled {
                    HStack {
                        Text(languageCode == "ar" ? "يوم استلام الراتب" : "Salary day of month")
                            .font(GhafTypography.body(13, languageCode: languageCode))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        GhafMenuRow(title: languageCode == "ar" ? "يوم الراتب" : "Salary day", value: "\(salaryDay)", theme: theme, languageCode: languageCode, compact: true) {
                            Picker(languageCode == "ar" ? "يوم الراتب" : "Salary day", selection: $salaryDay) {
                                ForEach(1...31, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                        }
                    }

                    GhafAmountField(value: $salaryAmountText, currency: currency,
                                    label: languageCode == "ar" ? "قيمة الراتب (اختياري)" : "Expected salary amount (optional)",
                                    theme: theme, languageCode: languageCode)

                    GhafMenuRow(title: languageCode == "ar" ? "إيداع الراتب في" : "Salary is deposited into", value: accountDrafts.first(where: { $0.id == salaryAccountDraftID }).map { $0.name.isEmpty ? accountTypeTitle($0.type) : $0.name } ?? "", theme: theme, languageCode: languageCode) {
                        Picker(languageCode == "ar" ? "إيداع الراتب في" : "Salary is deposited into", selection: $salaryAccountDraftID) {
                            ForEach(accountDrafts) { draft in
                                Text(draft.name.isEmpty ? accountTypeTitle(draft.type) : draft.name).tag(Optional(draft.id))
                            }
                        }
                    }

                    Toggle(isOn: $salaryReminderEnabled) {
                        Text(languageCode == "ar" ? "تذكيري في يوم الراتب" : "Remind me on salary day")
                            .font(GhafTypography.body(13, languageCode: languageCode))
                            .foregroundStyle(theme.primaryText)
                    }
                    .tint(theme.accent)
                }
            }
            .padding(16)
            .ghafCard(theme: theme, radius: 18)

            if accountSetupError {
                Text(languageCode == "ar"
                     ? "تحقق من أسماء الحسابات والأرصدة المدخلة."
                     : "Check the account names and starting balances.")
                    .font(GhafTypography.body(12, languageCode: languageCode))
                    .foregroundStyle(theme.over)
            }
        }
    }

    private func onboardingLabel(_ title: String) -> some View {
        Text(title)
            .font(GhafTypography.body(11, languageCode: languageCode, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(theme.secondaryText)
    }

    private func accountTypeTitle(_ type: GhafAccountType) -> String {
        guard languageCode == "ar" else {
            return type.titleKey
        }

        switch type {
        case .cash:
            return "محفظة نقدية"
        case .debit:
            return "بطاقة خصم"
        case .current:
            return "حساب جاري"
        case .savings:
            return "حساب توفير"
        case .credit:
            return "بطاقة ائتمان"
        case .prepaid:
            return "بطاقة مسبقة الدفع"
        }
    }

    private func currencyZeroLabel(for code: String) -> String {
        GhafFormat.money(0, currency: code, languageCode: languageCode)
    }

    private var connectionPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(theme.accent)

            Text(localized("Your bank action is already in Ghaf.", "إجراء البنك جاهز داخل غاف."))
                .font(GhafTypography.display(32, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)

            Text(localized("The Ghaf action appears automatically in Shortcuts after installing the app. You only need to choose which bank message should trigger it.", "يظهر إجراء غاف تلقائياً في تطبيق الاختصارات بعد تثبيت التطبيق. ما عليك سوى اختيار رسالة البنك التي ستشغّله."))
                .font(GhafTypography.body(15, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)

            onboardingPoint(icon: "checkmark.circle", title: localized("No shortcut to build", "لا حاجة لإنشاء اختصار"), description: localized("Ghaf provides the Log Bank Message action for you.", "يوفر غاف إجراء تسجيل رسالة البنك جاهزاً."))
            onboardingPoint(icon: "person.crop.circle", title: localized("One iOS confirmation step", "خطوة تأكيد واحدة في iOS"), description: localized("You create the personal automation trigger because iOS keeps those under your control.", "تنشئ محفّز الأتمتة الشخصية بنفسك لأن iOS يضع هذه الخطوة تحت تحكمك."))

            Button {
                showAutomationGuide = true
            } label: {
                Label(localized("Set up automatic tracking", "إعداد التتبع التلقائي"), systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity)
            }
            .ghafProminentButton(theme: theme, languageCode: languageCode)

            Text(localized("iOS controls whether some automations can run without confirmation. Some banking apps also hide transaction details in notification previews.", "يحدد iOS ما إذا كان يمكن تشغيل بعض الأتمتة دون تأكيد. كما تخفي بعض التطبيقات البنكية تفاصيل العمليات في معاينة الإشعارات."))
                .font(GhafTypography.body(13, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func onboardingPoint(icon: String, title: String, description: String) -> some View {
        GhafListRow(icon: icon, tint: theme.accent, title: title, subtitle: description,
                    theme: theme, languageCode: languageCode)
    }

    private func localized(_ english: String, _ arabic: String) -> String {
        languageCode == "ar" ? arabic : english
    }

    private func formLabel(_ value: String) -> some View {
        Text(value)
            .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
            .foregroundStyle(theme.primaryText)
    }

    private func onboardingField(_ placeholder: String, text: Binding<String>, numeric: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .font(GhafTypography.body(16, languageCode: languageCode))
            .keyboardType(numeric ? .decimalPad : .default)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 14, style: .continuous), fallback: theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.outline, lineWidth: 1))
    }

    private func advance() {
        if step < 5 {
            step += 1
            return
        }

        if step == 5 {
            settings.userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.currency = currency
            settings.monthlyIncome = Decimal(string: income) ?? 0
            settings.fixedCommitments = Decimal(string: commitments) ?? 0
            step = 6
            return
        }

        if step == 6 {
            var createdIDs: [UUID] = []
            for (index, draft) in accountDrafts.enumerated() {
                let cleanName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanName.isEmpty else {
                    accountSetupError = true
                    return
                }

                let balance: Decimal
                if balanceSetupMode == "manual" {
                    guard let entered = Decimal(string: draft.startingBalance), entered >= 0 else {
                        accountSetupError = true
                        return
                    }
                    balance = entered
                } else {
                    balance = 0
                }

                let account = GhafAccount(
                    id: draft.id,
                    name: cleanName,
                    institution: draft.institution.isEmpty ? nil : draft.institution,
                    accountType: draft.type,
                    currency: draft.currency,
                    openingBalance: balance,
                    openingDate: .now,
                    isPrimary: index == 0,
                    sortOrder: index
                )
                modelContext.insert(account)
                createdIDs.append(account.id)
            }

            settings.balanceSetupMode = balanceSetupMode
            settings.salaryEnabled = salaryEnabled
            settings.salaryDay = salaryEnabled ? salaryDay : nil
            settings.salaryAmount = salaryEnabled
                ? (Decimal(string: salaryAmountText) ?? settings.monthlyIncome)
                : nil
            settings.salaryCurrency = currency
            settings.salaryAccountID = salaryEnabled
                ? (salaryAccountDraftID ?? createdIDs.first)
                : nil
            settings.salaryReminderEnabled = salaryEnabled && salaryReminderEnabled
            do {
                try modelContext.save()
                step = 7
                accountSetupError = false
                if salaryEnabled && salaryReminderEnabled {
                    Task {
                        _ = await GhafSalaryReminderService.requestPermission()
                        try? await GhafSalaryReminderService.scheduleNext(
                            salaryDay: salaryDay,
                            languageCode: languageCode
                        )
                    }
                }
            } catch {
                accountSetupError = true
            }
            return
        }

        settings.hasCompletedOnboarding = true
        try? modelContext.save()
    }
}


// MARK: - Branded cold-launch welcome

/// Shown on every fresh app process launch, deliberately separate from onboarding completion, so returning
/// users see it without repeating setup or resetting data. Never shown on return from the background.
/// Canvas "Cold start": a centred "Welcome back" greeting, two tilted rows of the user's own cards drifting
/// in opposite directions, the theme's light rising from the bottom and a slim loading bar.
private struct GhafWelcomeLaunchScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    let settings: GhafSettings?
    @State private var shown = false
    @State private var start = Date()

    private var ar: Bool { settings?.languageCode == "ar" }
    private var lang: String { settings?.languageCode ?? "en" }
    private var returning: Bool { settings?.hasCompletedOnboarding == true }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings?.themeName ?? "Abu Dhabi", appearanceMode: settings?.appearanceMode ?? "System",
                          systemIsDark: colorScheme == .dark)
    }
    private var name: String {
        let value = settings?.userName.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? (ar ? "غاف" : "Ghaf") : value
    }
    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                Spacer()
                GhafTreeMark(color: theme.accent).frame(width: 96, height: 96)
                    .shadow(color: theme.glow.opacity(0.7), radius: 28)
                Text(returning ? (ar ? "أهلاً بعودتك، \(name)" : "Welcome back, \(name)") : "Ghaf")
                    .font(GhafTypography.display(42, languageCode: lang)).foregroundStyle(theme.primaryText)
                if !returning {
                    Text(ar ? "أموالك، بوضوح." : "Your money, clearly.")
                        .font(GhafTypography.body(17, languageCode: lang)).foregroundStyle(theme.secondaryText)
                }
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let phase = reduceMotion ? 0.5 : context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 2.8) / 2.8
                    ZStack {
                        Capsule().fill(theme.glow.opacity(0.12)).frame(height: 2)
                        WelcomeCurve().stroke(theme.glow.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        Circle().fill(theme.accent).frame(width: 9, height: 9)
                            .shadow(color: theme.accent, radius: 12)
                            .offset(x: (phase - 0.5) * 220, y: CGFloat(sin(phase * .pi * 2)) * 10)
                    }
                    .frame(width: 260, height: 34)
                }
                if returning {
                    let ownAccounts = accounts.filter { !$0.isArchived }
                    if !ownAccounts.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(ownAccounts) { account in
                                    GhafCardFace(account: account, name: account.name, institution: account.institution ?? "",
                                                 lastFour: account.lastFourDigits ?? "", design: GhafCardDesign.forAccount(account), width: 150)
                                }
                            }
                        }
                        .frame(height: 125)
                        .accessibilityHidden(true)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: 360).padding(28)
        }
        .ghafBackground(theme: theme)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ar ? "غاف يفتح" : "Ghaf is opening")
        .onAppear {
            start = .now
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.2)) { shown = true }
        }
    }

}

private struct WelcomeCurve: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                          control1: CGPoint(x: rect.width * 0.3, y: rect.minY),
                          control2: CGPoint(x: rect.width * 0.7, y: rect.maxY))
        }
    }
}


/// Ghaf AI's tab icon: a glass orb in the theme's colours, kept in full colour. `frame` 1...frameCount
/// draws the twirl played when the tab opens; 0 is at rest.
@MainActor
enum GhafAITabIcon {
    static let frameCount = 16
    private static var cache: [String: UIImage] = [:]

    static func image(theme: GhafTheme, selected: Bool, frame: Int = 0) -> UIImage {
        let key = "\(theme.name)-\(theme.isDark)-\(selected)-\(frame)"
        if let cached = cache[key] { return cached }
        let t = Double(frame) / Double(frameCount)          // 0...1 through the opening swirl
        let lift = sin(t * .pi)                             // rises then settles
        // The Ghaf AI orb, drawn by the same code as the AI screen. The dark palette's accent and glow are
        // the brighter pair, so it reads on light and dark tab bars. On open its light swirls once, then settles.
        let side: CGFloat = selected ? 32 : 29
        let lit = GhafTheme.resolve(name: theme.name, appearanceMode: "Dark", systemIsDark: true)
        let mark = GhafAIOrbFace(theme: lit, mood: frame == 0 ? .idle : .thinking, level: 0,
                                 time: 3.1 + t * 3, still: frame == 0, halo: false)
            .frame(width: side, height: side)
            .shadow(color: lit.accent.opacity(selected ? 0.6 : 0.3), radius: selected ? 5 : 2, y: 1)
            .opacity(selected ? 1 : 0.82)
            .scaleEffect(1 + 0.08 * lift)
            .frame(width: 40, height: 40)
        let renderer = ImageRenderer(content: mark)
        renderer.scale = 3
        let image = (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysOriginal)
        cache[key] = image
        return image
    }
}
