import SwiftUI
import SwiftData
import AVFoundation
import Charts
import GhafCore
import OSLog
import Speech

private struct GhafChatMessage: Identifiable {
    enum DraftState { case pending, saved, discarded }
    let id = UUID()
    let isUser: Bool
    var text: String
    var isVoice = false
    var isStreaming = false
    var drafts: [GhafVoiceTransactionDraft] = []
    var draftState: DraftState = .pending
    var chart: GhafChatChart?
    /// Tappable next questions under an answer.
    var suggestions: [String] = []
    /// Transactions created when the drafts were saved, so later corrections can update them.
    var savedIDs: [UUID] = []
    /// "From 312 of your transactions · November", on answers computed from the ledger.
    var source: String?
    var memoryID: UUID?

    init(isUser: Bool, text: String, isVoice: Bool = false, isStreaming: Bool = false,
         drafts: [GhafVoiceTransactionDraft] = [], chart: GhafChatChart? = nil, suggestions: [String] = []) {
        self.isUser = isUser; self.text = text; self.isVoice = isVoice; self.isStreaming = isStreaming
        self.drafts = drafts; self.chart = chart; self.suggestions = suggestions
    }

    init(_ stored: GhafStoredChatMessage) {
        self.init(isUser: stored.isUser, text: stored.text, isVoice: stored.isVoice, chart: stored.chart)
        source = stored.source
        memoryID = stored.memoryID
    }

    var stored: GhafStoredChatMessage {
        GhafStoredChatMessage(isUser: isUser, text: text, isVoice: isVoice, source: source, chart: chart, memoryID: memoryID)
    }
}

struct GhafAIView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(GhafTabRouter.self) private var tabRouter
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @Query private var subscriptions: [GhafSubscription]
    @Query(sort: \MerchantCategoryRule.hits, order: .reverse) private var rules: [MerchantCategoryRule]
    @Query(sort: \GhafChat.updatedAt, order: .reverse) private var chats: [GhafChat]
    @Query(sort: \GhafMemory.updatedAt, order: .reverse) private var memories: [GhafMemory]
    /// The saved chat the open conversation belongs to; nil until its first message is kept.
    @State private var chatID: UUID?
    @State private var showHistory = false

    @StateObject private var assistant = GhafAssistant()
    @StateObject private var recorder = GhafSpeechRecorder()
    @StateObject private var liveCall = GhafLiveCall()
    @State private var progress = GhafAIProgress.shared
    @State private var completedProgressStages: [GhafAIStage] = []
    @State private var prompt = ""
    @State private var isTyping = false
    @State private var microphoneOff = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false
    @State private var messages: [GhafChatMessage] = []
    @State private var isThinking = false
    @State private var replyTask: Task<Void, Never>?
    @AppStorage("ghaf.ai.speakReplies") private var speakReplies = false
    @AppStorage("ghaf.ai.voiceCharacter") private var voiceCharacter = ""
    @AppStorage(GhafMemoryStore.enabledKey) private var memoryEnabled = GhafMemoryStore.defaultEnabled
    @AppStorage("ghaf.ai.liveConsentAccepted") private var liveConsentAccepted = false
    @State private var cloudSpeaking = false
    @State private var cloudSpeechLevel: Float = 0
    /// Set when Ghaf asked something out loud: it listens for the answer once it stops speaking.
    @State private var listenAfterSpeaking = false
    /// Hands-free conversation: listen, answer aloud, listen again, until the user ends it.
    @State private var voiceMode = false
    @State private var liveCallActive = false
    @State private var liveInputMessageID: UUID?
    @State private var liveOutputMessageID: UUID?
    @State private var liveInputText = ""
    @State private var liveOutputText = ""
    @State private var liveGroundingSources: [String] = []
    @State private var liveFacts = ""
    @FocusState private var inputFocused: Bool
    @State private var savedCount = 0
    /// Model availability is costly to query; read it when the tab appears, not on every render.
    @State private var engine: GhafAssistant.Engine = .basic
    @State private var offerCloud = false
    @State private var offerLiveConsent = false
    @State private var voiceUnavailable = false
    /// Live calls use stand-in voices; while the server keeps them off, the mic uses listen-then-answer instead.
    @State private var liveVoiceOff = false
    @State private var showVoicePicker = false
    @State private var voiceUsage: GhafVoiceUsage?
    @State private var voiceLimitReached = false
    @State private var voiceStartedAt = Date.now
    @State private var voiceGoodbyePlaying = false
    @State private var hasProAccess = GhafProAccess.hasAccess
    @State private var proAccessKnown = GhafProAccess.isKnown
    @State private var showProSheet = false
    @State private var liveTurnHasTransactionDrafts = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ghafGlass) private var glassStyle

    let settings: GhafSettings
    private var ar: Bool { settings.languageCode == "ar" }
    /// Ghaf AI is always the dark version of the user's city theme: near-black glass lit by the city's colours.
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                voiceOrbControl
                if messages.isEmpty {
                    ScrollView { welcome }
                        .scrollDismissesKeyboard(.interactively)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 14) {
                                if progress.stage != nil { progressLine }
                                ForEach($messages) { $message in
                                    bubble($message).id(message.id)
                                }
                                if isThinking && messages.last?.isStreaming != true { thinkingDots.id("thinking") }
                            }
                            .ghafScreenPadding()
                            .padding(.vertical, 12)
                            .frame(maxWidth: 620)
                            .frame(maxWidth: .infinity)
                        }
                        .defaultScrollAnchor(.bottom)
                        .scrollDismissesKeyboard(.interactively)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            VStack(spacing: 8) {
                                if microphoneOff { microphonePermissionHint }
                            }
                            .padding(.bottom, 12)
                        }
                        .onChange(of: messages.last?.text) { _, _ in
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                        }
                    }
                }
                if isTyping { typingInput.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .background {
                ZStack(alignment: .bottom) {
                    theme.background.ignoresSafeArea()
                    // Blue light rising from the bottom edge, brighter while Ghaf listens or thinks.
                    Ellipse()
                        .fill(RadialGradient(colors: [theme.glow.opacity(0.9), theme.accent.opacity(0.6), .clear],
                                             center: .center, startRadius: 0, endRadius: 260))
                        .frame(width: 560, height: 300)
                        .offset(y: 170)
                        .blur(radius: 40)
                        .opacity(isThinking || recorder.isRecording ? 1 : 0.7)
                        .animation(.easeInOut(duration: 0.6), value: isThinking || recorder.isRecording)
                        .ignoresSafeArea()
                }
                .allowsHitTesting(false)
            }
            .toolbar(.hidden, for: .navigationBar)
            .modifier(GhafHideTabBar(forceDark: false))
            .environment(\.colorScheme, theme.isDark ? .dark : .light) // owner 1.31: AI follows the theme
            .sensoryFeedback(.success, trigger: savedCount)
            .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isRecording)
            .onChange(of: recorder.finishedSpeakingCount) { _, _ in finishVoice() }
            .onChange(of: recorder.transcript) { _, text in
                if recorder.isRecording { prompt = text }
            }
            .onChange(of: inputFocused) { _, focused in if !focused && isTyping { closeTyping() } }
            .onChange(of: isTyping) { _, typing in
                guard typing else { return }
                DispatchQueue.main.async { inputFocused = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GhafReloadAILimits"))) { _ in
                Task { await reloadAILimits() }
            }
            .onChange(of: progress.stage) { oldStage, newStage in
                if let oldStage, oldStage != newStage { completedProgressStages.append(oldStage) }
            }
            .onAppear {
                isOnScreen = true
                expireIfStale()
                engine = assistant.engine
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-GhafAIProTestAccess") {
                    hasProAccess = GhafProAccess.hasAccess
                    proAccessKnown = true
                    if ProcessInfo.processInfo.arguments.contains("-GhafAIUsageFixture") {
                        voiceUsage = GhafVoiceUsage(used: 1, limit: 3, resetsAt: Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400))
                    }
                }
#endif
                Task {
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-GhafAIProTestAccess") {
                        if !ProcessInfo.processInfo.arguments.contains("-GhafAIUsageFixture") {
                            voiceUsage = GhafVoiceUsage(used: 0, limit: 3, resetsAt: Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400))
                        }
                        return
                    }
#endif
                    await reloadAILimits()
                }
                tabRouter.startVoice = { toggleVoiceInput() }
                tabRouter.typeQuestion = { openTyping() }
#if DEBUG
                if GhafScreenshotFixture.enabled {
                    if let fixture = GhafScreenshotFixture.progressStageFixture {
                        let query = GhafLedgerAnswers.progressQuery(for: "How much did I spend this month?", transactions: transactions,
                                                                    currency: settings.currency, languageCode: settings.languageCode)
                        switch fixture {
                        case "listening": progress.stage = .listening; tabRouter.isListening = true
                        case "transcribing": progress.stage = .transcribing
                        case "checking": if let query { progress.stage = .checkingTransactions(count: query.transactionCount, period: query.period) }
                        case "adding": if let query, let count = query.purchaseCount { progress.stage = .addingPurchases(count) }
                        case "asking": progress.stage = .askingAI
                        case "chart": progress.stage = .drawingChart
                        case "draft": progress.stage = .preparingDraft
                        default: break
                        }
                    }
                    if GhafScreenshotFixture.destination == "ai-typing" { openTyping() }
                    if GhafScreenshotFixture.destination == "ai-conversation", messages.isEmpty {
                        // A stable local fixture lets UI proof cover answer chips without
                        // making a live model request or relying on network availability.
                        let question = settings.languageCode == "ar" ? "كم صرفت هذا الأسبوع؟" : "How much did I spend this week?"
                        let answer = GhafLedgerAnswers.answer(to: question, accounts: accounts,
                                                              transactions: transactions, subscriptions: subscriptions,
                                                              currency: settings.currency, languageCode: settings.languageCode)
                            ?? "The ledger doesn't have enough information to answer that yet."
                        messages = [
                            GhafChatMessage(isUser: true, text: question),
                            GhafChatMessage(isUser: false, text: answer,
                                            suggestions: ChatFollowUp.suggestions(after: question,
                                                                                 languageCode: settings.languageCode))
                        ]
                    }
                    if GhafScreenshotFixture.destination == "ai-draft", messages.isEmpty {
                        var draft = GhafVoiceTransactionParser.parse(
                            settings.languageCode == "ar" ? "صرفت 32 على الطعام الساعة 9 مساءً" : "spent 32 on food at 9 pm",
                            languageCode: settings.languageCode, baseCurrency: settings.currency
                        ).first
                        draft?.category = "Dining"
                        draft?.accountID = accounts.first(where: { $0.isPrimary && !$0.isArchived })?.id
                        if let draft {
                            messages = [GhafChatMessage(isUser: false, text: settings.languageCode == "ar" ? "راجع العملية ثم احفظها:" : "Review this transaction, then save:", drafts: [draft])]
                        }
                    }
                    if GhafScreenshotFixture.destination == "ai-subscription-answer", messages.isEmpty {
                        // Exercise the real ledger answer for subscription renewal dates in screenshots/tests.
                        let question = "Which subscriptions are due soon?"
                        let answer = GhafLedgerAnswers.answer(to: question, accounts: accounts,
                                                              transactions: transactions, subscriptions: subscriptions,
                                                              currency: settings.currency, languageCode: settings.languageCode)
                            ?? "The ledger doesn't have enough information to answer that yet."
                        messages = [
                            GhafChatMessage(isUser: true, text: question),
                            GhafChatMessage(isUser: false, text: answer,
                                            suggestions: ChatFollowUp.suggestions(after: question,
                                                                                 languageCode: settings.languageCode))
                        ]
                    }
                }
