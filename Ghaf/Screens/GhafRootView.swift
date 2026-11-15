import SwiftUI
import SwiftData
import LocalAuthentication

struct GhafRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settings: [GhafSettings]

    @State private var showAutomationIntro = false
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
                .id(languageCode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear.ignoresSafeArea())

            if showLaunch {
                GhafWelcomeLaunchScreen()
                    .transition(.opacity)
                    .zIndex(10)
            }

            if requiresAuthentication && !isUnlocked && !showLaunch {
                authenticationLockScreen
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .environment(\.locale, Locale(identifier: languageCode))
        .environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear.ignoresSafeArea())
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onAppear(perform: beginLaunch)
        .onChange(of: scenePhase) { _, phase in
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

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.85))
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
        try? modelContext.save()
    }
}

// MARK: - Main Tab Navigation

@Observable
final class GhafTabRouter {
    var selectedTab = 0
}

struct GhafTabView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(filter: #Predicate<GhafTransaction> { $0.needsReview }) private var reviewItems: [GhafTransaction]
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

        TabView(selection: $router.selectedTab) {
            GhafHomeView(settings: settings)
                .tabItem { Label(settings.languageCode == "ar" ? "الرئيسية" : "Home", systemImage: "house.fill") }
                .tag(0)

            GhafTransactionsView(settings: settings)
                .tabItem { Label(settings.languageCode == "ar" ? "العمليات" : "Transactions", systemImage: "arrow.left.arrow.right") }
                .badge(reviewCount)
                .tag(3)

            GhafAIView(settings: settings)
                .tabItem { Label(settings.languageCode == "ar" ? "غاف AI" : "Ghaf AI", systemImage: "sparkles") }
                .tag(1)

            GhafSubscriptionsView(settings: settings)
                .tabItem { Label(settings.languageCode == "ar" ? "الاشتراكات" : "Subscriptions", systemImage: "repeat") }
                .tag(2)

            GhafSettingsView(settings: settings)
                .tabItem { Label(settings.languageCode == "ar" ? "المزيد" : "More", systemImage: "ellipsis") }
                .tag(4)
        }
        .tint(theme.accent)
        .sensoryFeedback(.selection, trigger: router.selectedTab)
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

// MARK: - Onboarding

/// Intro illustration built from shapes and SF Symbols: a glowing disc, a hero glyph,
/// and three orbiting badges that drift gently (still under Reduce Motion).
struct GhafIntroIllustration: View {
    let symbol: String
    let satellites: [String]
    let theme: GhafTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        ZStack {
            Circle().fill(theme.accent.opacity(0.08)).frame(width: 230, height: 230)
            Circle().stroke(theme.accent.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [4, 7]))
                .frame(width: 190, height: 190)
            Circle().fill(theme.accent.gradient).frame(width: 116, height: 116)
                .shadow(color: theme.accent.opacity(0.4), radius: 22, y: 10)
            Image(systemName: symbol)
                .font(.system(size: 50, weight: .bold))
                .foregroundStyle(theme.accentContrast)
                .symbolEffect(.bounce, value: floating)
            ForEach(Array(satellites.prefix(3).enumerated()), id: \.offset) { index, name in
                let angle = Angle.degrees([-140, -30, 95][index])
                Image(systemName: name)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 50, height: 50)
                    .background(theme.surface, in: Circle())
                    .shadow(color: .black.opacity(theme.isDark ? 0 : 0.08), radius: 10, y: 4)
                    .offset(x: cos(angle.radians) * 98, y: sin(angle.radians) * 98 + (floating ? -5 : 5) * (index.isMultiple(of: 2) ? 1 : -1))
            }
        }
        .frame(width: 260, height: 250)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { floating = true }
        }
    }
}

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

    var body: some View {
        VStack(spacing: 0) {
            // Progress: one capsule per step, the current one stretched.
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? theme.accent : theme.secondaryText.opacity(0.2))
                        .frame(width: index == step ? 26 : 8, height: 8)
                }
            }
            .animation(.snappy(duration: 0.3), value: step)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localized("Step \(step + 1) of 7", "الخطوة \(step + 1) من 7"))

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        if step == 0 {
                            languageSelectionPage
                        } else if step == 1 {
                            welcomePage
                        } else if step == 2 {
                            privacyPage
                        } else if step == 3 {
                            automationIntroPage
                        } else if step == 4 {
                            setupPage
                        } else if step == 5 {
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
                Button(step == 6 ? localized("Start using Ghaf", "ابدأ استخدام غاف") : localized("Continue", "متابعة")) {
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
        .onChange(of: languageCode) { _, newValue in
            settings.languageCode = newValue
            try? modelContext.save()
        }
        .sheet(isPresented: $showAutomationGuide, onDismiss: {
            settings.hasSeenAutomationIntro = true
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
    }

    private var languageSelectionPage: some View {
        VStack(spacing: 22) {
            GhafTreeMark(color: theme.accent)
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

    private var welcomePage: some View {
        Image("GhafWelcomeArtwork")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .accessibilityLabel(languageCode == "ar" ? "غاف، صنع بحب في الإمارات" : "Ghaf, made with love in the UAE")
    }

    private var privacyPage: some View {
        VStack(spacing: 22) {
            GhafIntroIllustration(symbol: "lock.shield.fill",
                                  satellites: ["iphone", "eye.slash.fill", "hand.raised.fill"], theme: theme)
            introHeading(localized("Your money data stays yours.", "بياناتك المالية تبقى ملكاً لك."),
                         localized("Ghaf is designed to work locally on your iPhone.", "صُمم غاف للعمل محلياً على جهاز iPhone الخاص بك."))
            VStack(spacing: 0) {
                onboardingPoint(icon: "iphone", title: localized("Stored on your device", "محفوظة على جهازك"), description: localized("Transactions and settings are saved locally.", "تُحفظ العمليات والإعدادات محلياً على جهازك."))
                onboardingPoint(icon: "server.rack", title: localized("No financial servers", "لا خوادم مالية"), description: localized("No Ghaf account or external banking connection.", "لا يتطلب غاف حساباً خارجياً أو اتصالاً بالبنوك."))
                onboardingPoint(icon: "chart.bar.fill", title: localized("Understand your habits", "افهم عاداتك المالية"), description: localized("See spending trends and budget progress.", "تابع اتجاهات الإنفاق وتقدم ميزانيتك."))
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .ghafCard(theme: theme)
        }
    }

    private var automationIntroPage: some View {
        VStack(spacing: 22) {
            GhafIntroIllustration(symbol: "bolt.fill",
                                  satellites: ["message.fill", "sparkles", "checkmark.circle.fill"], theme: theme)
            introHeading(localized("Bank SMS, logged automatically.", "رسائل البنك تُسجّل تلقائياً."),
                         localized("Connect supported bank SMS messages once through Apple Shortcuts. Ghaf can then sort matching transactions automatically.", "اربط رسائل SMS البنكية المدعومة مرة واحدة عبر تطبيق الاختصارات، وبعدها يستطيع غاف تصنيف العمليات المطابقة تلقائياً."))
            VStack(spacing: 0) {
                onboardingPoint(icon: "message.fill", title: localized("Supported bank SMS", "رسائل SMS البنكية المدعومة"), description: localized("Choose a bank sender once. Matching transaction messages can be logged without retyping them.", "اختر مُرسل البنك مرة واحدة، وستُسجّل الرسائل المطابقة دون إعادة كتابتها."))
                onboardingPoint(icon: "banknote.fill", title: localized("Cash stays manual", "النقد يُسجّل يدوياً"), description: localized("Cash purchases and sources that do not send SMS still need a quick manual entry.", "المشتريات النقدية والمصادر التي لا ترسل رسائل SMS تحتاج إلى إدخال يدوي سريع."))
                onboardingPoint(icon: "iphone.gen3", title: localized("iOS privacy boundary", "حدود الخصوصية في iOS"), description: localized("Ghaf cannot read bank-app push notifications directly. App notifications without SMS cannot be captured automatically by this shortcut.", "لا يستطيع غاف قراءة إشعارات التطبيقات البنكية مباشرة، ولا يمكن التقاطها تلقائياً عبر هذا الاختصار دون رسالة SMS."))
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .ghafCard(theme: theme)
        }
    }

    private func introHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(GhafTypography.display(30, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)
            Text(subtitle)
                .font(GhafTypography.body(16, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
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
                Picker(
                    languageCode == "ar" ? "طريقة بدء الأرصدة" : "Starting balances",
                    selection: $balanceSetupMode
                ) {
                    Text(languageCode == "ar" ? "ابدأ من الصفر" : "Start at zero").tag("zero")
                    Text(languageCode == "ar" ? "أدخل الأرصدة الحالية" : "Enter current balances").tag("manual")
                }
                .pickerStyle(.segmented)
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

                        Picker(
                            languageCode == "ar" ? "نوع الحساب" : "Account type",
                            selection: $draft.type
                        ) {
                            ForEach(GhafAccountType.allCases) { type in
                                Text(accountTypeTitle(type)).tag(type)
                            }
                        }
                        .font(GhafTypography.body(12, languageCode: languageCode))
                        .tint(theme.accent)

                        HStack {
                            GhafCurrencyPicker(selection: $draft.currency, currencies: currencies, languageCode: languageCode, tint: theme.accent)

                            Spacer()

                            if balanceSetupMode == "manual" {
                                TextField(localized("0.00", "٠٫٠٠"), text: $draft.startingBalance)
                                    .font(GhafTypography.number(15, weight: .semibold))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 110)
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
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        Picker(languageCode == "ar" ? "يوم الراتب" : "Salary day", selection: $salaryDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(theme.accent)
                    }

                    TextField(
                        languageCode == "ar" ? "قيمة الراتب (اختياري)" : "Expected salary amount (optional)",
                        text: $salaryAmountText
                    )
                    .font(GhafTypography.body(14, languageCode: languageCode))
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))

                    Picker(
                        languageCode == "ar" ? "إيداع الراتب في" : "Salary is deposited into",
                        selection: $salaryAccountDraftID
                    ) {
                        ForEach(accountDrafts) { draft in
                            Text(draft.name.isEmpty ? accountTypeTitle(draft.type) : draft.name)
                                .tag(Optional(draft.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.accent)

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
            .font(GhafTypography.body(10, languageCode: languageCode, weight: .bold))
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
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.outline, lineWidth: 1))
    }

    private func advance() {
        if step < 4 {
            step += 1
            return
        }

        if step == 4 {
            settings.userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.currency = currency
            settings.monthlyIncome = Decimal(string: income) ?? 0
            settings.fixedCommitments = Decimal(string: commitments) ?? 0
            step = 5
            return
        }

        if step == 5 {
            guard !accountDrafts.isEmpty else {
                accountSetupError = true
                return
            }

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
                step = 6
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

/// Shown on every fresh app process launch. This is deliberately separate
/// from onboarding completion, so returning users see the artwork without
/// repeating setup or resetting any financial data.
private struct GhafWelcomeLaunchScreen: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                Image("GhafWelcomeArtwork")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityLabel("Ghaf")
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
