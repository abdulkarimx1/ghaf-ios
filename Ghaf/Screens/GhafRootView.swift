import SwiftUI
import GhafCore
import AuthenticationServices
import SwiftData
import LocalAuthentication
import UserNotifications
import AVFoundation
import Speech
import UniformTypeIdentifiers
import UIKit

struct GhafRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settings: [GhafSettings]

    @State private var showAutomationIntro = false
    @State private var appliedLanguage = ""
    @State private var languageTransitionText = ""
    @State private var showLanguageTransition = false
    @State private var languageGlow = false
    @State private var showLaunch = true
    @State private var launchHasStarted = false
    @State private var launchSkipRequested = false
    @State private var isUnlocked = true
    @State private var authenticationMessage: String?
    @State private var authenticationInProgress = false
    #if DEBUG
    @State private var fixtureRouter = GhafTabRouter()
    #endif

    private var requiresAuthentication: Bool {
        settings.first?.hasCompletedOnboarding == true &&
        settings.first?.biometricLockEnabled == true
    }

    private var languageCode: String {
        settings.first?.languageCode ?? "en"
    }

    private func localized(_ english: String, _ arabic: String, languageCode: String) -> String {
        languageCode == "ar" ? arabic : english
    }

    var body: some View {
        ZStack {
            rootContent
                .id(appliedLanguage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear.ignoresSafeArea())

            if showLaunch && (!screenshotFixtureEnabled || launchFixtureProofEnabled) {
                GhafWelcomeLaunchScreen(settings: settings.first) { launchSkipRequested = true }
                    .transition(.opacity)
                    .zIndex(10)
            }

            if requiresAuthentication && !isUnlocked && !showLaunch {
                authenticationLockScreen
                    .transition(.opacity)
                    .zIndex(20)
            }

            if showLanguageTransition, let currentSettings = settings.first {
                let transitionTheme = GhafTheme.resolve(name: currentSettings.themeName,
                                                        appearanceMode: currentSettings.appearanceMode,
                                                        systemIsDark: systemColorScheme == .dark)
                VStack(spacing: 18) {
                    Text(languageCode == "ar" ? "غاف" : "Ghaf")
                        .font(GhafTypography.display(40, languageCode: languageCode))
                        .foregroundStyle(transitionTheme.primaryText)
                        .shadow(color: transitionTheme.glow.opacity(languageGlow ? 0.65 : 0.2), radius: languageGlow ? 24 : 10)
                        .overlay { Circle().fill(transitionTheme.glow.opacity(languageGlow ? 0.18 : 0)).frame(width: 86, height: 86).blur(radius: 24) }
                    Text(languageTransitionText).font(GhafTypography.body(17, languageCode: languageCode, weight: .medium))
                        .contentTransition(.opacity)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(transitionTheme.primaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(transitionTheme.background.ignoresSafeArea())
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeOut(duration: 0.55)) { languageGlow = true }
                }
                .zIndex(30)
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
        .onChange(of: languageCode, initial: true) { oldCode, code in
            guard !appliedLanguage.isEmpty, oldCode != code else {
                UIView.appearance().semanticContentAttribute = code == "ar" ? .forceRightToLeft : .forceLeftToRight
                appliedLanguage = code
                return
            }
            let oldText = localized("Welcome", "أهلاً", languageCode: oldCode)
            let newText = localized("Welcome", "أهلاً", languageCode: code)
            languageTransitionText = oldText
            languageGlow = false
            showLanguageTransition = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.45)) {
                    languageTransitionText = newText
                }
                try? await Task.sleep(for: .milliseconds(200))
                UIView.appearance().semanticContentAttribute = code == "ar" ? .forceRightToLeft : .forceLeftToRight
                appliedLanguage = code
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeOut(duration: 0.15)) { showLanguageTransition = false; languageGlow = false }
            }
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: beginLaunch)
        .task {
            await GhafWidgetSync.endStale()
        }
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
        let theme = GhafTheme.resolve(name: settings.first?.themeName ?? "Graphite",
                                      appearanceMode: settings.first?.appearanceMode ?? "System",
                                      systemIsDark: systemColorScheme == .dark)
        return ZStack {
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
                }
                .ghafProminentButton(theme: theme, languageCode: languageCode)
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
#if DEBUG
        if GhafScreenshotFixture.enabled, !GhafScreenshotFixture.launchNewUser, let currentSettings = settings.first {
            Group {
            switch GhafScreenshotFixture.screen {
            case "importSheet": GhafImportSheet(settings: currentSettings)
            case "automation": GhafAutomationGuideView(settings: currentSettings)
            case "about": GhafAboutView(settings: currentSettings)
            case "wallet": NavigationStack { GhafAccountsView(settings: currentSettings) }
            case "insights", "bar-sheet": GhafStatsView(settings: currentSettings).environment(fixtureRouter)
            case "transaction-detail": GhafFixtureTransactionDetailView(settings: currentSettings)
            case "subscriptions", "subscription-editor", "subscription-editor-filled": GhafSubscriptionsView(settings: currentSettings)
            case "settings-glass": GhafSettingsView(settings: currentSettings)
            case "milestone-proof": GhafSettingsView(settings: currentSettings)
            case "salary-settings": GhafSalarySettingsView(settings: currentSettings)
            case "budget-salary-currency": GhafBudgetView(settings: currentSettings)
            case "account-editor": NavigationStack { GhafAccountEditorView(account: nil, settings: currentSettings) }
            case "new-transaction": GhafTabView(settings: currentSettings, launchIsFinished: Binding(get: { !showLaunch }, set: { showLaunch = !$0 }))
            case "amount-pad": GhafTabView(settings: currentSettings, launchIsFinished: Binding(get: { !showLaunch }, set: { showLaunch = !$0 }))
            case nil where GhafScreenshotFixture.tab == "subscriptions": GhafSubscriptionsView(settings: currentSettings)
            default: GhafTabView(settings: currentSettings, launchIsFinished: Binding(get: { !showLaunch }, set: { showLaunch = !$0 }))
            }
            }
            // Fixture screens can present tab-owned settings and subscription children directly.
            // Give every route the same router environment as the production tab hierarchy.
            .environment(fixtureRouter)
        } else if let currentSettings = settings.first {
            if currentSettings.hasCompletedOnboarding {
                GhafTabView(settings: currentSettings, launchIsFinished: Binding(get: { !showLaunch }, set: { showLaunch = !$0 }))
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
#else
        if let currentSettings = settings.first {
            if currentSettings.hasCompletedOnboarding {
                GhafTabView(settings: currentSettings, launchIsFinished: Binding(get: { !showLaunch }, set: { showLaunch = !$0 }))
            } else {
                GhafOnboardingView(settings: currentSettings)
            }
        } else {
            ProgressView().tint(.white).task {
                do { _ = try GhafPersistence.settings(in: modelContext) }
                catch { print("Ghaf initialization error: \(error)") }
            }
        }
#endif
    }

    private func beginLaunch() {
        guard !launchHasStarted else { return }
        launchHasStarted = true
#if DEBUG
        if GhafScreenshotFixture.enabled && (!GhafScreenshotFixture.launchProof || GhafScreenshotFixture.onboardingStep != nil) { showLaunch = false; return }
#endif
        launchStartedAt = .now

        Task { @MainActor in
            let settingsDeadline = ContinuousClock.now + .milliseconds(600)
            while settings.first == nil, ContinuousClock.now < settingsDeadline, !launchSkipRequested {
                try? await Task.sleep(for: .milliseconds(40))
            }
            let settingsWait = min(0.6, Date.now.timeIntervalSince(launchStartedAt))
            let minimum = (launchFixtureProofEnabled ? 10.0 : (reduceMotion ? 1.2 : 2.4)) + settingsWait
            while Date.now.timeIntervalSince(launchStartedAt) < minimum && !launchSkipRequested {
                try? await Task.sleep(for: .milliseconds(40))
            }
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

    private var screenshotFixtureEnabled: Bool {
#if DEBUG
        GhafScreenshotFixture.enabled
#else
        false
#endif
    }

    private var launchFixtureProofEnabled: Bool {
#if DEBUG
        GhafScreenshotFixture.launchProof
#else
        false
#endif
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

#if DEBUG
private struct GhafFixtureTransactionDetailView: View {
    let settings: GhafSettings
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    @Query private var accounts: [GhafAccount]

    var body: some View {
        Group {
            if let transaction = transactions.first {
                NavigationStack { GhafTransactionDetailView(transaction: transaction, settings: settings, accounts: accounts) }
            } else {
                ContentUnavailableView("No fixture transaction", systemImage: "receipt")
            }
        }
    }
}
#endif

// MARK: - Main Tab Navigation

@Observable
final class GhafTabRouter {
    var selectedTab = 0
    /// Bumped after ledger edits so cached tab summaries refresh only when their inputs change.
    var ledgerRevision = 0
    /// Bumped when Home is tapped while already open; Home cycles Daily, Weekly, Monthly.
    var homeReselects = 0
    var isListening = false
    var startVoice: (() -> Void)?
    var typeQuestion: (() -> Void)?
    var pendingMilestone: Int?
    var isSaveSplashPresented = false
}

struct GhafTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ghafGlass) private var glass
    @Query(filter: #Predicate<GhafTransaction> { $0.needsReview }) private var reviewItems: [GhafTransaction]
    @Query(filter: #Predicate<GhafTransaction> { $0.isUnread }) private var unreadTransactions: [GhafTransaction]
    @Query(filter: #Predicate<GhafSubscription> { $0.needsConfirmation }) private var subscriptionReviewItems: [GhafSubscription]
    @State private var expandedOrb = false
    @State private var showOrbOverlay = false
    /// A stable reference in the environment: switching tabs never changes the tabs' inputs.
    @State private var router = GhafTabRouter()
    /// Opened from a Live Activity or widget link (ghaf://transaction/<UUID>).
    @State private var linkedTransaction: GhafTransaction?
    @State private var showWidgetQuickAdd = false
    @State private var showWidgetPro = false
    @State private var activeInAppCard: GhafInAppCardContent?
    @State private var queuedStreakMilestone: Int?
    @State private var queuedAnnouncement: GhafAnnouncement?
    @State private var streakHapticToken = 0
    @State private var celebratedCardIDs: Set<String> = []
    @State private var waitingForModalToClose = false
#if DEBUG
    @State private var speedReport = ""
#endif
    @Query private var linkAccounts: [GhafAccount]
    @AppStorage(GhafCalendar.weekStartKey) private var weekStart = 0
    /// Decoded once, not on every tab switch, so category icons are not invalidated needlessly.
    @State private var categoryMeta: [String: GhafCategoryMeta] = [:]

    let settings: GhafSettings
    @Binding var launchIsFinished: Bool

    private var summarySettingsKey: String {
        "\(settings.currency)|\(settings.categoriesJSON)|\(weekStart)|\(settings.languageCode)"
    }

#if DEBUG
    private var debugProofCard: GhafInAppCardContent? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-GhafStreakCardProof") { return .streak(days: 7) }
        if arguments.contains("-GhafAnnouncementCardProof") {
            let arabic = settings.languageCode == "ar"
            return .announcement(GhafAnnouncement(
                id: "proof-announcement", title: arabic ? "يتوفر تحديث غاف" : "A Ghaf update is ready",
                body: arabic ? "حدّث غاف للاستفادة من التحسينات الجديدة." : "Update Ghaf for the latest improvements.",
                code: arguments.contains("-GhafVoucherCardProof") ? "GHAF30" : nil,
                expires: .now.addingTimeInterval(86_400)))
        }
        return nil
    }
#endif

    private var cardForPresentation: GhafInAppCardContent? {
#if DEBUG
        activeInAppCard ?? debugProofCard
#else
        activeInAppCard
#endif
    }

    var body: some View {
        let theme = GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
        let reviewCount = reviewItems.count
        let hasUnreadTransactions = !unreadTransactions.isEmpty
        let subscriptionReviewCount = subscriptionReviewItems.count

        // Tapping Home again while it's open switches its period instead of doing nothing.
        let selection = Binding(get: { router.selectedTab }, set: { tab in
            if tab == 0 && router.selectedTab == 0 { router.homeReselects += 1 }
            if tab == 1 && router.selectedTab == 1 { router.startVoice?() }
            else if tab != router.selectedTab {
#if DEBUG
                GhafPerformanceProbe.beginTransition(to: tab)
#endif
                // Let TabView own its native selection transition. Animating offset + opacity
                // around the entire five-screen tree forced all tab content to redraw per frame.
                withTransaction(Transaction(animation: nil)) { router.selectedTab = tab }
            }
        })
        TabView(selection: selection) {
            GhafHomeView(settings: settings)
#if DEBUG
                .onAppear { speedReport = GhafPerformanceProbe.endTransition(on: 0) }
#endif
                .tabItem { tabIcon(Image(systemName: "house.fill"), settings.languageCode == "ar" ? "الرئيسية" : "Home", attentionCount: subscriptionReviewCount, accent: theme.accent, background: theme.background, reduceMotion: reduceMotion) }
                .tag(0)

            GhafTransactionsView(settings: settings)
#if DEBUG
                .onAppear { speedReport = GhafPerformanceProbe.endTransition(on: 3) }
#endif
                .tabItem { tabIcon(Image(systemName: "arrow.left.arrow.right"), settings.languageCode == "ar" ? "العمليات" : "Transactions", attentionCount: reviewCount, hasUnread: hasUnreadTransactions, accent: theme.accent, background: theme.background, reduceMotion: reduceMotion) }
                .tag(3)

            GhafAIView(settings: settings)
                // A full-colour orb as the tab's own icon: unlike the monochrome tabs, and placed by iOS
                // exactly where the tab is on every iPhone and tab bar layout.
                .tabItem {
                    tabIcon(Image(uiImage: UIImage()),
                            router.isListening ? (settings.languageCode == "ar" ? "غاف AI، يستمع" : "Ghaf AI, listening") : (settings.languageCode == "ar" ? "غاف AI" : "Ghaf AI"))
                }
                .tag(1)

            GhafStatsView(settings: settings)
#if DEBUG
                .onAppear { speedReport = GhafPerformanceProbe.endTransition(on: 2) }
#endif
                .tabItem { tabIcon(Image(systemName: "chart.bar.xaxis"), settings.languageCode == "ar" ? "الإحصائيات" : "Stats") }
                .tag(2)

            GhafSettingsView(settings: settings)
#if DEBUG
                .onAppear { speedReport = GhafPerformanceProbe.endTransition(on: 4) }
#endif
                .tabItem { tabIcon(Image(systemName: "ellipsis"), settings.languageCode == "ar" ? "المزيد" : "More") }
                .tag(4)
        }
#if DEBUG
        .overlay(alignment: .topLeading) {
            if GhafPerformanceProbe.enabled {
                Text(speedReport)
                    .accessibilityIdentifier("ghaf.speed.report")
                    .accessibilityLabel(speedReport)
                    .opacity(0.01)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
        }
#endif
        .onOpenURL { url in
            guard url.scheme == "ghaf" else { return }
            switch url.host {
            case "transaction":
                guard let id = UUID(uuidString: url.lastPathComponent) else { return }
                linkedTransaction = try? modelContext.fetch(FetchDescriptor<GhafTransaction>(predicate: #Predicate { $0.id == id })).first
                if linkedTransaction != nil { router.selectedTab = 3 }
            case "home": router.selectedTab = 0
            case "transactions": router.selectedTab = 3
            case "insights": router.selectedTab = 2
            case "add-transaction":
                showWidgetQuickAdd = true
            case "pro":
                showWidgetPro = true
            case "ai":
                router.selectedTab = 1
                if url.path == "/voice" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { router.startVoice?() } }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { router.typeQuestion?() } }
            case "money-tip":
                if let source = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "source" })?.value,
                   let sourceURL = URL(string: source), ["https", "http"].contains(sourceURL.scheme?.lowercased() ?? "") {
                    UIApplication.shared.open(sourceURL)
                }
            default: break
            }
        }
        .sheet(isPresented: $showWidgetQuickAdd) { GhafQuickAddView(settings: settings).ghafDirection(settings.languageCode) }
        .sheet(isPresented: $showWidgetPro) { GhafProSheet(settings: settings, feature: ("Widgets", "الودجات")).ghafDirection(settings.languageCode) }
        .sheet(item: $linkedTransaction) { transaction in
            NavigationStack { GhafTransactionDetailView(transaction: transaction, settings: settings, accounts: linkAccounts.filter { !$0.isArchived }) }
                .ghafDirection(settings.languageCode)
        }
        .overlay {
            GeometryReader { geometry in
                if subscriptionReviewCount > 0 {
                    GhafTabAttentionMark(accent: theme.accent, background: theme.background, reduceMotion: reduceMotion)
                        .position(x: geometry.size.width / 2 - (geometry.size.width - 80) / 5 * 2 + 12, y: geometry.size.height - 36)
                        .allowsHitTesting(false)
                }
                if hasUnreadTransactions {
                    GhafTabAttentionMark(accent: theme.accent, background: theme.background, reduceMotion: reduceMotion)
                        .accessibilityIdentifier("transactions-unread-dot")
                        .accessibilityLabel(settings.languageCode == "ar" ? "عملية جديدة" : "New transaction")
                        .position(x: geometry.size.width / 2 - (geometry.size.width - 80) / 5 + 12, y: geometry.size.height - 36)
                        .allowsHitTesting(false)
                }
                Group {
                    if router.isListening || showOrbOverlay {
                        GhafAIOrb(theme: theme, mood: .listening, level: 0)
                            .frame(width: 112, height: 112)
                            .scaleEffect(expandedOrb ? 1 : 26 / 112)
                    } else {
                        Image(uiImage: GhafAITabIcon.image(theme: theme, selected: router.selectedTab == 1))
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                    }
                }
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
                    .modifier(GhafOrbPressGesture(onTap: handleAITabOrbTap, onHold: handleAITabOrbHold))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(settings.languageCode == "ar" ? "غاف AI" : "Ghaf AI")
                    .accessibilityIdentifier("ghaf.ai.tab-orb")
                    .accessibilityAction(named: Text(settings.languageCode == "ar" ? "اكتب سؤالاً" : "Type a question")) { handleAITabOrbHold() }
                    .position(x: geometry.size.width / 2, y: geometry.size.height - 32)
            }
            // V6: measured from the screen bottom, not the keyboard, so the orb stays on the tab bar.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .modifier(GhafTabBarGlass(enabled: glass.enabled))
        .tint(theme.accent)
#if DEBUG
        .onAppear {
            if router.isListening {
                showOrbOverlay = true
                expandedOrb = true
            }
            guard GhafScreenshotFixture.enabled else { return }
            if GhafScreenshotFixture.attentionMarksFixture {
                GhafScreenshotFixture.seedAttentionMarks(in: modelContext)
            }
            switch GhafScreenshotFixture.tab {
            case "transactions": router.selectedTab = 3
            case "ai": router.selectedTab = 1
            case "more": router.selectedTab = 4
            case "insights": router.selectedTab = 2
            default: router.selectedTab = 0
            }
        }
#endif
        .sensoryFeedback(.selection, trigger: router.selectedTab)
        // Every SwiftData context in this process posts didSave, including contexts created by
        // App Intents. One revision invalidates all ledger-derived tab caches after any persisted
        // ledger or summary-setting change, regardless of which screen initiated the write.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { @MainActor in router.ledgerRevision += 1 }
        }
        .onChange(of: router.ledgerRevision) { _, _ in checkForStreakMilestone() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            checkForStreakMilestone()
            checkForAnnouncement()
        }
        .onAppear {
            GhafEventNotifications.configure()
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-GhafStreakLogToday") {
                logStreakProofTransactionIfNeeded()
            }
#endif
            checkForStreakMilestone()
            checkForAnnouncement()
#if DEBUG
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-GhafNotificationProof"),
               ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                GhafEventNotifications.scheduleDebugEvent(ProcessInfo.processInfo.arguments[index + 1])
            }
            if ProcessInfo.processInfo.arguments.contains("-GhafStreakCardProof") {
                queuedStreakMilestone = 7
                presentNextCard()
            }
            if ProcessInfo.processInfo.arguments.contains("-GhafAnnouncementCardProof") {
                let ar = settings.languageCode == "ar"
                queuedAnnouncement = GhafAnnouncement(
                    id: "proof-announcement", title: ar ? "يتوفر تحديث غاف" : "A Ghaf update is ready",
                    body: ar ? "حدّث غاف للاستفادة من التحسينات الجديدة." : "Update Ghaf for the latest improvements.",
                    code: ProcessInfo.processInfo.arguments.contains("-GhafVoucherCardProof") ? "GHAF30" : nil,
                    expires: .now.addingTimeInterval(86_400))
                presentNextCard()
            }
#endif
        }
        .onChange(of: showWidgetQuickAdd) { _, _ in presentNextCard() }
        .onChange(of: showWidgetPro) { _, _ in presentNextCard() }
        .onChange(of: linkedTransaction != nil) { _, _ in presentNextCard() }
        .onChange(of: showOrbOverlay) { _, _ in presentNextCard() }
        .onChange(of: router.isSaveSplashPresented) { _, _ in presentNextCard() }
        .onChange(of: launchIsFinished) { _, finished in
            guard finished else { return }
            checkForStreakMilestone()
            checkForAnnouncement()
            presentNextCard()
        }
        .onChange(of: summarySettingsKey) { _, _ in router.ledgerRevision += 1 }
        .onChange(of: router.isListening) { _, listening in
            if listening {
                showOrbOverlay = true
                withAnimation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.8)) { expandedOrb = true }
            } else if showOrbOverlay {
                withAnimation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.8),
                              completionCriteria: .logicallyComplete) { expandedOrb = false } completion: {
                    showOrbOverlay = false
                }
            }
        }
        .environment(router)
        .environment(\.ghafCategoryMeta, categoryMeta)
        .onChange(of: settings.categoryMetaJSON, initial: true) { categoryMeta = settings.categoryMeta }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let card = cardForPresentation,
               activeInAppCard == nil || (!showOrbOverlay && !router.isSaveSplashPresented && !showWidgetQuickAdd &&
                                          !showWidgetPro && linkedTransaction == nil && !hasModalPresentation && launchIsFinished) {
                GhafInAppCard(content: card, theme: theme, languageCode: settings.languageCode,
                              onAction: { performCardAction(card) },
                              onDismiss: { dismissCard(card) },
                              onAppear: { cardDidAppear(card) })
                    .padding(.horizontal, 18)
                    .padding(.bottom, 88)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .sensoryFeedback(.success, trigger: streakHapticToken)
        .preferredColorScheme(
            settings.appearanceMode == "Dark" || router.selectedTab == 1 ? .dark :
                settings.appearanceMode == "Light" ? .light : nil
        )
    }

    private func checkForStreakMilestone() {
#if DEBUG
        guard !GhafScreenshotFixture.snapshotTestingEnabled else { return }
#endif
        guard queuedStreakMilestone == nil else { return }
        guard let transactions = try? modelContext.fetch(FetchDescriptor<GhafTransaction>()) else { return }
        let dates = transactions.map { GhafLoggingStreak.Entry(date: $0.date, needsReview: $0.needsReview) }
        guard let milestone = GhafLoggingStreak.newlyReachedMilestone(
            dates: dates, now: .now, calendar: GhafCalendar.current,
            lastCelebrated: UserDefaults.standard.string(forKey: "ghaf.streak.lastCelebrated")
        ) else { return }
        queuedStreakMilestone = milestone
        presentNextCard()
    }

