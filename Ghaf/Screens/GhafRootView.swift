import SwiftUI
import SwiftData

struct GhafRootView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var settings: [GhafSettings]
    @State private var showAutomationIntro = false

    var body: some View {

        Group {

            if let settings = settings.first {

                if settings.hasCompletedOnboarding {

                    GhafTabView(settings: settings)

                } else {

                    GhafOnboardingView(settings: settings)
                }

            } else {

                ProgressView()
                    .task {
                        do {
                            _ = try GhafPersistence.settings(
                                in: modelContext
                            )
                        } catch {
                            print("Ghaf initialization error: \(error)")
                        }
                    }
            }
        }
        .environment(\.locale, Locale(identifier: settings.first?.languageCode ?? "en"))
        .environment(\.layoutDirection, (settings.first?.languageCode ?? "en") == "ar" ? .rightToLeft : .leftToRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear.ignoresSafeArea())
        .onAppear {
            presentAutomationIntroIfNeeded()
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
                                Button("Done") {
                                    showAutomationIntro = false
                                }
                            }
                        }
                }
            }
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

        let reviewCount = transactions.filter {
            $0.needsReview
        }.count

        TabView(selection: $selectedTab) {

            GhafHomeView(settings: settings)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            GhafTransactionsView(settings: settings)
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            GhafReviewInboxView(settings: settings)
                .tabItem {
                    Label("Review", systemImage: "tray.full")
                }
                .badge(reviewCount)
                .tag(2)

            GhafInsightsView(settings: settings)
                .tabItem {
                    Label("Insights", systemImage: "chart.bar.fill")
                }
                .tag(3)

            GhafSettingsView(settings: settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(theme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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

        _income = State(
            initialValue: GhafFormat.decimal(
                settings.monthlyIncome
            )
        )

        _commitments = State(
            initialValue: GhafFormat.decimal(
                settings.fixedCommitments
            )
        )
    }

    var body: some View {

        VStack(spacing: 0) {

            HStack {

                Text("GHAF")
                    .font(.system(size: 17, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(theme.accent)

                Spacer()

                Picker("Language", selection: $languageCode) {
                    Text("English").tag("en")
                    Text("العربية").tag("ar")
                }
                .pickerStyle(.menu)
                .tint(theme.accent)

                if step < 5 {
                    Text("\(step + 1) OF 5")
                        .font(GhafTypeScale.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            ScrollView {

                VStack(alignment: .leading, spacing: 24) {

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
            }

            VStack(spacing: 12) {

                Button(step == 4 ? "Start using Ghaf" : "Continue") {

                    advance()
                }
                .buttonStyle(
                    GhafGlassButtonStyle(theme: theme)
                )

                if step > 0 {

                    Button("Back") {
                        step -= 1
                    }
                    .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .onChange(of: languageCode) { _, newValue in
            settings.languageCode = newValue
            try? modelContext.save()
        }
        .sheet(isPresented: $showAutomationGuide) {
            NavigationStack {
                GhafAutomationGuideView(settings: settings)
            }
        }
    }

    private var welcomePage: some View {

        VStack(alignment: .leading, spacing: 22) {

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.accent, theme.accent.opacity(0.68), theme.elevatedSurface.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 218)
                .overlay {
                    VStack(spacing: 13) {
                        GhafTreeMark(color: theme.accentContrast)
                            .frame(width: 82, height: 92)
                        Text("GHAF")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .tracking(5)
                            .foregroundStyle(theme.accentContrast)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: theme.accent.opacity(0.18), radius: 22, y: 12)

            Text("Make every dirham count.")

                .font(GhafTypeScale.largeTitle)
                .foregroundStyle(theme.primaryText)

            Text("A clearer picture of your money, your spending and your daily budget.")
                .font(GhafTypeScale.body)
                .foregroundStyle(theme.secondaryText)

            Text("A simple financial companion that helps you stay in control.")
                .font(GhafTypeScale.body)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var privacyPage: some View {

        VStack(alignment: .leading, spacing: 22) {

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54))
                .foregroundStyle(theme.accent)

            Text("Your money data stays yours.")
                .font(GhafTypeScale.largeTitle)
                .foregroundStyle(theme.primaryText)

            Text("Ghaf is designed to work locally on your iPhone.")

                .font(GhafTypeScale.body)
                .foregroundStyle(theme.secondaryText)

            onboardingPoint(
                icon: "iphone",
                title: "Stored on your device",
                description: "Transactions and settings are saved locally."
            )

            onboardingPoint(
                icon: "server.rack",
                title: "No financial servers",
                description: "No Ghaf account or external banking connection."
            )

            onboardingPoint(
                icon: "chart.bar",
                title: "Understand your habits",
                description: "See spending trends and budget progress."
            )
        }
    }

    private var automationIntroPage: some View {

        VStack(alignment: .leading, spacing: 22) {

            Image(systemName: "arrow.trianglehead.2.clockwise")
                .font(.system(size: 54))
                .foregroundStyle(theme.accent)

            Text("Your transactions, automatically.")
                .font(GhafTypeScale.largeTitle)
                .foregroundStyle(theme.primaryText)

            Text("Ghaf uses Apple Shortcuts to receive supported bank messages and notifications.")

                .font(GhafTypeScale.body)
                .foregroundStyle(theme.secondaryText)

            onboardingPoint(
                icon: "message",
                title: "SMS messages",
                description: "Create an automation when a bank message arrives."
            )

            onboardingPoint(
                icon: "app.badge",
                title: "Bank notifications",
                description: "Use a notification automation when your iOS version supports it."
            )

            onboardingPoint(
                icon: "checkmark.shield",
                title: "You stay in control",
                description: "Ghaf ignores OTPs, promotions and unconfirmed transfer requests."
            )
        }
    }

    private var setupPage: some View {

        VStack(alignment: .leading, spacing: 18) {

            Text("Let's set up your budget.")
                .font(GhafTypeScale.largeTitle)
                .foregroundStyle(theme.primaryText)

            Text("These numbers help calculate a realistic daily spending limit.")
                .foregroundStyle(theme.secondaryText)

            Group {

                Text("Your name")
                    .font(.system(size: 14, weight: .semibold))

                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                Text("Main currency")
                    .font(.system(size: 14, weight: .semibold))

                Picker("Currency", selection: $currency) {
                    ForEach(currencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .pickerStyle(.menu)

                Text("Monthly income")
                    .font(.system(size: 14, weight: .semibold))

                TextField("e.g. 5000", text: $income)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                Text("Fixed monthly commitments")
                    .font(.system(size: 14, weight: .semibold))

                TextField("e.g. 1500", text: $commitments)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            .foregroundStyle(theme.primaryText)

            Text("You can change all of these values later in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var connectionPage: some View {

        VStack(alignment: .leading, spacing: 22) {

            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(theme.accent)

            Text("Connect your bank messages.")
                .font(GhafTypeScale.largeTitle)
                .foregroundStyle(theme.primaryText)

            Text("Ghaf does not read SMS or other apps directly. You configure Shortcuts to pass supported message text into Ghaf.")
                .foregroundStyle(theme.secondaryText)

            onboardingPoint(
                icon: "message",
                title: "Message automation",
                description: "Open Shortcuts → Automation → Message. Select your bank sender, then pass the Message variable to Ghaf's Log Bank Message action."
            )

            onboardingPoint(
                icon: "app.badge",
                title: "Notification automation",
                description: "Where supported, select your banking app under the Notification automation trigger and pass its available notification content."
            )

            onboardingPoint(
                icon: "bolt.fill",
                title: "Add Ghaf's action",
                description: "Choose Log Bank Message. Pass Message Text and Sender / App Name. Enable automatic running wherever the trigger supports it."
            )

            Button {
                showAutomationGuide = true
            } label: {
                Label("Open step-by-step setup", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GhafGlassButtonStyle(theme: theme))

            Text("iOS controls whether notification automations can run without confirmation. Some bank apps also hide transaction details in notification previews.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func onboardingPoint(
        icon: String,
        title: String,
        description: String
    ) -> some View {

        HStack(alignment: .top, spacing: 14) {

            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 5) {

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.primaryText)

                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private func advance() {

        if step < 3 {

            step += 1
            return
        }

        if step == 3 {

            settings.userName = name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            settings.currency = currency

            settings.monthlyIncome = Decimal(
                string: income
            ) ?? 0

            settings.fixedCommitments = Decimal(
                string: commitments
            ) ?? 0

            step = 4

            return
        }

        settings.hasCompletedOnboarding = true

        try? modelContext.save()
    }
}