#endif
            }
            .onChange(of: scenePhase) { _, phase in
                // Only while Ghaf AI is on screen: backgrounding from another tab is not AI activity.
                guard isOnScreen else { return }
                if phase == .active { expireIfStale() } else { Self.stampActive() }
            }
            .onDisappear {
                isOnScreen = false
                Self.stampActive()
                recorder.reset()
                tabRouter.isListening = false
                progress.stage = nil
                tabRouter.startVoice = nil
                tabRouter.typeQuestion = nil
                stopSpeaking()
                liveCall.end()
                persistChat()
            }
            .onChange(of: isThinking) { _, thinking in if !thinking { persistChat() } }
            .onChange(of: recorder.isRecording) { _, listening in tabRouter.isListening = listening }
            .onChange(of: messages.count) { _, _ in if !isThinking { persistChat() } }
            .onChange(of: liveCall.phase) { _, phase in
                if case .ended(let reason) = phase, liveCallActive {
                    liveCallActive = false
                    tabRouter.isListening = false
                    if reason == "connection_lost" {
                        appendCallNote(ar ? "تعذّر الرد الآن. حاول مرة أخرى لاحقاً." : "Sorry, I can't answer right now. Try again in a moment.")
                        playVoiceError()
                    }
                    if reason == "turn_limit" {
                        appendCallNote(ar ? "تعذّر الرد الآن. حاول مرة أخرى لاحقاً." : "Sorry, I can't answer right now. Try again in a moment.")
                        playVoiceError()
                    }
                }
            }
            .overlay {
                if !proAccessKnown {
                    ProgressView().tint(theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.background.ignoresSafeArea())
                } else if !hasProAccess { aiProPaywall.ignoresSafeArea() }
            }
            .onReceive(NotificationCenter.default.publisher(for: GhafCloudAI.accessRevoked)) { _ in
                hasProAccess = false
                proAccessKnown = true
                voiceUsage = nil
                tabRouter.isListening = false
            }
            .sheet(isPresented: $showProSheet, onDismiss: {
                Task {
                    _ = await GhafAITier.refreshVerifiedEntitlement()
                    hasProAccess = GhafProAccess.hasAccess
                    proAccessKnown = true
                    if hasProAccess { voiceUsage = await GhafCloudAI.voiceUsage() }
                }
            }) {
                GhafProSheet(settings: settings, feature: ("Ghaf AI", "غاف AI"))
                    .ghafDirection(settings.languageCode)
            }
        }
    }

    private var aiProPaywall: some View {
        VStack(spacing: 20) {
            // Owner 1.31: free users see a blurred preview of the orb, with a lock on top.
            GhafAIOrb(theme: theme, mood: .idle)
                .frame(width: 150, height: 150)
                .blur(radius: 2.5)
                .overlay { Image(systemName: "lock.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(theme.primaryText) }
                .accessibilityHidden(true)
            Text(ar ? "غاف AI متاح لمشتركي غاف برو" : "Ghaf AI is for Pro members")
                .font(GhafTypography.display(30, languageCode: settings.languageCode))
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.primaryText)
            Text(ar ? "اسأل عن إنفاقك وحساباتك، وتحدث مع مساعدك الصوتي." : "Ask about your spending and accounts, and talk with your financial assistant.")
                .font(GhafTypography.body(16, languageCode: settings.languageCode))
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.secondaryText)
            VStack(spacing: 12) {
                Button { showProSheet = true } label: {
                    Text(ar ? "الأساسية · 3 ردود صوتية يوميًا" : "Essentials · 3 voice replies a day")
                        .frame(maxWidth: .infinity)
                }.ghafProminentButton(theme: theme, languageCode: settings.languageCode)
                Button { showProSheet = true } label: {
                    Text(ar ? "الكاملة · 10 ردود صوتية يوميًا" : "Complete · 10 voice replies a day")
                        .frame(maxWidth: .infinity)
                }.ghafGlassButton(theme: theme, languageCode: settings.languageCode)
            }
            .frame(maxWidth: 360)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
        .accessibilityIdentifier("ghaf.ai.pro-paywall")
    }

    private var progressLine: some View {
        Group {
            if !completedProgressStages.isEmpty || progress.stage != nil {
                VStack(spacing: 8) {
                    ForEach(completedProgressStages.indices, id: \.self) { index in
                        progressChip(completedProgressStages[index], active: false)
                    }
                    if let stage = progress.stage { progressChip(stage, active: true).id(stage) }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: progress.stage)
    }

    private func progressChip(_ stage: GhafAIStage, active: Bool) -> some View {
        HStack(spacing: 9) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(4), spacing: 2), count: 3), spacing: 2) {
                ForEach(0..<9, id: \.self) { index in
                    if !active {
                        RoundedRectangle(cornerRadius: 1).fill(theme.accent.opacity(0.4)).frame(width: 4, height: 4)
                    } else if active {
                        RoundedRectangle(cornerRadius: 1).fill(theme.accent)
                            .frame(width: 4, height: 4)
                            .phaseAnimator(reduceMotion ? [0.6] : [0.15, 1.0]) { dot, phase in
                                dot.opacity(phase)
                            } animation: { _ in .easeInOut(duration: 1.1).delay(Double(index) * 0.08) }
                    } else {
                        RoundedRectangle(cornerRadius: 1).fill(theme.accent.opacity(0.15)).frame(width: 4, height: 4)
                    }
                }
            }
            .frame(width: 16, height: 16)
            Text(stage.label(languageCode: settings.languageCode) + (active && reduceMotion ? " …" : ""))
                .font(ar ? GhafTypography.body(14, languageCode: settings.languageCode, weight: .medium) : .system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.primaryText.opacity(0.06), in: Capsule())
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(active ? .updatesFrequently : [])
    }

    // MARK: Header

    private func glassCircle(_ symbol: String, tint: Color? = nil) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint ?? theme.primaryText)
            .frame(width: 44, height: 44)
            .background(theme.primaryText.opacity(0.06), in: Circle())
    }

    /// Engine, read-aloud and dictation; also reachable from the history sheet.
    private var optionsMenu: some View {
        Menu {
            if !messages.isEmpty {
                Button { startNewChat() } label: {
                    Label(ar ? "محادثة جديدة" : "New chat", systemImage: "square.and.pencil")
                }
            }
            Section(engineLabel) {
                if engine != .cloud {
                    Button { offerCloud = true } label: {
                        Label(ar ? "فعّل الذكاء السحابي" : "Turn on Cloud AI", systemImage: "cloud.fill")
                    }
                }
            }
            Button { showHistory = true } label: {
                Label(ar ? "المحادثات السابقة" : "Chat history", systemImage: "clock.arrow.circlepath")
            }
            Button {
                speakReplies.toggle()
                if !speakReplies { stopSpeaking() }
            } label: {
                Label(ar ? "قراءة الردود بصوت" : "Read replies aloud",
                      systemImage: speakReplies ? "checkmark" : "speaker.slash")
            }
            Button { startVoice() } label: {
                Label(ar ? "إملاء رسالة" : "Dictate a message", systemImage: "mic.fill")
            }
            .disabled(isThinking || recorder.isRecording)
            Button { showVoicePicker = true } label: {
                Label(ar ? "صوت غاف" : "Ghaf voice", systemImage: "waveform")
            }
        } label: {
            glassCircle("line.3.horizontal")
        }
        .accessibilityLabel(ar ? "قائمة غاف AI" : "Ghaf AI menu")
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                // Owner 1.31: Ghaf AI is full screen (no tab bar); back returns to the tab it was opened from.
                Button { tabRouter.selectedTab = tabRouter.tabBeforeAI } label: { glassCircle("chevron.backward") }
                    .accessibilityLabel(ar ? "رجوع" : "Back")
                    .accessibilityIdentifier("ghaf.ai.back")
                Spacer()
                optionsMenu
            }
            .overlay {
                Text("Ghaf AI")
                    .font(GhafTypography.heading(17, languageCode: "en"))
                    .foregroundStyle(theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .ghafScreenPadding()
        .padding(.top, 8)
        .sheet(isPresented: $showHistory) {
            AnyView(GhafChatHistorySheet(
                chats: chats, currentID: chatID, theme: theme, languageCode: settings.languageCode,
                engineLabel: engineLabel, speakReplies: $speakReplies,
                open: { chat in openChat(chat) },
                dictate: { showHistory = false; startVoice() },
                turnOnCloud: engine == .cloud ? nil : { showHistory = false; offerCloud = true },
                delete: { deleteChats($0) }
            )).ghafSheetFrame(theme: theme)
        }
        .confirmationDialog(ar ? "الذكاء السحابي" : "Cloud AI", isPresented: $offerCloud, titleVisibility: .visible) {
            Button(ar ? "تفعيل" : "Turn On") {
                UserDefaults.standard.set(true, forKey: GhafCloudAI.enabledKey)
                engine = assistant.engine
            }
        } message: {
            Text(GhafCloudAI.disclosure(ar: ar) + (ar ? " يمكنك إيقافه من «ما تعلّمه غاف»." : " Turn it off anytime in What Ghaf learned."))
        }
        .confirmationDialog(ar ? "رسالة صوتية إلى غاف" : "Voice message to Ghaf", isPresented: $offerLiveConsent, titleVisibility: .visible) {
            Button(ar ? "متابعة" : "Continue") { liveConsentAccepted = true; Task { await beginVoiceCall() } }
            Button(ar ? "إلغاء" : "Cancel", role: .cancel) { exitVoiceMode() }
        } message: {
            Text(GhafCloudAI.liveDisclosure(ar: ar))
        }
        .sheet(isPresented: $showVoicePicker) {
            GhafAIVoiceSettingsView(settings: settings, firstChoiceRequired: voiceCharacter.isEmpty)
                .presentationDetents([.medium, .large])
                .ghafSheetFrame(theme: theme)
        }
    }

    // MARK: History

    // Row 14: 15 minutes away from Ghaf AI starts a fresh chat; the old one stays in history (persistChat runs first).
    private static let lastActiveKey = "ghaf.ai.lastActive"
    private static func stampActive() { UserDefaults.standard.set(Date.now, forKey: lastActiveKey) }
    private func expireIfStale() {
        let last = UserDefaults.standard.object(forKey: Self.lastActiveKey) as? Date
        let busy = isThinking || recorder.isRecording || liveCallActive
        if !busy, !messages.isEmpty, AISessionExpiry.isStale(lastActive: last, now: .now) { startNewChat() }
        Self.stampActive()
    }

    private func startNewChat() {
        replyTask?.cancel()
        stopSpeaking()
        isThinking = false
        persistChat()
        chatID = nil
        withAnimation(.spring(duration: 0.35)) { messages.removeAll() }
    }

    private func openChat(_ chat: GhafChat) {
        replyTask?.cancel()
        stopSpeaking()
        isThinking = false
        persistChat()
        showHistory = false
        chatID = chat.id
        var restored = chat.messages.map(GhafChatMessage.init)
        if let last = restored.indices.last, !restored[last].isUser,
           let question = restored.last(where: \.isUser)?.text {
            restored[last].suggestions = suggestions(after: question)
        }
        withAnimation(.spring(duration: 0.35)) { messages = restored }
    }

    private func deleteChats(_ doomed: [GhafChat]) {
        if doomed.contains(where: { $0.id == chatID }) { chatID = nil; messages.removeAll() }
        doomed.forEach(modelContext.delete)
        do { try modelContext.save() } catch {
            Logger(subsystem: "com.ghaf.app", category: "ai").error("Deleting chats failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Keeps the open conversation in history once it has a question in it. Runs after each finished reply.
    private func persistChat() {
        let stored = messages.filter { !$0.isStreaming && (!$0.text.isEmpty || $0.chart != nil) }.map(\.stored)
        guard let first = stored.first(where: \.isUser) else { return }
        if let chatID, let chat = try? modelContext.fetch(FetchDescriptor<GhafChat>(predicate: #Predicate { $0.id == chatID })).first {
            guard chat.messagesData != (try? JSONEncoder().encode(stored)) else { return }
            chat.messages = stored
        } else {
            let chat = GhafChat(title: String(first.text.prefix(80)), messages: stored)
            modelContext.insert(chat)
            chatID = chat.id
        }
        do { try modelContext.save() } catch {
            Logger(subsystem: "com.ghaf.app", category: "ai").error("Saving chat failed: \(String(describing: error), privacy: .public)")
        }
    }

    private var engineLabel: String {
        switch engine {
        case .cloud: ar ? "الذكاء السحابي · يُرسل الملخص فقط" : "Cloud AI · only a summary is sent"
        case .onDevice: ar ? "ذكاء Apple على جهازك · خاص" : "Apple Intelligence on this iPhone · private"
        case .basic: ar ? "الوضع الأساسي · فعّل Apple Intelligence لمحادثة كاملة" : "Basic mode · turn on Apple Intelligence for full chat"
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            let name = (memoryEnabled ? memories.first(where: { $0.kind == "name" })?.text : nil)
                ?? settings.userName.split(separator: " ").first.map(String.init) ?? ""
            Text(name.isEmpty ? (ar ? "أهلاً" : "Hello") : (ar ? "أهلاً \(name)" : "Hello \(name)"))
                .font(GhafTypography.body(16, languageCode: settings.languageCode, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .padding(.top, 34)
            Text(ar ? "كيف أساعدك\nفي أموالك؟" : "How can I help\nwith your money?")
                .font(GhafTypography.display(32, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
            if progress.stage != nil { progressLine.padding(.top, 12) }
            let chips = ar
                ? ["كم أنفقت هذا الأسبوع؟", "أين أنفقت أكثر؟", "ما الاشتراكات القادمة؟"]
                : ["How much did I spend this week?", "Where did most of my money go?", "Which subscriptions are due soon?"]
            GhafFlowLayout(spacing: 10) {
                ForEach(chips, id: \.self) { chip in
                    GhafSecondaryButton(title: chip, theme: theme, languageCode: settings.languageCode, compact: true) { send(chip) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 26)
            if microphoneOff {
                microphonePermissionHint.padding(.top, 14)
            } else {
                Text(ar ? "اضغط على الدائرة للتحدث، واضغط مطولاً ثم ارفع إصبعك للكتابة" : "Tap the orb to talk · hold, then release to type")
                    .font(GhafTypography.body(13, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
            }
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
        .ghafScreenPadding()
    }

    private var voiceOrbControl: some View {
        Group {
            if orbMood == .listening {
                VStack(spacing: 12) {
                    orb(size: 183)
                    HStack(spacing: 12) {
                        TimelineView(.periodic(from: voiceStartedAt, by: 1)) { context in
                            let seconds = max(0, Int(context.date.timeIntervalSince(voiceStartedAt)))
                            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                        Button {
                            toggleVoiceInput()
                        } label: {
                            Label(ar ? "إيقاف" : "Stop", systemImage: "stop.fill")
                                .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                        }
                        .accessibilityIdentifier("ghaf.ai.stop-listening")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(theme.isDark ? Color(red: 30/255, green: 31/255, blue: 35/255).opacity(0.86) : theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(theme.outline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            } else {
                HStack(spacing: 12) {
                    orb(size: 32)
                    Text(ar ? "اضغط على الدائرة للتحدث" : "Tap the orb and talk")
                        .font(GhafTypography.body(14, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(action: openTyping) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(ar ? "اكتب سؤالاً" : "Type a question")
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 74)
                .background(theme.isDark ? Color(red: 30/255, green: 31/255, blue: 35/255).opacity(0.86) : theme.surface)
                .overlay(Capsule().stroke(theme.outline, lineWidth: 1))
                .clipShape(Capsule())
            }
            if hasProAccess, let voiceUsage { voiceLimitCounter(voiceUsage) }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55), value: orbMood == .listening)
    }

    private func orb(size: CGFloat) -> some View {
        GhafAIOrb(theme: theme, mood: orbMood, level: orbLevel)
            .onChange(of: orbLevel) { _, level in tabRouter.voiceLevel = level }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .modifier(GhafOrbPressGesture(
                onTap: { guard hasProAccess else { return }; toggleVoiceInput() },
                onHold: { guard hasProAccess else { return }; openTyping() }
            ))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ar ? "غاف AI. اضغط للتحدث أو اضغط مطولاً للكتابة" : "Ghaf AI. Tap to talk or hold to type")
            .accessibilityIdentifier("ghaf.ai.orb")
            .accessibilityAction(named: Text(ar ? "تحدث" : "Talk")) { toggleVoiceInput() }
            .accessibilityAction(named: Text(ar ? "اكتب سؤالاً" : "Type a question")) { openTyping() }
    }

    // MARK: Messages

    @ViewBuilder
    private func bubble(_ message: Binding<GhafChatMessage>) -> some View {
        let item = message.wrappedValue
        let inlineBars = item.chart.map { $0.kind == .categories && $0.style == .bar } ?? false
        let priorQuestion = messages[..<max(0, messages.firstIndex(where: { $0.id == item.id }) ?? 0)].last(where: \.isUser)?.text ?? item.text
        let followUps = item.suggestions.isEmpty
            ? ChatFollowUp.suggestions(after: priorQuestion, languageCode: settings.languageCode)
            : item.suggestions
        VStack(alignment: item.isUser ? .trailing : .leading, spacing: 8) {
            if !item.isUser && (item.source != nil || inlineBars || item.isVoice) && !item.text.isEmpty {
                answerCard(item, bars: inlineBars ? item.chart : nil)
            } else if !item.text.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    if item.isVoice { Image(systemName: "waveform").font(.system(size: 13, weight: .bold)) }
                    GhafMoneyText.text(item.text, size: 15)
                        .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: item.isUser ? .semibold : .regular))
                        .textSelection(.enabled)
                }
                .foregroundStyle(item.isUser ? theme.background : theme.primaryText)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background {
                    let shape = UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: item.isUser ? 22 : 6,
                                                       bottomTrailingRadius: item.isUser ? 6 : 22, topTrailingRadius: 22, style: .continuous)
                    if item.isUser { shape.fill(theme.primaryText) }
                    else { shape.fill(.ultraThinMaterial).overlay(shape.fill(theme.primaryText.opacity(0.04))).overlay(shape.stroke(theme.primaryText.opacity(0.14))) }
                }
                .contextMenu {
                    if item.isUser {
                        Button { prompt = item.text; openTyping() } label: {
                            Label(ar ? "تعديل وإعادة الإرسال" : "Edit & resend", systemImage: "pencil")
                        }
                    }
                    Button { UIPasteboard.general.string = item.text } label: {
                        Label(ar ? "نسخ" : "Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: item.text) { Label(ar ? "مشاركة" : "Share", systemImage: "square.and.arrow.up") }
                }
            }
            if let chart = item.chart, !inlineBars || item.text.isEmpty {
                GhafChatChartView(chart: chart, theme: theme, languageCode: settings.languageCode)
                    .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
            }
            if !item.isUser && !item.isStreaming && item.drafts.isEmpty && !isThinking
                && item.id == messages.last(where: { !$0.isUser && !$0.isStreaming })?.id && !followUps.isEmpty {
                ScrollView {
                    GhafFlowLayout(spacing: 10) {
                        ForEach(followUps, id: \.self) { suggestion in
                            GhafSecondaryButton(title: suggestion, theme: theme, languageCode: settings.languageCode, compact: true) {
                                if ChatFollowUp.ledgerQuestion(for: suggestion, languageCode: settings.languageCode) != nil {
                                    answerFollowUpLocally(suggestion)
                                } else {
                                    send(suggestion)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !item.drafts.isEmpty { draftCard(message) }
            if let memoryID = item.memoryID {
                Button {
                    if let memory = memories.first(where: { $0.id == memoryID }) { modelContext.delete(memory) }
                    message.wrappedValue.memoryID = nil
                    try? modelContext.save()
                    persistChat()
                } label: {
                    Label(ar ? "انحفظ في الذاكرة · تراجع" : "Saved to memory · Undo", systemImage: "brain.head.profile")
                        .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: item.isUser ? .trailing : .leading)
        .padding(item.isUser ? .leading : .trailing, 40)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// The canvas answer card: where the numbers came from, the answer, and the top categories as inline bars.
    private func answerCard(_ item: GhafChatMessage, bars chart: GhafChatChart?) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6,
                                           bottomTrailingRadius: 22, topTrailingRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            if let source = item.source {
                Label(source, systemImage: "checkmark.seal.fill")
                    .labelStyle(GhafSourceLabelStyle())
                    .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .semibold))
                    .foregroundStyle(theme.glow)
            }
            (GhafMoneyText.text(item.text, size: 16) + Text(item.isStreaming ? " ▍" : "").foregroundStyle(theme.glow))
                .font(GhafTypography.body(16, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
                .lineSpacing(3)
                .textSelection(.enabled)
            if let chart, !item.isStreaming {
                GhafInlineBars(chart: chart, theme: theme, languageCode: settings.languageCode)
            }
        }
        .padding(GhafMetrics.cardPadding)
        .frame(maxWidth: 340, alignment: .leading)
        .background {
            if glassStyle.enabled { shape.fill(Color.clear) }
            else { shape.fill(.ultraThinMaterial).overlay(shape.fill(theme.primaryText.opacity(0.08))).overlay(shape.stroke(theme.primaryText.opacity(0.14))) }
        }
        .ghafGlassHero(theme: theme, radius: 22, fallback: .clear)
        .contextMenu {
            Button { UIPasteboard.general.string = item.text } label: { Label(ar ? "نسخ" : "Copy", systemImage: "doc.on.doc") }
            ShareLink(item: item.text) { Label(ar ? "مشاركة" : "Share", systemImage: "square.and.arrow.up") }
        }
    }

    private func draftCard(_ message: Binding<GhafChatMessage>) -> some View {
        let state = message.wrappedValue.draftState
        return VStack(spacing: 10) {
            ForEach(message.drafts) { $draft in
                VStack(alignment: .leading, spacing: 8) {
                    GhafTransactionSentenceCard(draft: $draft, accounts: accounts, transactions: transactions,
                                                theme: theme, languageCode: settings.languageCode, enabled: state == .pending)
                    GhafTextField(text: $draft.merchant, placeholder: ar ? "الاسم" : "Name", theme: theme, languageCode: settings.languageCode)
                        .disabled(state != .pending)
                    if state == .pending && isNewCategory(draft) {
                        Label(ar ? "جديدة · تُضاف عند الحفظ" : "New · added when you save", systemImage: "sparkles")
                            .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .bold))
                            .foregroundStyle(theme.accentContrast).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(theme.accent, in: Capsule())
                    }
                }
            }
            switch state {
            case .pending:
                HStack(spacing: 10) {
                    Button(ar ? "تجاهل" : "Discard") { message.wrappedValue.draftState = .discarded }
                        .ghafGlassButton(theme: theme, languageCode: settings.languageCode)
                    Button(ar ? "تأكيد" : "Confirm") { saveDrafts(message) }
                        .ghafProminentButton(theme: theme, languageCode: settings.languageCode)
                }
            case .saved:
                Label(ar ? "تم الحفظ" : "Saved", systemImage: "checkmark.circle.fill")
                    .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .bold))
                    .foregroundStyle(theme.credit)
            case .discarded:
                Label(ar ? "تم التجاهل" : "Discarded", systemImage: "xmark.circle")
                    .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(theme.primaryText.opacity(0.14)))
    }

    private var thinkingDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(theme.secondaryText).frame(width: 7, height: 7)
                    .phaseAnimator([0.3, 1.0]) { view, phase in view.opacity(phase) } animation: { _ in
                        .easeInOut(duration: 0.5).delay(Double(index) * 0.15)
                    }
            }
        }
        .padding(GhafMetrics.cardPadding)
        .background(theme.primaryText.opacity(0.08), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Input

    private var typingInput: some View {
        HStack(spacing: 8) {
            TextField("Type your question", text: $prompt,
                      prompt: Text("Type your question").foregroundStyle(theme.secondaryText))
                .focused($inputFocused)
                .accessibilityIdentifier("ghaf.ai.question")
                .font(GhafTypography.userContent(prompt.isEmpty ? "Type your question" : prompt, size: 17, languageCode: "en"))
                .foregroundStyle(theme.primaryText)
                .tint(theme.accent)
                .submitLabel(.send)
                .onSubmit(submitTypedQuestion)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button(action: submitTypedQuestion) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.accentContrast)
                    .frame(width: 44, height: 44)
                    .background(theme.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send")
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
            .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
        }
        .ghafScreenPadding()
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(theme.background)
    }

    private var microphonePermissionHint: some View {
        HStack(spacing: 4) {
            Text("Microphone is off — hold Ghaf AI in the tab bar to type")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Link("Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                .underline()
                .fixedSize()
        }
        .font(GhafTypography.body(13, languageCode: "en"))
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private func openTyping() {
        guard hasProAccess, !isThinking else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) { isTyping = true }
    }

    @MainActor
    private func reloadAILimits() async {
        hasProAccess = GhafProAccess.hasAccess
        proAccessKnown = GhafProAccess.isKnown
        _ = await GhafAITier.refreshVerifiedEntitlement()
        hasProAccess = GhafProAccess.hasAccess
        proAccessKnown = true
        guard hasProAccess else { return }
        await GhafCloudAI.prewarm()
        voiceUsage = await GhafCloudAI.voiceUsage()
    }

    private func closeTyping() {
        withAnimation(.snappy) { isTyping = false }
    }

    private func submitTypedQuestion() {
        let text = prompt
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        inputFocused = false
        closeTyping()
        send(text)
    }

    // MARK: Actions

    private func startVoice() {
        guard hasProAccess else { return }
        guard !voiceCharacter.isEmpty else { showVoicePicker = true; return }
        completedProgressStages.removeAll()
        if GhafCloudAI.isEnabled, !liveVoiceOff {
            guard !liveCallActive else {
                liveCall.end(reason: "user")
                liveCallActive = false
                tabRouter.isListening = false
                return
            }
            if !liveConsentAccepted { offerLiveConsent = true }
            else { Task { await beginVoiceCall() } }
            return
        }
        stopSpeaking()
        prompt = ""
        microphoneOff = false
        voiceStartedAt = .now
        closeTyping()
        inputFocused = false
        // Bias recognition towards this user's own merchants and categories.
        let hints = rules.prefix(60).map(\.normalizedMerchant)
            + settings.categories + settings.categories.flatMap(settings.subcategories(of:))
        tabRouter.isListening = true
        Task {
            await recorder.start(languageCode: settings.languageCode, hints: hints)
            let speechDenied = SFSpeechRecognizer.authorizationStatus() == .denied
            let microphoneDenied = AVAudioApplication.shared.recordPermission == .denied
            microphoneOff = speechDenied || microphoneDenied
            if microphoneOff { tabRouter.isListening = false }
        }
    }

    private func toggleVoiceInput() {
        guard hasProAccess else { return }
        if liveCallActive {
            if liveCall.phase == .speaking {
                liveCall.interruptPlayback()
                beginLiveUserTurn()
            } else if liveCall.isCapturingUserTurn {
                liveCall.endUserTurn()
                tabRouter.isListening = false
            } else if liveCall.phase != .thinking {
                beginLiveUserTurn()
            }
        } else if recorder.isRecording {
            GhafSounds.shared.play(.orbOff)
            recorder.stop()
            finishVoice()
        } else {
            GhafSounds.shared.play(.orbOn)
            startVoice()
        }
    }

    private func voiceLimitCounter(_ usage: GhafVoiceUsage) -> some View {
        let remaining = max(0, usage.limit - usage.used)
        let spokenCount = remaining.formatted(.number.locale(GhafLocale.locale(identifier: ar ? "ar" : "en")))
        let spokenLimit = usage.limit.formatted(.number.locale(GhafLocale.locale(identifier: ar ? "ar" : "en")))
        return VStack(spacing: 4) {
            Text(ar ? "تبقى \(spokenCount) من \(spokenLimit) رداً صوتياً اليوم" : "\(spokenCount) of \(spokenLimit) voice replies left today")
                .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
            GeometryReader { geometry in
                ZStack(alignment: ar ? .trailing : .leading) {
                    Capsule().fill(theme.outline.opacity(0.45))
                    Capsule().fill(LinearGradient(colors: [theme.accent, theme.glow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * CGFloat(usage.limit == 0 ? 0 : remaining) / CGFloat(max(usage.limit, 1)))
                }
            }
            .frame(height: 5)
            .accessibilityLabel(ar ? "الردود الصوتية المتبقية اليوم" : "Voice replies remaining today")
            .accessibilityValue("\(remaining) of \(usage.limit)")
        }
        .frame(maxWidth: 220)
        .frame(maxWidth: .infinity)
    }

    private func beginLiveUserTurn() {
        guard hasProAccess, liveCallActive, !voiceLimitReached else { return }
        if let usage = voiceUsage, usage.used >= usage.limit {
            handleDailyLimit()
            return
        }
        // Open the turn at once (the orb must feel instant); the reservation runs alongside it.
        liveCall.beginUserTurn()
        liveTurnHasTransactionDrafts = false
        tabRouter.isListening = true
        Task {
            // nil = network or server trouble: keep talking; /live-token still enforces the daily cap.
            guard let reservation = await GhafCloudAI.reserveVoiceTurn(languageCode: ar ? "ar" : "en") else { return }
            voiceUsage = reservation.usage
            guard !reservation.allowed else { return }
            liveCall.endUserTurn()
            tabRouter.isListening = false
            handleDailyLimit()
        }
    }

    private func handleDailyLimit() {
        voiceLimitReached = true
        liveCall.end(reason: "daily_limit")
        liveCallActive = false
        tabRouter.isListening = false
        let text = ar
            ? (settings.userSex == "male" ? "بلغت الحد اليومي للتسجيلات الصوتية." : settings.userSex == "female" ? "بلغت الحد اليومي للتسجيلات الصوتية." : "بلغ الحد اليومي للتسجيلات الصوتية.")
            : "You've reached today's voice limit."
        appendCallNote(text)
        // Owner 1.31: after the limit line, the subscription page opens.
        let finished = { voiceGoodbyePlaying = false; showProSheet = true }
        if GhafCloudVoice.shared.playBundledGoodbye(character: voiceCharacter, arabic: ar, userSex: settings.userSex, onFinish: finished) {
            voiceGoodbyePlaying = true
        } else { showProSheet = true }
    }

    private func playVoiceError() {
        _ = GhafCloudVoice.shared.playBundledError(character: voiceCharacter, arabic: ar, userSex: settings.userSex)
    }

    /// Called by the stop button, or automatically after a pause. Clear speech is sent;
    /// unclear speech is dropped.
    private func finishVoice() {
        recorder.stop()
        let text = (recorder.transcript.isEmpty ? prompt : recorder.transcript).trimmingCharacters(in: .whitespacesAndNewlines)
        recorder.reset()
        let letters = text.filter(\.isLetter).count
        let voiceDrafts = GhafMessageIntent.drafts(in: text, baseCurrency: settings.currency)
        let understood = GhafMessageIntent.isQuestion(text)
            || !voiceDrafts.isEmpty
            || MemoryIntent.parse(text) != nil
            || ChatCorrection.parse(text, recent: recentDraftRefs().map(\.name)) != nil
            || ChatEdit.parse(text, recent: recentDraftRefs().map(\.name)) != nil
        if (letters >= 2 || ChatEdit.parse(text, recent: []) == .confirm) && understood {
            if !voiceDrafts.isEmpty {
                Task { @MainActor in
                    progress.stage = .preparingDraft
                    await Task.yield()
                    send(text, isVoice: true)
                    progress.stage = nil
                }
            } else { send(text, isVoice: true) }
        } else {
            // Nothing usable: clear it and show a short note that removes itself.
            prompt = ""
            let note = GhafChatMessage(isUser: false, text: ar
                ? (settings.userSex == "male" ? "لم أفهم الجملة، هل يمكنك قولها بصيغة أخرى؟" : settings.userSex == "female" ? "لم أفهم الجملة، هل يمكنك قولها بصيغة أخرى؟" : "لم أفهم الجملة، هل يمكن قولها بصيغة أخرى؟")
                : "Sorry, I didn't catch that. Could you say it another way?")
            withAnimation(.snappy) { messages.append(note) }
            // Listening restarts only after the clip ends, so the mic never hears it.
            let relisten = { if voiceMode { startVoice() } }
            let speaking = hasProAccess && GhafCloudVoice.shared.playBundledNotHeard(character: voiceCharacter, arabic: ar, userSex: settings.userSex, onFinish: relisten)
            Task {
                if voiceMode, !speaking {
                    try? await Task.sleep(for: .seconds(1.2))
                    relisten()
                }
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.snappy) { messages.removeAll { $0.id == note.id } }
            }
        }
    }

    /// "4 dirhams at Karak, under Food. Should I save it?" — how a person would read the entries back.
    private func spokenSummary(_ drafts: [GhafVoiceTransactionDraft]) -> String {
        let parts = drafts.map { draft -> String in
            let money = "\(draft.currency) \(draft.amountText)"
            let category = GhafLocalization.category(draft.category, languageCode: settings.languageCode)
            let place = draft.merchant.isEmpty ? "" : (ar ? " في \(draft.merchant)" : " at \(draft.merchant)")
            return ar ? "\(money)\(place)، ضمن \(category)" : "\(money)\(place), under \(category)"
        }
        let list = parts.joined(separator: ar ? "، و" : "; and ")
        return drafts.count == 1
            ? (ar ? "\(list). أحفظها؟" : "\(list). Should I save it?")
            : (ar ? "سجلت \(drafts.count): \(list). أحفظها كلها؟" : "I have \(drafts.count): \(list). Save them all?")
    }

    /// "yes", "cancel", "remove the lunch", "rename karak to tea": acts on the latest drafts.
    private func applyEdit(_ text: String, isVoice: Bool) -> Bool {
        guard let m = messages.indices.last(where: { !messages[$0].drafts.isEmpty && messages[$0].draftState != .discarded }) else { return false }
        let names = messages[m].drafts.indices.reversed().map { messages[m].drafts[$0].merchant }
        guard let edit = ChatEdit.parse(text, recent: names) else { return false }
        let pending = messages[m].draftState == .pending
        var reply: String
        switch edit {
        case .confirm:
            guard pending else { return false }
            saveDrafts($messages[m])
            return true
        case .cancel:
            guard pending else { return false }
            messages[m].draftState = .discarded
            reply = ar ? "حسناً، لم يُحفَظ أي شيء." : "Okay, nothing saved."
        case .remove(let index):
            let draftIndex = messages[m].drafts.count - 1 - index
            guard pending else {
                reply = ar ? "هذه محفوظة. احذفها من العمليات." : "That one's already saved. Delete it from Transactions."
                break
            }
            let removed = messages[m].drafts.remove(at: draftIndex).merchant
            if messages[m].drafts.isEmpty { messages[m].draftState = .discarded }
            reply = ar ? "حذفت \(removed)." : "Removed \(removed)."
            if !messages[m].drafts.isEmpty { reply += ar ? " هل أحفظ بقية العمليات؟" : " Save the rest?"; listenAfterSpeaking = isVoice }
        case .rename(let index, let name):
            let draftIndex = messages[m].drafts.count - 1 - index
            let title = Self.tidyTitle(name)
            messages[m].drafts[draftIndex].merchant = title
            if !pending, draftIndex < messages[m].savedIDs.count {
                let id = messages[m].savedIDs[draftIndex]
                if let transaction = try? modelContext.fetch(FetchDescriptor<GhafTransaction>(predicate: #Predicate { $0.id == id })).first {
                    let raw = transaction.rawMerchant ?? transaction.merchant ?? title
                    GhafMerchantAliasStore.rename(raw, to: title)
                    transaction.rawMerchant = raw
                    try? modelContext.save()
                }
            }
            reply = ar ? "تم، صار اسمها \(title)." : "Done, it's now \(title)."
            if pending { reply += ar ? " أحفظها؟" : " Save it?"; listenAfterSpeaking = isVoice }
        }
        withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: false, text: reply)) }
        speak(reply, force: isVoice)
        return true
    }

    /// Latest draft entries first: (message index, draft index, name).
    private func recentDraftRefs() -> [(message: Int, draft: Int, name: String)] {
        messages.indices.reversed().flatMap { m in
            messages[m].draftState == .discarded ? [] :
                messages[m].drafts.indices.reversed().map { (m, $0, messages[m].drafts[$0].merchant) }
        }
    }

    /// "no, edit karak it was 5 dhs": updates the draft (or the saved transaction) in place.
    private func applyCorrection(_ text: String) -> Bool {
        let refs = recentDraftRefs()
        guard let result = ChatCorrection.parse(text, recent: refs.map(\.name)), let amount = result.amount else { return false }
        let ref = refs[result.index]
        messages[ref.message].drafts[ref.draft].amountText = NSDecimalNumber(decimal: amount).stringValue
        let draft = messages[ref.message].drafts[ref.draft]
        if messages[ref.message].draftState == .saved, ref.draft < messages[ref.message].savedIDs.count {
            let id = messages[ref.message].savedIDs[ref.draft]
            if let transaction = try? modelContext.fetch(FetchDescriptor<GhafTransaction>(predicate: #Predicate { $0.id == id })).first {
                transaction.amount = amount
                try? modelContext.save()
            }
        }
        let money = GhafFormat.money(amount, currency: draft.currency, languageCode: settings.languageCode)
        let reply = ar ? "تم. عدّلت \(draft.merchant) إلى \(money)." : "Done. Updated \(draft.merchant) to \(money)."
        withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: false, text: reply)) }
        savedCount += 1
        speak(reply)
        return true
    }

    private func send(_ raw: String, isVoice: Bool = false) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasProAccess, !text.isEmpty, !isThinking else { return }
        completedProgressStages.removeAll()
        prompt = ""
        withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: true, text: text, isVoice: isVoice)) }
        if liveCallActive { liveGroundingSources.append(text); liveCall.sendText(text); return }
        if let intent = MemoryIntent.parse(text) {
            if memoryEnabled {
                handleMemoryIntent(intent, source: "said")
            } else {
                let note = ar ? "الذاكرة متوقفة. يمكنك تشغيلها من المزيد ← ما تعلّمه غاف." : "Memory is off. Turn it on in More → What Ghaf learned."
                messages.append(GhafChatMessage(isUser: false, text: note))
                if voiceMode && !liveCallActive { listenAfterSpeaking = true; speak(note, force: true) }
            }
            return
        }
        if applyEdit(text, isVoice: isVoice) { return }
        if applyCorrection(text) { return }

        // A purchase ("35 AED lunch") becomes a draft card; anything else goes to the assistant.
        let drafts = preparedVoiceDrafts(in: text)
        if !drafts.isEmpty {
            let intro = ar
                ? (drafts.count == 1 ? "وجدت عملية. راجع الفئة ثم احفظ:" : "وجدت \(drafts.count) عمليات. راجعها ثم احفظ:")
                : (drafts.count == 1 ? "Got it. Check the category, then save:" : "I found \(drafts.count) transactions. Check them, then save:")
            let unmatched = drafts.filter { $0.category == "Other" && !$0.merchant.isEmpty }.map(\.merchant)
            let suggested = drafts.filter(isNewCategory).map { draft in
                "\(draft.merchant) → \(GhafLocalization.category(draft.category, languageCode: settings.languageCode))"
                    + (draft.subcategory.map { " › \(GhafLocalization.category($0, languageCode: settings.languageCode))" } ?? "")
            }
            var hint = ""
            if !suggested.isEmpty {
                hint += ar ? "\nاقتراح فئة جديدة: \(suggested.joined(separator: "، ")). ستُضاف عند الحفظ، ويمكنك تغييرها."
                           : "\nSuggested new category: \(suggested.joined(separator: ", ")). It's added when you save, or tap it to change."
            }
            if !unmatched.isEmpty {
                hint += ar ? "\nلم أجد فئة لـ \(unmatched.joined(separator: "، ")). اضغط على الفئة واختر «فئة جديدة»."
                           : "\nNo category fits \(unmatched.joined(separator: ", ")). Tap the category and choose New category."
            }
            withAnimation(.snappy) {
                for draft in drafts {
                    messages.append(GhafChatMessage(isUser: false, text: drafts.count == 1 ? intro + hint : (ar ? "راجع العملية ثم احفظها:" : "Review this transaction, then save:"), drafts: [draft]))
                }
            }
            if isVoice {
                // Read back what was heard and ask, then listen for "yes", "remove the coffee", "make it 5"…
                listenAfterSpeaking = true
                speak(spokenSummary(drafts), force: true)
            } else {
                speak(intro)
            }
            return
        }

        // "and last month?" carries over what the previous question was about.
        let previousQuestion = messages.dropLast().last(where: \.isUser)?.text
        let resolved = ChatFollowUp.resolve(text, previous: previousQuestion)

        // "Show it as a donut": redraw the last chart, no need to ask the model.
        if GhafChatChartBuilder.isRestyleOnly(text), let style = GhafChatChartBuilder.style(in: text),
           let last = messages.last(where: { $0.chart != nil })?.chart {
            let names: [GhafChatChart.Style: (String, String)] = [.bar: ("bars", "أعمدة"), .donut: ("a donut", "دائري"),
                                                                 .rose: ("a petal chart", "بتلات"), .line: ("a line", "خطي")]
            let name = names[style] ?? ("a chart", "رسم")
            withAnimation(.snappy) {
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تفضل، الرسم نفسه بشكل \(name.1)." : "Here it is as \(name.0).",
                                                chart: last.restyled(style), suggestions: suggestions(after: resolved)))
            }
            return
        }

        let history = messages.dropLast().filter { !$0.text.isEmpty }.map { (isUser: $0.isUser, text: $0.text) }
        let facts = GhafFinanceFacts.addressLine(sex: settings.userSex) + "\n"
            + GhafFinanceFacts.summary(accounts: accounts, transactions: transactions, subscriptions: subscriptions,
                                       memories: memoryEnabled ? memories : [], languageCode: settings.languageCode)
        let progressQuery = GhafLedgerAnswers.progressQuery(for: resolved, transactions: transactions,
                                                            currency: settings.currency, languageCode: settings.languageCode)
        if let progressQuery {
            progress.stage = .checkingTransactions(count: progressQuery.transactionCount, period: progressQuery.period)
        }
        isThinking = true
        replyTask = Task {
            if let progressQuery {
                await Task.yield()
                if let count = progressQuery.purchaseCount {
                    progress.stage = .addingPurchases(count)
                    await Task.yield()
                }
            }
            let direct = GhafLedgerAnswers.answer(to: resolved, accounts: accounts, transactions: transactions,
                                                  subscriptions: subscriptions, currency: settings.currency,
                                                  languageCode: settings.languageCode)
            var index: Int?
            do {
                GhafLedgerContext.accounts = accounts
                GhafLedgerContext.transactions = transactions
                GhafLedgerContext.subscriptions = subscriptions
                GhafLedgerContext.currency = settings.currency
                GhafLedgerContext.languageCode = settings.languageCode
                GhafLedgerContext.modelContext = modelContext
                GhafLedgerContext.requestedChart = nil
                for try await partial in assistant.reply(to: text, facts: facts, direct: direct, history: Array(history), languageCode: settings.languageCode) {
                    if let index {
                        messages[index].text = partial
                    } else {
                        messages.append(GhafChatMessage(isUser: false, text: partial, isStreaming: true))
                        index = messages.count - 1
                    }
                }
            } catch GhafCloudAI.Failure.dailyLimit {
                handleDailyLimit()
            } catch {
                let note = ar ? "تعذّر الرد الآن. حاول مرة أخرى لاحقاً." : "Sorry, I can't answer right now. Try again in a moment."
                messages.append(GhafChatMessage(isUser: false, text: note))
                if isVoice || speakReplies { playVoiceError() }
            }
            if let index {
                messages[index].isStreaming = false
                // The model's own chart choice wins; otherwise the question decides.
                let chartQuestion = GhafLedgerContext.requestedChart.map {
                    ["compare": "compare", "week": "week", "trend": "trend"][$0.kind, default: "categories"] + " " + $0.style
                } ?? resolved
                let chart = GhafChatChartBuilder.chart(for: chartQuestion, transactions: transactions,
                                                       currency: settings.currency, languageCode: settings.languageCode)
                if chart != nil {
                    progress.stage = .drawingChart
                    await Task.yield()
                }
                withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
                    messages[index].chart = chart
                    messages[index].suggestions = suggestions(after: resolved)
                    if chart != nil {
                        messages[index].text = settings.languageCode == "ar" ? "هذا الرسم من سجلاتك." : "Here is a chart from your records."
                    }
                    // Only answers the ledger computed say where their numbers came from.
                    if direct != nil {
                        messages[index].source = GhafChatChartBuilder.source(for: resolved, transactions: transactions,
                                                                             languageCode: settings.languageCode)
                    }
                }
                speak(messages[index].text, force: isVoice)
            }
            isThinking = false
            progress.stage = nil
        }
    }

    /// Follow-up chips answer from the on-device ledger and never call Gemini.
    private func answerFollowUpLocally(_ suggestion: String) {
        guard hasProAccess, !isThinking,
              let question = ChatFollowUp.ledgerQuestion(for: suggestion, languageCode: settings.languageCode) else { return }
        withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: true, text: suggestion)) }
        let answer = GhafLedgerAnswers.answer(to: question, accounts: accounts, transactions: transactions,
                                              subscriptions: subscriptions, currency: settings.currency,
                                              languageCode: settings.languageCode)
            ?? (ar ? "لا توجد بيانات كافية للإجابة." : "The ledger doesn't have enough information to answer that yet.")
        var reply = GhafChatMessage(isUser: false, text: answer,
                                    suggestions: ChatFollowUp.suggestions(after: question, languageCode: settings.languageCode))
        reply.source = GhafChatChartBuilder.source(for: question, transactions: transactions, languageCode: settings.languageCode)
        withAnimation(.snappy) { messages.append(reply) }
        persistChat()
    }

    private func handleMemoryIntent(_ intent: MemoryIntent, source: String) {
        switch intent {
        case .remember(let text), .name(let text):
            let kind = intent.isName ? "name" : "fact"
            do {
                let memory = try GhafMemoryStore.remember(text, kind: kind, source: source, in: modelContext)
                var answer = GhafChatMessage(isUser: false, text: ar ? "حسناً، سأحفظ هذه المعلومة." : "Got it. I’ll remember that.")
                answer.memoryID = memory.id
                messages.append(answer)
            } catch {
                Logger(subsystem: "com.ghaf.app", category: "ai").error("Saving memory failed: \(String(describing: error), privacy: .public)")
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تعذّر حفظ هذه المعلومة. حاول مرة أخرى." : "I couldn't save that memory. Try again."))
            }
        case .forget(let text):
            do {
                try GhafMemoryStore.forget(text, in: modelContext)
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تم، حذفت هذه المعلومة." : "Done. I’ve forgotten that."))
            } catch {
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تعذّر حذف هذه المعلومة. حاول مرة أخرى." : "I couldn't forget that. Try again."))
            }
        }
        if voiceMode && !liveCallActive, let reply = messages.last(where: { !$0.isUser })?.text {
            listenAfterSpeaking = true
            speak(reply, force: true)
        }
    }

    /// Follow-ups are deterministic and use short copy from the core mappings.
    private func suggestions(after question: String) -> [String] {
        ChatFollowUp.suggestions(after: question, languageCode: settings.languageCode)
    }

    /// "zumba class" → "Zumba Class". Arabic and already-capitalised words are left as spoken.
    static func tidyTitle(_ text: String) -> String {
        text.split(separator: " ").map { word in
            guard word.unicodeScalars.allSatisfy({ $0.isASCII }), word == word.lowercased() else { return String(word) }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private func preparedVoiceDrafts(in text: String) -> [GhafVoiceTransactionDraft] {
        GhafMessageIntent.drafts(in: text, baseCurrency: settings.currency).map { draft in
            var result = draft
            result.merchant = Self.tidyTitle(draft.merchant)
            if let match = MerchantCategorizer.suggestion(for: draft.merchant, context: modelContext) {
                result.category = match.category
                result.subcategory = match.subcategory
            } else {
                result.category = draft.direction == "credit" ? "Other Income" : "Other"
            }
            let eligible = accounts.filter { !$0.isArchived && $0.currency == draft.currency }
            result.accountID = eligible.first(where: { $0.type == .cash })?.id
                ?? eligible.first(where: { $0.isPrimary })?.id
                ?? eligible.first?.id
            return result
        }
    }

    /// The suggested category or subcategory isn't in the user's list yet.
    private func isNewCategory(_ draft: GhafVoiceTransactionDraft) -> Bool {
        guard draft.category != "Other" else { return false }
        if !settings.categories.contains(draft.category) { return true }
        if let sub = draft.subcategory { return !settings.subcategories(of: draft.category).contains(sub) }
        return false
    }

    private func saveDrafts(_ message: Binding<GhafChatMessage>) {
        do {
            let ids = try GhafDraftSaver.save(message.wrappedValue.drafts, preferredAccountID: nil, accounts: accounts,
                                    context: modelContext, note: ar ? "أضيفت عبر غاف AI" : "Added with Ghaf AI")
            message.wrappedValue.savedIDs = ids
            message.wrappedValue.draftState = .saved
            savedCount += 1
            let learned = message.wrappedValue.drafts.filter { !$0.merchant.isEmpty && $0.category != "Other" }
            let note = learned.isEmpty ? (ar ? "تم الحفظ." : "Saved.") : (ar
                ? "تم الحفظ. سأتذكر أن " + learned.map { "\($0.merchant) ← \(GhafLocalization.category($0.category, languageCode: "ar"))" + ($0.subcategory.map { " › \(GhafLocalization.category($0, languageCode: "ar"))" } ?? "") }.joined(separator: "، ") + "."
                : "Saved. I'll remember " + learned.map { "\($0.merchant) → \(GhafLocalization.category($0.category, languageCode: settings.languageCode))" + ($0.subcategory.map { " › \(GhafLocalization.category($0, languageCode: settings.languageCode))" } ?? "") }.joined(separator: ", ") + ".")
            withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: false, text: note)) }
            speak(ar ? "تم الحفظ. هل تريد شيئاً آخر؟" : "Saved. Anything else?", force: liveCallActive)
        } catch {
            withAnimation(.snappy) {
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تعذر الحفظ. حاول مرة أخرى." : "Couldn't save. Try again."))
            }
        }
    }

    /// Replies to voice input are always spoken; typed messages only when "read replies aloud" is on.
    // MARK: Voice mode

    private func beginVoiceCall() async {
        guard hasProAccess else { return }
        guard GhafCloudAI.isEnabled else {
            appendCallNote(ar ? "المحادثة الصوتية تحتاج الذكاء السحابي — أكمل بالصوت العادي." : "Voice chat needs Cloud AI — using standard voice.")
            startVoice()
            return
        }
        liveFacts = GhafFinanceFacts.addressLine(sex: settings.userSex) + "\n" + GhafCloudAI.minimized(GhafFinanceFacts.summary(accounts: accounts, transactions: transactions,
                                                                   subscriptions: subscriptions,
                                                                   memories: memoryEnabled ? memories : [], languageCode: settings.languageCode))
        if liveGroundingSources.isEmpty { liveGroundingSources = [liveFacts] }
        let firstName = (memoryEnabled ? memories.first(where: { $0.kind == "name" })?.text : nil)
            ?? settings.userName
        let date = Date.now.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(GhafLocale.locale(identifier: settings.languageCode)))
        let persona = ar
            ? "أنت غاف، \(voiceCharacter == "Mariam" ? "امرأة" : "رجل") إماراتي ودود. أجب دائماً بلغة آخر رسالة للمستخدم: العربية بلهجة خليجية إماراتية طبيعية، أو الإنجليزية. لا تخلط اللغتين إلا إذا خلط المستخدم بينهما، ولا تقدّم نفسك أو تمزج تحية إنجليزية بجملة عربية. عند السؤال عن الرصيد أو المصروفات أو الحسابات أو الاشتراكات، استدعِ get_finance_answer دائماً ولا تقل إنك لا تملك معلومات المستخدم. استخدم نتائج الأداة كما هي ولا تخمّن. استخدم remember أو forget فقط بطلب صريح. عند ذكر عملية، استدعِ log_transaction لعرض بطاقة تأكيد ولا تحفظها بنفسك."
            : "You are Ghaf, a warm \(voiceCharacter == "Mariam" ? "female" : "male") Emirati assistant. Always reply in the language of the user's latest turn: English, or natural Gulf Emirati Arabic. Do not mix languages unless the user does, and do not introduce yourself or combine an English greeting with Arabic. For any question about balances, spending, accounts, or subscriptions, always call get_finance_answer; never claim you lack access to the user's data. Use the tool result exactly and never guess. For a transaction, call log_transaction to show a confirmation card; never save it yourself. Use remember or forget only when explicitly asked. Speak English with a soft, educated American delivery and light Emirati warmth; avoid rolled or tapped r sounds."
        let nameLine = firstName.isEmpty ? "" : (ar ? "اسم المستخدم: \(firstName)." : "User's name: \(firstName).")
        let instruction = String("\(persona)\n\(nameLine)\nToday's date: \(date).\n\nFACTS:\n\(liveFacts)".prefix(5_900))
        configureLiveCallbacks()
        tabRouter.isListening = true
        do {
            try await liveCall.start(language: ar ? "ar" : "en", character: voiceCharacter, tier: GhafAITier.current, systemInstruction: instruction, tools: liveToolDeclarations)
            liveCallActive = true
            beginLiveUserTurn()
        } catch GhafCloudAI.Failure.dailyLimit {
            handleDailyLimit()
        } catch GhafCloudAI.Failure.voiceOff {
            tabRouter.isListening = false
            liveVoiceOff = true
            startVoice()
        } catch {
            tabRouter.isListening = false
            appendCallNote(ar ? "تعذّر الرد الآن. حاول مرة أخرى لاحقاً." : "Sorry, I can't answer right now. Try again in a moment.")
            playVoiceError()
        }
    }

    private var liveToolDeclarations: [LiveFunctionDeclaration] {
        func schema(_ properties: [String: LiveJSON], required: [String]) -> [String: LiveJSON] {
            ["type": .string("OBJECT"), "properties": .object(properties), "required": .array(required.map(LiveJSON.string))]
        }
        let string: LiveJSON = .object(["type": .string("STRING")])
        return [
            LiveFunctionDeclaration(name: "get_finance_answer", description: "Required for every question about balances, spending, income, accounts, budgets, subscriptions, or financial comparisons. Return the deterministic answer from Ghaf ledger records.", parameters: schema(["question": string], required: ["question"]), behavior: "NON_BLOCKING"),
            LiveFunctionDeclaration(name: "show_chart", description: "Ghaf draws inline charts from the user's ledger transactions. Use this tool when asked for a chart; never claim charts cannot be made.", parameters: schema(["question": string, "style": .object(["type": .string("STRING"), "enum": .array(["bar", "donut", "line", "rose"].map(LiveJSON.string))])], required: ["question"]), behavior: "NON_BLOCKING"),
            LiveFunctionDeclaration(name: "log_transaction", description: "Parse the user's transaction and show an editable confirmation card. Never save it.", parameters: schema(["text": string], required: ["text"]), behavior: "NON_BLOCKING"),
            LiveFunctionDeclaration(name: "remember", description: "Save a short user fact or preference they explicitly asked Ghaf to remember.", parameters: schema(["fact": string], required: ["fact"]), behavior: "NON_BLOCKING"),
            LiveFunctionDeclaration(name: "forget", description: "Forget a user fact they explicitly asked Ghaf to forget.", parameters: schema(["fact": string], required: ["fact"]), behavior: "NON_BLOCKING")
        ]
    }

    private func configureLiveCallbacks() {
        liveCall.onSpeechLimit = { handleDailyLimit() }
        liveCall.onTurnFinished = {
            guard liveCallActive else { return }
            tabRouter.isListening = false
            persistChat()
        }
        liveCall.onInputTranscript = { text, final in
            if !text.isEmpty {
                liveInputText += text
                if liveInputMessageID == nil {
                    let message = GhafChatMessage(isUser: true, text: text, isVoice: true)
                    messages.append(message); liveInputMessageID = message.id
                } else if let id = liveInputMessageID, let index = messages.firstIndex(where: { $0.id == id }) {
                    messages[index].text += text
                }
                liveGroundingSources.append(text)
            }
            if final {
                let completeText = liveInputText
                if let id = liveInputMessageID, let index = messages.firstIndex(where: { $0.id == id }) { messages[index].isVoice = true }
                liveInputMessageID = nil; liveInputText = ""
                let drafts = preparedVoiceDrafts(in: completeText)
                if !drafts.isEmpty && !liveTurnHasTransactionDrafts {
                    for draft in drafts {
                        messages.append(GhafChatMessage(isUser: false, text: ar ? "راجع العملية ثم احفظها:" : "Review this transaction, then save:", drafts: [draft]))
                    }
                    liveTurnHasTransactionDrafts = true
                }
            }
        }
        liveCall.onOutputTranscript = { text, final in
            if !text.isEmpty {
                liveOutputText += text
                if liveOutputMessageID == nil {
                    var message = GhafChatMessage(isUser: false, text: text, isVoice: true, isStreaming: true)
                    message.source = nil
                    messages.append(message); liveOutputMessageID = message.id
                } else if let id = liveOutputMessageID, let index = messages.firstIndex(where: { $0.id == id }) {
                    messages[index].text += text
                }
            }
            if final, let id = liveOutputMessageID, let index = messages.firstIndex(where: { $0.id == id }) {
                let unsupported = GroundedNumbers.unsupported(in: messages[index].text, sources: liveGroundingSources)
                if !unsupported.isEmpty {
                    messages[index].text += ar
                        ? "\n\n(بعض الأرقام هنا غير موجودة في سجلاتك في غاف، فتحقق منها.)"
                        : "\n\n(Some figures here aren't in your Ghaf records, so double-check them.)"
                }
                messages[index].isStreaming = false
                liveOutputMessageID = nil; liveOutputText = ""
            }
        }
        liveCall.onToolCall = { call in await runLiveTool(call) }
    }

    private func runLiveTool(_ call: LiveToolCall) async -> [String: LiveJSON] {
        func value(_ key: String) -> String { if case .string(let text) = call.args[key] { return text }; return "" }
        let response: String
        switch call.name {
        case "get_finance_answer":
            let question = value("question")
            let answer = GhafLedgerAnswers.answer(to: question, accounts: accounts, transactions: transactions,
                                                  subscriptions: subscriptions, currency: settings.currency,
                                                  languageCode: settings.languageCode) ?? (ar ? "لا توجد بيانات كافية للإجابة." : "The records don't contain an answer.")
            liveGroundingSources.append(answer)
            response = answer
        case "show_chart":
            let question = value("question") + " " + value("style")
            if let chart = GhafChatChartBuilder.chart(for: question, transactions: transactions,
                                                     currency: settings.currency, languageCode: settings.languageCode) {
                messages.append(GhafChatMessage(isUser: false, text: ar ? "هذا الرسم من سجلاتك." : "Here is a chart from your records.", chart: chart))
                response = chart.points.prefix(6).map { "\($0.label): \(GhafFormat.money(Decimal($0.value), currency: chart.currency, languageCode: settings.languageCode))" }.joined(separator: ", ")
                liveGroundingSources.append(response)
            } else { response = ar ? "لا توجد بيانات للرسم." : "There is no data to chart." }
        case "log_transaction":
            let text = value("text")
            let drafts = preparedVoiceDrafts(in: text)
            if !drafts.isEmpty {
                if !liveTurnHasTransactionDrafts {
                    for draft in drafts {
                        messages.append(GhafChatMessage(isUser: false, text: ar ? "راجع العملية ثم احفظها:" : "Review this transaction, then save:", drafts: [draft]))
                    }
                    liveTurnHasTransactionDrafts = true
                }
                response = ar ? "تظهر بطاقة تأكيد مستقلة لكل عملية. اطلب من المستخدم مراجعتها قبل الحفظ." : "Each transaction has its own confirmation card. Ask the user to review before saving."
            } else { response = ar ? "لم أجد عملية واضحة." : "I couldn't parse a clear transaction." }
        case "remember":
            guard memoryEnabled else { response = ar ? "الذاكرة متوقفة." : "Memory is disabled."; return ["result": .string(response)] }
            do {
                let memory = try GhafMemoryStore.remember(value("fact"), source: "confirmed", in: modelContext)
                var message = GhafChatMessage(isUser: false, text: ar ? "حسناً، سأحفظ هذه المعلومة." : "Got it. I’ll remember that.")
                message.memoryID = memory.id; messages.append(message)
                response = ar ? "انحفظت على هذا الجهاز." : "Saved on this iPhone."
            } catch { response = ar ? "تعذر الحفظ." : "Could not save memory." }
        case "forget":
            do { try GhafMemoryStore.forget(value("fact"), in: modelContext); response = ar ? "نسيت المعلومة." : "Forgotten." }
            catch { response = ar ? "تعذر النسيان." : "Could not forget that." }
        default: response = "Unknown tool."
        }
        return ["result": .string(response)]
    }

    private func appendCallNote(_ text: String) {
        withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: false, text: text)) }
    }

    private func exitVoiceMode() {
        liveCall.end()
        if reduceMotion { voiceMode = false } else { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { voiceMode = false } }
        liveCallActive = false
        GhafCloudAI.conversational = false
        GhafCloudVoice.shared.stop()
        cloudSpeaking = false
        cloudSpeechLevel = 0
        listenAfterSpeaking = false
        recorder.reset()
    }

    private var orbMood: GhafAIOrb.Mood {
        if voiceGoodbyePlaying { return .speaking }
        if progress.stage == .listening { return .listening }
        if voiceMode {
            switch liveCall.phase {
            case .connecting, .thinking: return .thinking
            case .listening, .reconnecting: return .listening
            case .speaking: return .speaking
            case .ended: break
            }
        }
        if recorder.isRecording { return .listening }
        if isThinking { return .thinking }
        if cloudSpeaking { return .speaking }
        return .idle
    }

    private var orbLevel: Float {
        if liveCallActive { return liveCall.phase == .speaking ? liveCall.outputLevel : liveCall.inputLevel }
        return recorder.isRecording ? recorder.level : cloudSpeechLevel
    }

    private func stopSpeaking() {
        if cloudSpeaking { GhafSounds.shared.play(.orbOff) }
        GhafCloudVoice.shared.stop()
        cloudSpeaking = false
        cloudSpeechLevel = 0
    }

    /// Replies use the selected Hamad/Mariam cloud voice or a bundled clip. Device speech is never used.
    private func speak(_ text: String, force: Bool = false) {
        guard speakReplies || force || voiceMode, !text.isEmpty else { return }
        guard hasProAccess else { return }
        guard GhafCloudAI.isEnabled else { playVoiceError(); return }
        GhafCloudVoice.shared.onLevel = { level in cloudSpeechLevel = level }
        let spoken = SpokenMoney.speakable(text, arabic: ar)
        Task {
            let result = await GhafCloudVoice.shared.speak(spoken, arabic: ar, character: voiceCharacter,
                onStart: { cloudSpeaking = true },
                onFinish: {
                    cloudSpeaking = false
                    guard listenAfterSpeaking || voiceMode else { return }
                    listenAfterSpeaking = false
                    startVoice()
                })
            switch result {
            case .played: break
            case .limitReached: handleDailyLimit()
            case .voiceOff:
                // Text-only until Hamad/Mariam's voices are on; no error clip for every answer.
                voiceUnavailable = true
                if listenAfterSpeaking || voiceMode { listenAfterSpeaking = false; startVoice() }
            case .unavailable:
                voiceUnavailable = true
                playVoiceError()
            }
        }
    }

}

/// The source line's icon sits tight against its text.
private struct GhafSourceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.imageScale(.small); configuration.title }
    }
}