#if DEBUG
    private func logStreakProofTransactionIfNeeded() {
        let existing = (try? modelContext.fetch(FetchDescriptor<GhafTransaction>())) ?? []
        guard !existing.contains(where: { !$0.needsReview && Calendar.current.isDateInToday($0.date) }) else { return }
        let account = (try? modelContext.fetch(FetchDescriptor<GhafAccount>()))?.first
        let parsed = ParsedTransaction(amount: 35, currency: settings.currency, merchant: "Lunch", date: .now,
                                       direction: .debit, confidence: 1, bank: nil)
        modelContext.insert(GhafTransaction(fingerprint: "streak-ui-proof-\(UUID().uuidString)", parsed: parsed,
                                            category: "Food & Dining", needsReview: false, isReversal: false,
                                            accountID: account?.id))
        try? modelContext.save()
    }
#endif

    private func checkForAnnouncement() {
#if DEBUG
        guard !GhafScreenshotFixture.snapshotTestingEnabled else { return }
#endif
        guard activeInAppCard == nil, queuedAnnouncement == nil else { return }
        Task { @MainActor in
            guard let item = await GhafAnnouncementService.check(language: settings.languageCode) else { return }
            queuedAnnouncement = item
            presentNextCard()
        }
    }

    private func presentNextCard() {
#if DEBUG
        guard !GhafScreenshotFixture.snapshotTestingEnabled else { return }
#endif
        guard activeInAppCard == nil else { return }
        guard !showOrbOverlay, !router.isSaveSplashPresented, !showWidgetQuickAdd, !showWidgetPro,
              linkedTransaction == nil, !hasModalPresentation, launchIsFinished, scenePhase == .active else {
            waitForCardPresentationWindow()
            return
        }
        if let days = queuedStreakMilestone {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.86)) {
                activeInAppCard = .streak(days: days)
            }
            queuedStreakMilestone = nil
        } else if let item = queuedAnnouncement {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.86)) {
                activeInAppCard = .announcement(item)
            }
            queuedAnnouncement = nil
        }
    }

    private func cardDidAppear(_ card: GhafInAppCardContent) {
        guard celebratedCardIDs.insert(card.id).inserted else { return }
        guard case .streak(let days) = card,
              let transactions = try? modelContext.fetch(FetchDescriptor<GhafTransaction>()) else { return }
        let dates = transactions.map { GhafLoggingStreak.Entry(date: $0.date, needsReview: $0.needsReview) }
        if let key = GhafLoggingStreak.celebrationKey(for: days, dates: dates, now: .now, calendar: GhafCalendar.current) {
            UserDefaults.standard.set(key, forKey: "ghaf.streak.lastCelebrated")
        }
        GhafSounds.shared.play(.streak)
        streakHapticToken += 1
    }

    private var hasModalPresentation: Bool {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow),
              var controller = window.rootViewController else { return false }
        while let presented = controller.presentedViewController {
            if !presented.isBeingDismissed { return true }
            controller = presented
        }
        return false
    }

    private func waitForCardPresentationWindow() {
        guard !waitingForModalToClose else { return }
        waitingForModalToClose = true
        Task { @MainActor in
            while waitingForModalToClose {
                try? await Task.sleep(for: .milliseconds(350))
                guard scenePhase == .active else { continue }
                guard !showOrbOverlay, !router.isSaveSplashPresented, !showWidgetQuickAdd, !showWidgetPro,
                      linkedTransaction == nil, !hasModalPresentation, launchIsFinished else { continue }
                waitingForModalToClose = false
                presentNextCard()
            }
        }
    }

    private func performCardAction(_ card: GhafInAppCardContent) {
        switch card {
        case .streak(let days):
            router.pendingMilestone = days
            router.selectedTab = 4
        case .announcement(let item):
            if let code = item.code { UIPasteboard.general.string = code }
            else { UIApplication.shared.open(GhafLinks.appStore) }
        }
        dismissCard(card)
    }

    private func dismissCard(_ card: GhafInAppCardContent) {
        if case .announcement(let item) = card { GhafAnnouncementService.dismiss(item) }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.86)) {
            activeInAppCard = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { presentNextCard() }
    }

    private func handleAITabOrbTap() {
        guard router.selectedTab == 1 else {
            router.selectedTab = 1
            return
        }
        Task { @MainActor in
            for _ in 0..<15 {
                if let action = router.startVoice { action(); return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func handleAITabOrbHold() {
        router.selectedTab = 1
        Task { @MainActor in
            for _ in 0..<15 {
                if let action = router.typeQuestion { action(); return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

private struct GhafTabBarGlass: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.toolbarBackground(.ultraThinMaterial, for: .tabBar) }
        else { content }
    }
}

extension GhafTabView {
    /// Tabs show icons only; the title is still what VoiceOver reads.
    fileprivate func tabIcon(_ image: Image, _ title: String, attentionCount: Int = 0, hasUnread: Bool = false,
                             accent: Color = .accentColor, background: Color = .black,
                             reduceMotion: Bool = false) -> some View {
        image.accessibilityLabel(attentionCount > 0 ? "\(title), \(attentionCount) to review" : title)
            .accessibilityValue(hasUnread ? (title == "Transactions" ? "New transaction" : "عملية جديدة") : "")
    }
}

private struct GhafTabAttentionMark: View {
    let accent: Color
    let background: Color
    let reduceMotion: Bool
    @State private var appeared = false

    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: 9, height: 9)
            .padding(2)
            .background(background, in: Circle())
            .scaleEffect(appeared || reduceMotion ? 1 : 0.5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) { appeared = true }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
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
    @State private var userSex = "unspecified"
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
    @State private var showImportSheet = false
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
        _income = State(initialValue: "")
        _commitments = State(initialValue: "")
        _salaryAmountText = State(initialValue: "")
    }

    private let stepCount = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmRestart = false
    @State private var viewedGuide = false
    @State private var preset = BudgetAllocation.Preset.balanced
    @GestureState private var drag: CGFloat = 0
    @GestureState private var introPressed = false
    @State private var introCardsShown = false
    @State private var pageDirection = 1

    private var introCards: [GhafCardDesign] {
        let preferred = ["mashreq", "adcb", "enbd"].compactMap { bankID in
            GhafCardDesign.all.first { $0.bank == bankID }
        }
        return Array((preferred.count == 3 ? preferred : Array(GhafCardDesign.all.prefix(3))).prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button { move(to: step - 1) } label: {
                        Image(systemName: "chevron.backward").frame(width: 44, height: 44)
                    }.accessibilityLabel(localized("Back", "رجوع"))
                }
                Spacer()
                Menu {
                    Button(localized("Start over", "البدء من جديد"), role: .destructive) { confirmRestart = true }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel(localized("More options", "خيارات إضافية"))
                Button { languageCode = languageCode == "ar" ? "en" : "ar" } label: {
                    Text(languageCode == "ar" ? "EN" : "ع").padding(.horizontal, 18).frame(minHeight: 44)
                        .background(theme.surface, in: Capsule())
                }.accessibilityLabel(localized("العربية", "English"))
            }
            .buttonStyle(.plain).foregroundStyle(theme.primaryText)
            .padding(.horizontal, GhafMetrics.gutter)
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule().fill(index == step ? theme.primaryText : theme.secondaryText.opacity(0.35))
                        .frame(width: index == step ? 24 : 7, height: 7)
                }
            }.padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localized("Step \(step + 1) of \(stepCount)", "الخطوة \(step + 1) من \(stepCount)"))
            ScrollView {
                VStack(spacing: 24) {
                    // Owner 1.31: 4 feature cards, then name + sex → currency → first account → budget + salary day.
                    if step < 4 { intro }
                    else if step == 4 { profilePage }
                    else if step == 5 { currencyPage }
                    else if step == 6 { accountsPage }
                    else { budgetPage }
                }
                .padding(.horizontal, GhafMetrics.gutter).padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .id(step)
                .transition(reduceMotion ? .identity : .asymmetric(
                    insertion: .move(edge: pageDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: pageDirection > 0 ? .leading : .trailing).combined(with: .opacity)
                ))
            }
            .overlay(alignment: .top) {
                LinearGradient(stops: [.init(color: theme.background, location: 0), .init(color: theme.background, location: 0.45),
                                       .init(color: theme.background.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 32).allowsHitTesting(false)
            }
            .frame(maxHeight: .infinity)
            VStack(spacing: 8) {
                if step == 0 {
                    appleButton
                        .disabled(!GhafFeatureFlags.appStoreAccount)
                        .opacity(GhafFeatureFlags.appStoreAccount ? 1 : 0.4)
                    Text(localized("Coming soon", "قريباً"))
                        .font(GhafTypography.body(12, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                    primaryAction(localized("Continue", "متابعة")) { advance() }
                    // V1: restoring is the secondary path, a small link under Continue.
                    Button { showImportSheet = true } label: {
                        Text(localized("Restore from a Ghaf backup", "استعادة من نسخة غاف الاحتياطية"))
                            .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                } else if step == 7 {
                    primaryAction(localized("Start using Ghaf", "ابدأ استخدام غاف")) { advance() }
                    Button { showAutomationGuide = true } label: {
                        Text(localized("Set up automatic tracking", "إعداد التتبع التلقائي"))
                    }
                    .ghafGlassButton(theme: theme, languageCode: languageCode)
                } else {
                    primaryAction(localized("Continue", "متابعة")) { advance() }
                }
            }.buttonStyle(.plain).padding(.horizontal, GhafMetrics.gutter).padding(.vertical, 16)
                .background(theme.background.ignoresSafeArea(edges: .bottom))
        }
        .foregroundStyle(theme.primaryText)
        .background(theme.background.ignoresSafeArea())
        .environment(\.locale, Locale(identifier: languageCode))
#if DEBUG
        .onAppear {
            if let fixtureStep = GhafScreenshotFixture.onboardingStep {
                step = fixtureStep
                languageCode = GhafScreenshotFixture.language
                if fixtureStep >= 6, accountDrafts.isEmpty { accountDrafts = [GhafAccountDraft(name: "Mashreq", type: .debit, currency: "AED", startingBalance: "0")] }
            }
        }
#endif
        .environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
        .confirmationDialog(localized("Start over?", "هل تريد البدء من جديد؟"), isPresented: $confirmRestart, titleVisibility: .visible) {
            Button(localized("Start over", "البدء من جديد"), role: .destructive) { restart() }
            Button(localized("Cancel", "إلغاء"), role: .cancel) {}
        } message: { Text(localized("This clears the details you entered during setup.", "ستُحذف البيانات التي أدخلتها أثناء الإعداد.")) }
        .sheet(isPresented: $showAutomationGuide, onDismiss: { viewedGuide = true }) {
            NavigationStack {
                GhafAutomationGuideView(settings: GhafSettings(languageCode: languageCode, themeName: settings.themeName))
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button(localized("Done", "تم")) { showAutomationGuide = false }
                    } }
            }.environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $showImportSheet) { GhafImportSheet(settings: settings) }
        .alert(localized("Could not finish", "تعذر إكمال العملية"), isPresented: Binding(
            get: { backupImportError != nil }, set: { if !$0 { backupImportError = nil } }
        )) {
            Button(localized("OK", "حسناً"), role: .cancel) { backupImportError = nil }
        } message: { Text(backupImportError ?? "") }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            if case let .success(authorization) = result,
               let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                if let components = credential.fullName { name = PersonNameComponentsFormatter().string(from: components) }
                move(to: 1)
            } else if case let .failure(error) = result, (error as? ASAuthorizationError)?.code != .canceled {
                backupImportError = error.localizedDescription
            }
        }
        .signInWithAppleButtonStyle(theme.isDark ? .white : .black)
        .frame(height: 60).clipShape(Capsule())
            .accessibilityHint(GhafFeatureFlags.appStoreAccount ? "" : localized("Coming soon", "قريباً"))
    }

    private var intro: some View {
        let pages = [
            (localized("Your bank alerts, logged for you", "رسائل البنك تُسجَّل تلقائياً"), localized("Ghaf reads the bank messages you pass to it in Shortcuts and records each purchase once.", "يقرأ غاف رسائل البنك التي ترسلها له عبر الاختصارات ويسجّل كل عملية مرة واحدة.")),
            (localized("All your accounts in one place", "كل حساباتك في مكان واحد"), localized("Cards, bank accounts and cash, each with its own balance and currency.", "البطاقات والحسابات البنكية والنقد، لكلٍّ رصيده وعملته.")),
            (localized("Just say it", "قلها بصوتك"), localized("Tell Ghaf AI what you spent, in Arabic or English, and it adds it for you.", "قل لغاف ماذا صرفت، بالعربية أو الإنجليزية، ويضيفها لك.")),
            (localized("Subscriptions and budget at a glance", "الاشتراكات والميزانية بنظرة"), localized("See what's due next, and petals that fill as you spend each category.", "اعرف ما سيُدفع قريباً، وبتلات تمتلئ مع مصروف كل فئة."))
        ]
        let page = pages[step]
        return VStack(spacing: 20) {
            GhafWelcomeHero(step: step, theme: theme, languageCode: languageCode, cards: introCards)
                .id(step)
                .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 320)
                .background(GhafWelcomeGlow(theme: theme, step: step).padding(-140))
                .offset(x: reduceMotion ? 0 : drag * 0.08)
                .scaleEffect(introPressed && !reduceMotion ? 0.985 : 1)
                .animation(.spring(duration: 0.24, bounce: 0.08), value: introPressed)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($drag) { value, state, _ in state = value.translation.width }
                        .updating($introPressed) { value, state, _ in
                            state = abs(value.translation.width) < 10 && abs(value.translation.height) < 10
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > 56,
                                  abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                            let forward = languageCode == "ar" ? value.translation.width > 0 : value.translation.width < 0
                            move(to: min(max(step + (forward ? 1 : -1), 0), 3))
                        }
                )
                .accessibilityHidden(true)
            Text(page.0).font(GhafTypography.display(34, languageCode: languageCode))
            Text(page.1).font(GhafTypography.body(16, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
        }.multilineTextAlignment(.center)
    }


    private func illustrativeAccountRow(_ title: String, card: GhafCardDesign?, amount: Decimal) -> some View {
        HStack(spacing: 12) {
            if let card {
                card.image.resizable().scaledToFill().frame(width: 66, height: 42).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(GhafTypography.body(13, languageCode: "en", weight: .semibold)).lineLimit(1)
                GhafMoneyLabel(amount: amount, currency: "AED", languageCode: languageCode, size: 13, weight: .semibold)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 12).background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func permissionTile(icon: String, caption: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .medium)).foregroundStyle(theme.accent)
            Text(caption).font(GhafTypography.body(13, languageCode: languageCode, weight: .medium)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 112).background(theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func primaryAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .ghafProminentButton(theme: theme, languageCode: languageCode)
    }

    private func move(to page: Int) {
        guard (0..<stepCount).contains(page), page != step else { return }
        pageDirection = page > step ? 1 : -1
        withAnimation(reduceMotion ? .none : .spring(duration: 0.48, bounce: 0.15)) { step = page }
    }

    private func restart() {
        name = ""; income = ""; commitments = ""; salaryAmountText = ""; currency = "AED"
        languageCode = "en"; accountDrafts = []; balanceSetupMode = "zero"; salaryEnabled = false
        salaryDay = 28; salaryReminderEnabled = true; salaryAccountDraftID = nil
        preset = .balanced; accountSetupError = false; backupImportError = nil; viewedGuide = false; userSex = "unspecified"
        settings.userName = ""
        settings.languageCode = "en"
        settings.currency = "AED"
        settings.monthlyIncome = 0
        settings.fixedCommitments = 0
        settings.allocationPresetRaw = BudgetAllocation.Preset.balanced.rawValue
        settings.hasSeenAutomationIntro = false
        settings.balanceSetupMode = "zero"
        settings.salaryEnabled = false
        settings.salaryDay = nil
        settings.salaryAmount = nil
        settings.salaryCurrency = "AED"
        settings.salaryAccountID = nil
        settings.salaryReminderEnabled = false
        do { try modelContext.save() }
        catch { backupImportError = error.localizedDescription }
        move(to: 0)
    }

    private var profilePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localized("What should Ghaf call you?", "بماذا يناديك غاف؟"))
                .font(GhafTypography.display(32, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Text(localized("Ghaf AI uses your sex for the right Arabic forms. You can change it in Profile.", "يستخدم غاف جنسك لمخاطبتك بالصيغة الصحيحة. يمكنك تغييره من الملف الشخصي."))
                .font(GhafTypography.body(15, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            formLabel(localized("Your name", "اسمك"))
            onboardingField(localized("Name", "الاسم"), text: $name)
            formLabel(localized("Sex", "الجنس"))
            GhafSegmented(options: [("male", localized("Male", "ذكر")), ("female", localized("Female", "أنثى")), ("unspecified", localized("Prefer not to say", "أفضّل عدم الذكر"))],
                          selection: $userSex, theme: theme, languageCode: languageCode)
        }
    }

    private var currencyPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localized("Your main currency", "عملتك الرئيسية"))
                .font(GhafTypography.display(32, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Text(localized("Totals and budgets use it. Each account can still have its own currency.", "تُحسب بها المجاميع والميزانية، ويبقى لكل حساب عملته."))
                .font(GhafTypography.body(15, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(currencies, id: \.self) { code in
                    let picked = code == currency
                    Button { withAnimation(reduceMotion ? nil : .snappy) { currency = code } } label: {
                        VStack(spacing: 8) {
                            GhafCurrencyIcon(currency: code, size: 28)
                            Text(Locale(identifier: languageCode).localizedString(forCurrencyCode: code) ?? code)
                                .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(picked ? theme.background : theme.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .background(picked ? theme.primaryText : theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.ghafPress)
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
        }
    }

    private var budgetPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localized("Your budget and salary day", "ميزانيتك ويوم راتبك"))
                .font(GhafTypography.display(32, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Text(localized("These numbers help calculate a realistic daily spending limit.", "تساعد هذه البيانات على حساب حد إنفاق يومي واقعي."))
                .font(GhafTypography.body(15, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            GhafAmountField(value: $income, currency: currency, label: localized("Monthly income", "الدخل الشهري"), theme: theme, languageCode: languageCode, fontSize: 44, chromeless: true)
            budgetPreview

            formLabel(localized("Fixed monthly commitments", "الالتزامات الشهرية الثابتة"))
            onboardingField(localized("e.g. 1500", "مثال: ١٥٠٠"), text: $commitments, numeric: true)

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

            Text(localized("You can change all of these values later in Settings.", "يمكنك تعديل جميع هذه البيانات لاحقاً من الإعدادات."))
                .font(GhafTypography.body(13, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var budgetPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            formLabel(localized("Needs / Wants / Savings", "الاحتياجات / الرغبات / الادخار"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) { presetButtons }
        }.frame(maxWidth: .infinity)
    }

    private var presetButtons: some View {
        ForEach(BudgetAllocation.Preset.allCases, id: \.self) { option in
            Button { withAnimation(reduceMotion ? nil : .snappy) { preset = option } } label: {
                Text(option.title)
                    .font(GhafTypography.number(16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(option == preset ? theme.background : theme.primaryText)
                    .background(option == preset ? theme.primaryText : theme.surface, in: Capsule())
            }.buttonStyle(.plain).accessibilityAddTraits(option == preset ? .isSelected : [])
        }
    }

    private var accountsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(languageCode == "ar" ? "أين تحتفظ بأموالك؟" : "Where do you keep your money?")
                .font(GhafTypography.display(31, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Text(languageCode == "ar"
                 ? "أضف محفظتك النقدية وبطاقاتك وحساباتك. كل رصيد سيبقى منفصلاً بعملته."
                 : "Add your cash wallet, cards and bank accounts. Each balance stays separate in its own currency.")
                .font(GhafTypography.body(14, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

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
                    .padding(GhafMetrics.cardPadding)
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
                }
                .ghafGlassButton(theme: theme, languageCode: languageCode)
            }

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
        TextField(text: text) {
            Text(placeholder).foregroundStyle(theme.primaryText.opacity(0.78))
        }
            .font(GhafTypography.body(16, languageCode: languageCode))
            .keyboardType(numeric ? .decimalPad : .default)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 14, style: .continuous), fallback: theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.outline, lineWidth: 1))
    }

    private func advance() {
        if step < 6 { move(to: step + 1); return }
        if step == 6 {
            guard accountDrafts.allSatisfy({ draft in
                !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                (balanceSetupMode != "manual" || (Decimal(string: draft.startingBalance) ?? -1) >= 0)
            }) else { accountSetupError = true; return }
            accountSetupError = false
            move(to: 7)
            return
        }
        settings.userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.userSex = userSex
        settings.currency = currency
        settings.languageCode = languageCode
        settings.monthlyIncome = Decimal(string: income) ?? 0
        settings.fixedCommitments = Decimal(string: commitments) ?? 0
        settings.allocationPresetRaw = preset.rawValue
        settings.hasSeenAutomationIntro = viewedGuide
        settings.hasCompletedOnboarding = true
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
            accountSetupError = false
            if salaryEnabled && salaryReminderEnabled {
                Task {
                    _ = await GhafSalaryReminderService.requestPermission()
                    try? await GhafSalaryReminderService.scheduleNext(
                        salaryDay: salaryDay,
                        languageCode: languageCode,
                        salaryAmount: settings.salaryAmount,
                        salaryCurrency: settings.salaryCurrency ?? settings.currency
                    )
                }
            }
        } catch {
            modelContext.rollback()
            backupImportError = error.localizedDescription
        }
    }
}

// MARK: - Branded cold-launch welcome

/// Shown on every fresh app process launch, deliberately separate from onboarding completion, so returning
/// users see it without repeating setup or resetting data. Never shown on return from the background.
/// Canvas "Cold start": a centred greeting, three tilted rows of cards drifting
/// in opposite directions, the theme's light rising from the bottom and a slim loading bar.
private struct GhafWelcomeLaunchScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    let settings: GhafSettings?
    let onSkip: () -> Void
    @State private var shown = false
    @State private var start = Date()
    @State private var sweep = false

    init(settings: GhafSettings?, onSkip: @escaping () -> Void) {
        self.settings = settings
        self.onSkip = onSkip
    }

    private var ar: Bool { settings?.languageCode == "ar" }
    private var lang: String { settings?.languageCode ?? "en" }
    private var returning: Bool { settings?.hasCompletedOnboarding == true }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings?.themeName ?? "Graphite", appearanceMode: settings?.appearanceMode ?? "System",
                          systemIsDark: colorScheme == .dark)
    }
    private var name: String {
        let value = settings?.userName.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? (ar ? "غاف" : "Ghaf") : value
    }
    private struct WallCard: Identifiable {
        let id: String
        let bank: String
        let view: AnyView
        let isOwn: Bool
    }

    private var wallCards: [WallCard] {
        var seenOwnDesigns = Set<String>()
        let own = accounts.filter { !$0.isArchived && $0.type != .cash }.compactMap { account -> WallCard? in
            guard let design = GhafCardDesign.forAccount(account), design.bank != "cash" else { return nil }
            guard seenOwnDesigns.insert(design.id).inserted else { return nil }
            return WallCard(id: design.id, bank: design.bank,
                            view: AnyView(GhafCardFace(account: account, name: account.name,
                                                       institution: account.institution ?? "",
                                                       lastFour: account.lastFourDigits ?? "", design: design, width: 150)),
                            isOwn: true)
        }
        let ownDesigns = Set(own.map(\.id))
        let ownBanks = Set(own.map(\.bank))
        var seenBanks = Set<String>()
        let generic = GhafCardDesign.all.filter {
            $0.bank != "cash" && !ownBanks.contains($0.bank) && !ownDesigns.contains($0.id)
                && seenBanks.insert($0.bank).inserted
        }.map { design in
            WallCard(id: design.id, bank: design.bank,
                     view: AnyView(GhafCardFace(account: nil, design: design, width: 150)), isOwn: false)
        }
        return own + generic
    }

    var body: some View {
        GeometryReader { geometry in
            let cards = wallCards
            let own = cards.filter(\.isOwn)
            let generic = cards.filter { !$0.isOwn }
            let genericRows = (0..<3).map { row in generic.enumerated().compactMap { $0.offset % 3 == row ? $0.element : nil } }
            let rowA = own + genericRows[0]
            let rowB = genericRows[1]
            let rowC = genericRows[2]
            ZStack(alignment: .bottom) {
                theme.background.ignoresSafeArea()
                // A soft accent glow; a full-strength fill turned into a white slab on Graphite.
                LinearGradient(stops: [.init(color: theme.accent.opacity(0), location: 0),
                                       .init(color: theme.accent.opacity(0.14), location: 0.55),
                                       .init(color: theme.accent.opacity(0.28), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 430).ignoresSafeArea(edges: .bottom)
                VStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text(returning ? (ar ? "أهلاً بعودتك،" : "Welcome back,") : (ar ? "أهلاً بك في" : "Welcome to"))
                            .font(GhafTypography.body(17, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                        Text(returning ? name : (ar ? "غاف" : "Ghaf"))
                            .font(GhafTypography.display(44, languageCode: returning && name.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) } ? "en" : lang))
                            .foregroundStyle(theme.primaryText).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 94)
                    .opacity(shown ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 14)
                    Spacer(minLength: 0)
                }
                TimelineView(.animation(paused: reduceMotion)) { context in
                    GeometryReader { rowGeometry in
                        VStack(spacing: 12) {
                            cardRow(rowA, genericCount: genericRows[0].count, seconds: context.date.timeIntervalSince(start), speed: 57, forward: true, width: rowGeometry.size.width)
                            cardRow(rowB, genericCount: rowB.count, seconds: context.date.timeIntervalSince(start), speed: 46, forward: false, width: rowGeometry.size.width)
                            cardRow(rowC, genericCount: rowC.count, seconds: context.date.timeIntervalSince(start), speed: 53, forward: true, width: rowGeometry.size.width)
                        }
                    }
                }
                .frame(height: geometry.size.height * 0.45, alignment: .bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .rotationEffect(.degrees(-6)).clipped()
                .environment(\.layoutDirection, .leftToRight).accessibilityHidden(true)
                .opacity(shown ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 14)
                LinearGradient(stops: [.init(color: theme.background.opacity(0), location: 0),
                                       .init(color: theme.background.opacity(0.82), location: 0.48),
                                       .init(color: theme.background, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * 0.45).frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea().allowsHitTesting(false)
                VStack(spacing: 12) {
                    loadingBar
                    Text(ar ? "جارٍ تحديث أرصدتك…" : "Updating your balances…")
                        .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .padding(.bottom, 56)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle()).onTapGesture(perform: onSkip)
        }
        .ignoresSafeArea()
        .ghafBackground(theme: theme)
        .accessibilityElement(children: .combine).accessibilityLabel("Ghaf is opening")
        .onAppear {
            start = .now
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.2)) { shown = true }
        }
    }

    private func cardRow(_ cards: [WallCard], genericCount: Int, seconds: TimeInterval, speed: Double, forward: Bool, width: CGFloat) -> some View {
        guard !cards.isEmpty else { return AnyView(EmptyView()) }
        let repeated = cards.filter { $0.isOwn } + cards.filter { !$0.isOwn } + cards.filter { !$0.isOwn }
        let setWidth = CGFloat(max(genericCount, 1)) * 162
        let shift = CGFloat((seconds * speed).truncatingRemainder(dividingBy: Double(setWidth)))
        return AnyView(HStack(spacing: 12) {
            ForEach(Array(repeated.enumerated()), id: \.offset) { _, card in card.view }
        }
        .offset(x: forward ? -shift : shift - setWidth / 2)
        .frame(width: width, alignment: .leading).clipped().drawingGroup())
    }

    private var loadingBar: some View {
        Capsule().fill(theme.primaryText.opacity(0.15)).frame(width: 120, height: 4)
            .overlay(alignment: .leading) {
                Capsule().fill(theme.primaryText).frame(width: 48, height: 4).offset(x: sweep ? 120 : -48)
            }
            .clipShape(Capsule())
            .onAppear {
                guard !reduceMotion else { sweep = true; return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { sweep = true }
            }
            .accessibilityHidden(true)
    }
}


/// Ghaf AI's tab icon: a glass orb in the theme's colours, kept in full colour.
@MainActor
enum GhafAITabIcon {
    private static var cache: [String: UIImage] = [:]

    static func image(theme: GhafTheme, selected: Bool) -> UIImage {
        let key = "\(theme.name)-\(theme.isDark)-\(selected)"
        if let cached = cache[key] { return cached }
        // The Ghaf AI orb, drawn by the same code as the AI screen. The dark palette's accent and glow are
        // the brighter pair, so it reads on light and dark tab bars.
        let side: CGFloat = selected ? 32 : 29
        let lit = GhafTheme.resolve(name: theme.name, appearanceMode: "Dark", systemIsDark: true)
        let mark = GhafAIOrbFace(theme: lit, mood: .idle, level: 0, time: 3.1, still: true, halo: false)
            .frame(width: side, height: side)
            .opacity(selected ? 1 : 0.82)
            .frame(width: 40, height: 40)
        let renderer = ImageRenderer(content: mark)
        renderer.scale = 3
        let image = (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysOriginal)
        cache[key] = image
        return image
    }
}
