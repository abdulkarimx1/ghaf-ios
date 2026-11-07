import SwiftUI
import SwiftData

struct GhafRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [GhafSettings]

    @State private var showAutomationIntro = false
    @State private var showLaunch = true
    @State private var launchScale: CGFloat = 0.62
    @State private var launchHasStarted = false

    private var languageCode: String {
        settings.first?.languageCode ?? "en"
    }

    var body: some View {
        ZStack {
            rootContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear.ignoresSafeArea())

            if showLaunch {
                GhafLaunchSplash(scale: launchScale)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .environment(\.locale, Locale(identifier: languageCode))
        .environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear.ignoresSafeArea())
        .onAppear(perform: beginLaunch)
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
                                Button("Done") {
                                    showAutomationIntro = false
                                }
                            }
                        }
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

        withAnimation(.spring(response: 0.78, dampingFraction: 0.78)) {
            launchScale = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.85))
            withAnimation(.easeOut(duration: 0.42)) {
                showLaunch = false
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

struct GhafTabView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Query private var transactions: [GhafTransaction]
    @State private var selectedTab = 0

    let settings: GhafSettings

    var body: some View {
        let theme = GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
        let reviewCount = transactions.filter { $0.needsReview }.count

        TabView(selection: $selectedTab) {
            GhafHomeView(settings: settings)
                .tabItem { Label(settings.languageCode == "ar" ? "الرئيسية" : "Home", systemImage: "house.fill") }
                .tag(0)

            GhafTransactionsView(settings: settings)
                .tabItem { Label(settings.languageCode == "ar" ? "العمليات" : "Transactions", systemImage: "arrow.left.arrow.right") }
                .tag(1)

            GhafReviewInboxView(settings: settings)
                .tabItem { Label(settings.languageCode == "ar" ? "المراجعة" : "Review", systemImage: "tray.full.fill") }
                .badge(reviewCount)
                .tag(2)

            GhafInsightsView(settings: settings)
                .tabItem { Label(settings.languageCode == "ar" ? "التقارير" : "Insights", systemImage: "chart.bar.xaxis") }
                .tag(3)

            GhafSettingsView(settings: settings)
                .tabItem { Label(settings.languageCode == "ar" ? "الإعدادات" : "Settings", systemImage: "slider.horizontal.3") }
                .tag(4)
        }
        .tint(theme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .preferredColorScheme(
            settings.appearanceMode == "Dark" ? .dark :
                settings.appearanceMode == "Light" ? .light : nil
        )
    }
}

// MARK: - Onboarding

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

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private let currencies = [
        "AED", "USD", "EUR", "GBP", "SAR",
        "KWD", "BHD", "OMR", "QAR"
    ]

    init(settings: GhafSettings) {
        self.settings = settings
        _languageCode = State(initialValue: settings.languageCode)
        _name = State(initialValue: settings.userName)
        _currency = State(initialValue: settings.currency)
        _income = State(initialValue: GhafFormat.decimal(settings.monthlyIncome))
        _commitments = State(initialValue: GhafFormat.decimal(settings.fixedCommitments))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GHAF")
                    .font(GhafTypography.number(15, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(theme.accent)

                Spacer()

                Picker("Language", selection: $languageCode) {
                    Text("English").tag("en")
                    Text("العربية").tag("ar")
                }
                .pickerStyle(.menu)
                .tint(theme.accent)

                Text("\(step + 1) / 5")
                    .font(GhafTypography.number(12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        if step == 0 {
                            welcomePage
                        } else if step == 1 {
                            privacyPage
                        } else if step == 2 {
                            automationIntroPage
                        } else if step == 3 {
                            setupPage
                        } else {
                            connectionPage
                        }
                    }
                    .padding(24)
                    .frame(minHeight: geometry.size.height, alignment: .topLeading)
                }
            }

            VStack(spacing: 10) {
                Button(step == 4 ? "Start using Ghaf" : "Continue") {
                    advance()
                }
                .ghafProminentButton(theme: theme, languageCode: languageCode)

                if step > 0 {
                    Button("Back") { step -= 1 }
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
                            Button("Done") { showAutomationGuide = false }
                        }
                    }
            }
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(theme.accent)
                VStack(spacing: 12) {
                    GhafTreeMark(color: theme.accentContrast)
                        .frame(width: 80, height: 85)
                    Text("GHAF")
                        .font(GhafTypography.number(26, weight: .bold))
                        .tracking(5)
                        .foregroundStyle(theme.accentContrast)
                }
            }
            .frame(height: 218)

            Text("Make every dirham count.")
                .font(GhafTypography.display(34, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)

            Text("A clearer picture of your money, your spending and your daily budget.")
                .font(GhafTypography.body(16, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)

            Text("A simple financial companion that helps you stay in control.")
                .font(GhafTypography.body(15, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(theme.accent)

            Text("Your money data stays yours.")
                .font(GhafTypography.display(32, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)

            Text("Ghaf is designed to work locally on your iPhone.")
                .font(GhafTypography.body(16, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)

            onboardingPoint(icon: "iphone", title: "Stored on your device", description: "Transactions and settings are saved locally.")
            onboardingPoint(icon: "server.rack", title: "No financial servers", description: "No Ghaf account or external banking connection.")
            onboardingPoint(icon: "chart.bar", title: "Understand your habits", description: "See spending trends and budget progress.")
        }
    }

    private var automationIntroPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(theme.accent)

            Text("Your transactions, automatically.")
                .font(GhafTypography.display(32, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)

            Text("Ghaf's bank-message action is ready to use from Apple Shortcuts.")
                .font(GhafTypography.body(16, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)

            onboardingPoint(icon: "message", title: "Bank messages", description: "Pass incoming SMS message text to Ghaf.")
            onboardingPoint(icon: "app.badge", title: "Bank notifications", description: "Where iOS exposes the notification content, send it to Ghaf.")
            onboardingPoint(icon: "checkmark.shield", title: "You stay in control", description: "OTP messages, promotions and incomplete transfer requests are filtered.")
        }
    }

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Let's set up your budget.")
                .font(GhafTypography.display(32, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)

            Text("These numbers help calculate a realistic daily spending limit.")
                .font(GhafTypography.body(15, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)

            formLabel("Your name")
            onboardingField("Name", text: $name)

            formLabel("Main currency")
            Picker("Currency", selection: $currency) {
                ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
            }
            .pickerStyle(.menu)
            .tint(theme.accent)

            formLabel("Monthly income")
            onboardingField("e.g. 5000", text: $income, numeric: true)

            formLabel("Fixed monthly commitments")
            onboardingField("e.g. 1500", text: $commitments, numeric: true)

            Text("You can change all of these values later in Settings.")
                .font(GhafTypography.body(13, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var connectionPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(theme.accent)

            Text("Your bank action is already in Ghaf.")
                .font(GhafTypography.display(32, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)

            Text("The Ghaf action appears automatically in Shortcuts after installing the app. You only need to choose which bank message should trigger it.")
                .font(GhafTypography.body(15, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)

            onboardingPoint(icon: "checkmark.circle", title: "No shortcut to build", description: "Ghaf provides the Log Bank Message action for you.")
            onboardingPoint(icon: "person.crop.circle", title: "One iOS confirmation step", description: "You create the personal automation trigger because iOS keeps those under your control.")

            Button {
                showAutomationGuide = true
            } label: {
                Label("Set up automatic tracking", systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity)
            }
            .ghafProminentButton(theme: theme, languageCode: languageCode)

            Text("iOS controls whether some automations can run without confirmation. Some banking apps also hide transaction details in notification previews.")
                .font(GhafTypography.body(13, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func onboardingPoint(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(description)
                    .font(GhafTypography.body(14, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        if step < 3 {
            step += 1
            return
        }

        if step == 3 {
            settings.userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.currency = currency
            settings.monthlyIncome = Decimal(string: income) ?? 0
            settings.fixedCommitments = Decimal(string: commitments) ?? 0
            step = 4
            return
        }

        settings.hasCompletedOnboarding = true
        try? modelContext.save()
    }
}