/// Top categories as rows of name, bar and amount inside an answer, as on the canvas. Values from the ledger.
private struct GhafInlineBars: View {
    let chart: GhafChatChart
    let theme: GhafTheme
    let languageCode: String
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let points = Array(chart.points.prefix(4))
        let top = max(points.map(\.value).max() ?? 1, 1)
        let total = max(chart.points.reduce(0) { $0 + $1.value }, 1)
        let colors = GhafCategoryIcon.chartColors(for: points.map(\.label), dark: true)
        VStack(spacing: 9) {
            ForEach(points) { point in
                HStack(spacing: 10) {
                    Text(point.label)
                        .lineLimit(1)
                        .frame(width: 96, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.primaryText.opacity(0.1))
                            Capsule().fill(colors[point.label] ?? theme.accent)
                                .frame(width: max(8, geometry.size.width * (grown ? point.value / top : 0)))
                        }
                    }
                    .frame(height: 8)
                    Text(point.value, format: .number.precision(.fractionLength(0)).locale(GhafLocale.locale(identifier: languageCode)))
                        .foregroundStyle(theme.secondaryText)
                        .frame(minWidth: 48, alignment: .trailing)
                }
                .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(point.label), \(GhafFormat.money(Decimal(point.value), currency: chart.currency, languageCode: languageCode)), \(Int((point.value / total * 100).rounded()))%")
            }
        }
        .onAppear {
            if reduceMotion { grown = true } else { withAnimation(.smooth(duration: 0.9)) { grown = true } }
        }
    }
}

/// Five bars that follow the microphone level while recording.
private struct GhafLevelBars: View {
    let level: Float
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                let weight = [0.5, 0.8, 1.0, 0.8, 0.5][index]
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: 4 + CGFloat(level) * 16 * weight)
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}

/// Saved Ghaf AI chats, newest first, plus the chat options (engine, read-aloud, dictation).
private struct GhafChatHistorySheet: View {
    let chats: [GhafChat]
    let currentID: UUID?
    let theme: GhafTheme
    let languageCode: String
    let engineLabel: String
    @Binding var speakReplies: Bool
    let open: (GhafChat) -> Void
    let dictate: () -> Void
    let turnOnCloud: (() -> Void)?
    let delete: ([GhafChat]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteAll = false

    private var ar: Bool { languageCode == "ar" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(engineLabel, systemImage: "cpu")
                        .foregroundStyle(theme.secondaryText)
                    if let turnOnCloud {
                        Button(action: turnOnCloud) {
                            Label(ar ? "فعّل الذكاء السحابي" : "Turn on Cloud AI", systemImage: "cloud.fill")
                        }
                    }
                    Toggle(isOn: $speakReplies) {
                        Label(ar ? "قراءة الردود بصوت" : "Read replies aloud", systemImage: "speaker.wave.2.fill")
                    }
                    Button(action: dictate) {
                        Label(ar ? "إملاء رسالة" : "Dictate a message", systemImage: "mic.fill")
                    }
                }
                Section {
                    if chats.isEmpty {
                        Text(ar ? "لا توجد محادثات بعد. اسأل غاف أي شيء عن أموالك وستُحفظ هنا."
                                : "No chats yet. Ask Ghaf anything about your money and it's kept here.")
                            .foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 12)
                            .ghafEntrance(1)
                    }
                    ForEach(chats) { chat in
                        Button { open(chat) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(chat.title)
                                        .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(1)
                                    if chat.id == currentID {
                                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(theme.accent)
                                            .accessibilityLabel(ar ? "مفتوحة الآن" : "Open now")
                                    }
                                }
                                Text(chat.updatedAt.formatted(.relative(presentation: .named).locale(GhafLocale.locale(identifier: languageCode))))
                                    .font(GhafTypography.body(12, languageCode: languageCode))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, minHeight: GhafMetrics.rowHeight, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in delete(offsets.map { chats[$0] }) }
                } header: {
                    Text(ar ? "المحادثات" : "Chats")
                } footer: {
                    Text(ar ? "تبقى المحادثات على هذا الآيفون ولا تدخل في النسخ الاحتياطي. اسحب لحذف محادثة."
                            : "Chats stay on this iPhone and aren't part of backups. Swipe to delete one.")
                }
            }
            .scrollContentBackground(.hidden)
            .ghafBackground(theme: theme)
            .navigationTitle(ar ? "غاف AI" : "Ghaf AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ar ? "تم" : "Done") { dismiss() }
                }
                if !chats.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(ar ? "حذف الكل" : "Delete All", role: .destructive) { confirmDeleteAll = true }
                    }
                }
            }
            .confirmationDialog(ar ? "حذف كل المحادثات؟" : "Delete all chats?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button(ar ? "حذف \(chats.count) محادثة" : "Delete \(chats.count) Chats", role: .destructive) { delete(chats) }
            } message: {
                Text(ar ? "لا يمكن التراجع. عملياتك المحفوظة لا تتأثر." : "This can't be undone. Your saved transactions aren't affected.")
            }
        }
        .tint(theme.accent)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        .presentationDetents([.medium, .large])
    }
}
