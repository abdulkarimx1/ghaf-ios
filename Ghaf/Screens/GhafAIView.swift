import SwiftUI
import SwiftData
import AVFoundation
import Charts
import GhafCore
import OSLog

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
    static let night = Color(red: 0.02, green: 0.024, blue: 0.031)
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
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
    @State private var prompt = ""
    @State private var messages: [GhafChatMessage] = []
    @State private var isThinking = false
    @State private var replyTask: Task<Void, Never>?
    @AppStorage("ghaf.ai.speakReplies") private var speakReplies = false
    @AppStorage(GhafMemoryStore.enabledKey) private var memoryEnabled = GhafMemoryStore.defaultEnabled
    @AppStorage("ghaf.ai.liveConsentAccepted") private var liveConsentAccepted = false
    @State private var synthesizer = AVSpeechSynthesizer()
    @State private var speechDone = GhafSpeechDone()
    /// Set when Ghaf asked something out loud: it listens for the answer once it stops speaking.
    @State private var listenAfterSpeaking = false
    /// Hands-free conversation: listen, answer aloud, listen again, until the user ends it.
    @State private var voiceMode = false
    @State private var liveCallActive = false
    @State private var voiceStartedAt = Date()
    @State private var fallbackElapsed = 0
    @State private var voicePromptNotice: String?
    @State private var fallbackTimer: Task<Void, Never>?
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ghafGlass) private var glassStyle

    let settings: GhafSettings
    private var ar: Bool { settings.languageCode == "ar" }
    /// Ghaf AI is always the dark version of the user's city theme: near-black glass lit by the city's colours.
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: "Dark", systemIsDark: true)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if messages.isEmpty { welcome } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach($messages) { $message in
                                bubble($message).id(message.id)
                            }
                            if isThinking && messages.last?.isStreaming != true { thinkingDots.id("thinking") }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.last?.text) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                    }
                }
                }
                inputBar
            }
            .background {
                ZStack(alignment: .bottom) {
                    GhafAIView.night.ignoresSafeArea()
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
            .environment(\.colorScheme, .dark)
            .sensoryFeedback(.success, trigger: savedCount)
            .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isRecording)
            .onChange(of: recorder.finishedSpeakingCount) { _, _ in finishVoice() }
            .onChange(of: recorder.transcript) { _, text in
                if recorder.isRecording { prompt = text }
            }
            .onChange(of: prompt) { _, value in if !value.isEmpty { voicePromptNotice = nil } }
            .onAppear { engine = assistant.engine }
            .onDisappear {
                recorder.reset()
                stopSpeaking()
                liveCall.end()
                persistChat()
            }
            .onChange(of: isThinking) { _, thinking in if !thinking { persistChat() } }
            .onChange(of: messages.count) { _, _ in if !isThinking { persistChat() } }
            .onChange(of: liveCall.phase) { _, phase in
                if case .ended(let reason) = phase, liveCallActive {
                    liveCallActive = false
                    if reason == "time_limit" { voicePromptNotice = ar ? "اضغط على الموجة لتكمل الكلام" : "Tap the waveform to keep talking" }
                    if reason == "connection_lost" { appendCallNote(ar ? "توقف الصوت — انقطع الاتصال." : "Voice paused — connection lost.") }
                    exitVoiceMode()
                }
            }
        }
    }

    // MARK: Header

    private func glassCircle(_ symbol: String, tint: Color? = nil) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint ?? theme.primaryText)
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.06), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.14)))
    }

    /// Engine, read-aloud and dictation; also reachable from the history sheet.
    private var optionsMenu: some View {
        Menu {
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
        } label: {
            glassCircle("ellipsis")
        }
        .accessibilityLabel(ar ? "خيارات غاف" : "Ghaf AI options")
    }

    private var header: some View {
        HStack {
            if messages.isEmpty {
                // As on the canvas: history on the start screen.
                Button { showHistory = true } label: { glassCircle("line.3.horizontal") }
                    .buttonStyle(.ghafPress)
                    .accessibilityLabel(ar ? "المحادثات السابقة" : "Chat history")
            } else {
                // Back to the start screen; the chat is already saved in history.
                Button { startNewChat() } label: { glassCircle(ar ? "chevron.right" : "chevron.left") }
                    .buttonStyle(.ghafPress)
                    .accessibilityLabel(ar ? "محادثة جديدة، المحادثة محفوظة" : "New chat, this one is saved")
            }
            Spacer()
            if !messages.isEmpty || voiceMode {
                HStack(spacing: 8) {
                    GhafAIOrb(theme: theme, mood: orbMood, level: orbLevel)
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ghaf AI")
                            .font(GhafTypography.heading(17, languageCode: "en"))
                            .foregroundStyle(theme.primaryText)
                    }
                }
                Spacer()
            }
            optionsMenu
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .sheet(isPresented: $showHistory) {
            AnyView(GhafChatHistorySheet(
                chats: chats, currentID: chatID, theme: theme, languageCode: settings.languageCode,
                engineLabel: engineLabel, speakReplies: $speakReplies,
                open: { chat in openChat(chat) },
                dictate: { showHistory = false; startVoice() },
                turnOnCloud: engine == .cloud ? nil : { showHistory = false; offerCloud = true },
                delete: { deleteChats($0) }
            ))
        }
        .confirmationDialog(ar ? "الذكاء السحابي" : "Cloud AI", isPresented: $offerCloud, titleVisibility: .visible) {
            Button(ar ? "تفعيل" : "Turn On") {
                UserDefaults.standard.set(true, forKey: GhafCloudAI.enabledKey)
                engine = assistant.engine
            }
        } message: {
            Text(GhafCloudAI.disclosure(ar: ar) + (ar ? " يمكنك إيقافه من «ما تعلّمه غاف»." : " Turn it off anytime in What Ghaf learned."))
        }
        .confirmationDialog(ar ? "المحادثة الصوتية مع غاف" : "Voice chat with Ghaf", isPresented: $offerLiveConsent, titleVisibility: .visible) {
            Button(ar ? "تحدث" : "Talk") { liveConsentAccepted = true; Task { await beginVoiceCall() } }
            Button(ar ? "إلغاء" : "Cancel", role: .cancel) { exitVoiceMode() }
        } message: {
            Text(GhafCloudAI.liveDisclosure(ar: ar))
        }
    }

    // MARK: History

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
            GhafAIOrb(theme: theme, mood: orbMood, level: orbLevel)
                .frame(width: 150, height: 150)
                .padding(.top, 40)
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
            let chips = ar
                ? ["كم صرفت هالأسبوع؟", "وين أكثر مكان صرفت فيه؟", "ما الاشتراكات القادمة؟"]
                : ["How much did I spend this week?", "Where did most of my money go?", "Which subscriptions are due soon?"]
            VStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button { send(chip) } label: {
                        Text(chip)
                            .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 40)
                            .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
                            .background(.white.opacity(0.07), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.14)))
                    }
                    .buttonStyle(.ghafPress)
                }
            }
            .padding(.top, 26)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: Messages

    @ViewBuilder
    private func bubble(_ message: Binding<GhafChatMessage>) -> some View {
        let item = message.wrappedValue
        let inlineBars = item.chart.map { $0.kind == .categories && $0.style == .bar } ?? false
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
                .foregroundStyle(item.isUser ? GhafAIView.night : theme.primaryText)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background {
                    let shape = UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: item.isUser ? 22 : 6,
                                                       bottomTrailingRadius: item.isUser ? 6 : 22, topTrailingRadius: 22, style: .continuous)
                    if item.isUser { shape.fill(theme.primaryText) }
                    else { shape.fill(.ultraThinMaterial).overlay(shape.fill(.white.opacity(0.04))).overlay(shape.stroke(.white.opacity(0.14))) }
                }
                .contextMenu {
                    if item.isUser {
                        Button { prompt = item.text; inputFocused = true } label: {
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
            if !item.suggestions.isEmpty && item.id == messages.last?.id && !isThinking {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(item.suggestions, id: \.self) { suggestion in
                            Button { send(suggestion) } label: {
                                Text(suggestion)
                                    .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 40)
                                    .background(.white.opacity(0.06), in: Capsule())
                                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                            }
                            .buttonStyle(.ghafPress)
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
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: 340, alignment: .leading)
        .background {
            if glassStyle.enabled { shape.fill(Color.clear) }
            else { shape.fill(.ultraThinMaterial).overlay(shape.fill(.white.opacity(0.08))).overlay(shape.stroke(.white.opacity(0.14))) }
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
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Name and amount stay editable until saved, in case speech was misheard.
                        TextField(ar ? "الاسم" : "Name", text: $draft.merchant)
                            .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                            .disabled(state != .pending)
                        GhafCategoryPicker(category: $draft.category, subcategory: $draft.subcategory,
                                           languageCode: settings.languageCode, tint: theme.accent)
                            .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .semibold))
                            .disabled(state != .pending)
                        if state == .pending && isNewCategory(draft) {
                            Label(ar ? "جديدة · تُضاف عند الحفظ" : "New · added when you save", systemImage: "sparkles")
                                .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .bold))
                                .foregroundStyle(theme.accentContrast)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(theme.accent, in: Capsule())
                        }
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        GhafCurrencyIcon(currency: draft.currency, size: 14)
                        TextField("0", text: $draft.amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(GhafTypography.number(17, weight: .heavy))
                            .fixedSize()
                            .disabled(state != .pending)
                    }
                    .foregroundStyle(draft.direction == "credit" ? theme.credit : theme.primaryText)
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
            switch state {
            case .pending:
                HStack(spacing: 10) {
                    Button(ar ? "تجاهل" : "Discard") { message.wrappedValue.draftState = .discarded }
                        .ghafGlassButton(theme: theme, languageCode: settings.languageCode)
                    Button(ar ? "حفظ" : "Save") { saveDrafts(message) }
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
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.14)))
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
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(.white.opacity(0.08), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Input

    private var inputBar: some View {
        let hasText = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(voicePlaceholder, text: $prompt, axis: .vertical)
                    .font(GhafTypography.body(15, languageCode: settings.languageCode))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { send(prompt) }
                    .padding(.leading, 14).padding(.vertical, 12)

                // A multi-line field turns Return into a new line, so closing the keyboard needs its own button.
                if inputFocused {
                    Button { inputFocused = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 40, height: 46)
                    }
                    .accessibilityLabel(ar ? "إخفاء لوحة المفاتيح" : "Hide keyboard")
                    .transition(.scale.combined(with: .opacity))
                }

                // One light button, as on the canvas: voice chat when empty, send with text, stop while dictating.
                Button {
                    if recorder.isRecording { finishVoice() }
                    else if hasText { send(prompt) }
                    else { startVoice() }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : (hasText ? "arrow.up" : "mic.fill"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(recorder.isRecording ? .white : GhafAIView.night)
                        .frame(width: 48, height: 48)
                        .background(recorder.isRecording ? theme.over : theme.primaryText, in: Circle())
                        .symbolEffect(.pulse, isActive: recorder.isRecording)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.ghafPress)
                .disabled(isThinking && !recorder.isRecording)
                .accessibilityLabel(recorder.isRecording ? (ar ? "إيقاف وإرسال" : "Stop and send")
                                    : hasText ? (ar ? "إرسال" : "Send") : (ar ? "إملاء رسالة" : "Dictate a message"))
                Button { voiceMode ? exitVoiceMode() : enterVoiceMode() } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(voiceMode ? GhafAIView.night : theme.secondaryText)
                        .frame(width: 48, height: 48)
                        .background(voiceMode ? theme.accent : .clear, in: Circle())
                        .scaleEffect(voiceMode && !reduceMotion ? 1 + CGFloat(orbLevel) * 0.16 : 1)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: orbLevel)
                        .symbolEffect(.variableColor, isActive: voiceMode && !reduceMotion)
                }
                .buttonStyle(.ghafPress)
                .accessibilityLabel(voiceMode ? (ar ? "إيقاف المحادثة الصوتية" : "Stop talking") : (ar ? "تحدث مع غاف" : "Talk with Ghaf"))
            }
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke((recorder.isRecording || isThinking || inputFocused) ? theme.accent.opacity(0.8) : .white.opacity(0.28),
                        lineWidth: (recorder.isRecording || isThinking || inputFocused) ? 1.5 : 1)
                .allowsHitTesting(false))
            .shadow(color: theme.accent.opacity(recorder.isRecording || isThinking ? 0.35 : 0), radius: 14)
            .animation(.easeInOut(duration: 0.35), value: recorder.isRecording || isThinking || inputFocused)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var voicePlaceholder: String {
        if prompt.isEmpty, let voicePromptNotice { return voicePromptNotice }
        guard voiceMode, prompt.isEmpty else { return ar ? "اسأل أي شيء…" : "Ask anything…" }
        if liveCallActive {
            switch liveCall.phase {
            case .connecting, .listening: return ar ? "أسمعك…" : "Listening…"
            case .speaking: return ar ? "غاف يرد…" : "Ghaf is replying…"
            case .thinking: return ar ? "أشيّك على سجلاتك…" : "Checking your records…"
            case .reconnecting: return ar ? "أعيد الاتصال…" : "Reconnecting…"
            case .ended: break
            }
        }
        if isThinking { return ar ? "أشيّك على سجلاتك…" : "Checking your records…" }
        if speechDone.speaking { return ar ? "غاف يرد…" : "Ghaf is replying…" }
        return ar ? "أسمعك…" : "Listening…"
    }

    // MARK: Actions

    private func startVoice() {
        stopSpeaking()
        prompt = ""
        inputFocused = false
        // Bias recognition towards this user's own merchants and categories.
        let hints = rules.prefix(60).map(\.normalizedMerchant)
            + settings.categories + settings.categories.flatMap(settings.subcategories(of:))
        Task { await recorder.start(languageCode: settings.languageCode, hints: hints) }
    }

    /// Called by the stop button, or automatically after a pause. Clear speech is sent;
    /// unclear speech is dropped.
    private func finishVoice() {
        recorder.stop()
        let text = (recorder.transcript.isEmpty ? prompt : recorder.transcript).trimmingCharacters(in: .whitespacesAndNewlines)
        recorder.reset()
        let letters = text.filter(\.isLetter).count
        let understood = GhafMessageIntent.isQuestion(text)
            || !GhafMessageIntent.drafts(in: text, baseCurrency: settings.currency).isEmpty
            || MemoryIntent.parse(text) != nil
            || ChatCorrection.parse(text, recent: recentDraftRefs().map(\.name)) != nil
            || ChatEdit.parse(text, recent: recentDraftRefs().map(\.name)) != nil
        if (letters >= 2 || ChatEdit.parse(text, recent: []) == .confirm) && understood {
            send(text, isVoice: true)
        } else {
            // Nothing usable: clear it and show a short note that removes itself.
            prompt = ""
            let note = GhafChatMessage(isUser: false, text: text.isEmpty
                ? (ar ? "لم أسمع شيئاً. حاول مرة أخرى." : "I didn't hear anything. Try again.")
                : (ar ? "لم أفهم ذلك. حاول مرة أخرى." : "I didn't catch that. Try again."))
            withAnimation(.snappy) { messages.append(note) }
            Task {
                if voiceMode {
                    try? await Task.sleep(for: .seconds(1.2))
                    if voiceMode { startVoice() }
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
            reply = ar ? "تمام، ما حفظت شيئاً." : "Okay, nothing saved."
        case .remove(let index):
            let draftIndex = messages[m].drafts.count - 1 - index
            guard pending else {
                reply = ar ? "هذه محفوظة. احذفها من العمليات." : "That one's already saved. Delete it from Transactions."
                break
            }
            let removed = messages[m].drafts.remove(at: draftIndex).merchant
            if messages[m].drafts.isEmpty { messages[m].draftState = .discarded }
            reply = ar ? "حذفت \(removed)." : "Removed \(removed)."
            if !messages[m].drafts.isEmpty { reply += ar ? " أحفظ الباقي؟" : " Save the rest?"; listenAfterSpeaking = isVoice }
        case .rename(let index, let name):
            let draftIndex = messages[m].drafts.count - 1 - index
            let title = Self.tidyTitle(name)
            messages[m].drafts[draftIndex].merchant = title
            if !pending, draftIndex < messages[m].savedIDs.count {
                let id = messages[m].savedIDs[draftIndex]
                if let transaction = try? modelContext.fetch(FetchDescriptor<GhafTransaction>(predicate: #Predicate { $0.id == id })).first {
                    transaction.merchant = title
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
        guard !text.isEmpty, !isThinking else { return }
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
        let drafts = GhafMessageIntent.drafts(in: text, baseCurrency: settings.currency).map { draft -> GhafVoiceTransactionDraft in
            var result = draft
            result.merchant = Self.tidyTitle(draft.merchant)
            if let match = MerchantCategorizer.suggestion(for: draft.merchant, context: modelContext) {
                result.category = match.category
                result.subcategory = match.subcategory
            } else {
                result.category = draft.direction == "credit" ? "Other Income" : "Other"
            }
            return result
        }
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
            withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: false, text: intro + hint, drafts: drafts)) }
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
        let facts = GhafFinanceFacts.summary(accounts: accounts, transactions: transactions, subscriptions: subscriptions,
                                              memories: memoryEnabled ? memories : [])
        isThinking = true
        let direct = GhafLedgerAnswers.answer(to: resolved, accounts: accounts, transactions: transactions,
                                              subscriptions: subscriptions, currency: settings.currency,
                                              languageCode: settings.languageCode)
        replyTask = Task {
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
            } catch {
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تعذر الرد الآن. حاول مرة أخرى." : "I couldn't answer just now. Try again."))
            }
            if let index {
                messages[index].isStreaming = false
                // The model's own chart choice wins; otherwise the question decides.
                let chartQuestion = GhafLedgerContext.requestedChart.map {
                    ["compare": "compare", "week": "week", "trend": "trend"][$0.kind, default: "categories"] + " " + $0.style
                } ?? resolved
                withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
                    messages[index].chart = GhafChatChartBuilder.chart(for: chartQuestion, transactions: transactions,
                                                                      currency: settings.currency, languageCode: settings.languageCode)
                    messages[index].suggestions = suggestions(after: resolved)
                    // Only answers the ledger computed say where their numbers came from.
                    if direct != nil {
                        messages[index].source = GhafChatChartBuilder.source(for: resolved, transactions: transactions,
                                                                             languageCode: settings.languageCode)
                    }
                }
                speak(messages[index].text, force: isVoice)
            }
            isThinking = false
        }
    }

    private func handleMemoryIntent(_ intent: MemoryIntent, source: String) {
        switch intent {
        case .remember(let text), .name(let text):
            let kind = intent.isName ? "name" : "fact"
            do {
                let memory = try GhafMemoryStore.remember(text, kind: kind, source: source, in: modelContext)
                var answer = GhafChatMessage(isUser: false, text: ar ? "تمام، بحفظ هالمعلومة." : "Got it. I’ll remember that.")
                answer.memoryID = memory.id
                messages.append(answer)
            } catch {
                Logger(subsystem: "com.ghaf.app", category: "ai").error("Saving memory failed: \(String(describing: error), privacy: .public)")
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تعذر حفظها. حاول مرة ثانية." : "I couldn't save that memory. Try again."))
            }
        case .forget(let text):
            do {
                try GhafMemoryStore.forget(text, in: modelContext)
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تم، نسيت هالمعلومة." : "Done. I’ve forgotten that."))
            } catch {
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تعذر نسيانها. حاول مرة ثانية." : "I couldn't forget that. Try again."))
            }
        }
        if voiceMode && !liveCallActive, let reply = messages.last(where: { !$0.isUser })?.text {
            listenAfterSpeaking = true
            speak(reply, force: true)
        }
    }

    /// Three useful next questions, chosen from what was just asked, never repeating it.
    private func suggestions(after question: String) -> [String] {
        let q = question.lowercased()
        func lastMonth(_ code: String) -> String {
            (GhafCalendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now)
                .formatted(.dateTime.month(.wide).locale(Locale(identifier: code)))
        }
        let pool: [(match: [String], en: String, ar: String)] = [
            (["compare", "قارن"], "Compare to \(lastMonth("en"))", "قارن بشهر \(lastMonth("ar"))"),
            (["donut", "دائري"], "Show as a donut", "اعرضها كرسم دائري"),
            (["petal", "بتلات"], "Show as a petal chart", "اعرضها كرسم بتلات"),
            (["trend", "اتجاه"], "This month's trend", "اتجاه هذا الشهر"),
            (["biggest", "أكبر"], "My biggest purchase", "أكبر عملية"),
            (["forecast", "توقع"], "Forecast to month end", "توقع نهاية الشهر"),
            (["tip", "نصيحة"], "A saving tip", "نصيحة للتوفير"),
            (["subscri", "اشتراك"], "Subscriptions due soon", "الاشتراكات القادمة")
        ]
        return pool.filter { !$0.match.contains(where: q.contains) }.shuffled().prefix(3).map { ar ? $0.ar : $0.en }
    }

    /// "zumba class" → "Zumba Class". Arabic and already-capitalised words are left as spoken.
    static func tidyTitle(_ text: String) -> String {
        text.split(separator: " ").map { word in
            guard word.unicodeScalars.allSatisfy({ $0.isASCII }), word == word.lowercased() else { return String(word) }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
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
                ? "تم الحفظ. سأتذكر أن " + learned.map { "\($0.merchant) ← \(GhafLocalization.category($0.category, languageCode: "ar"))" }.joined(separator: "، ") + "."
                : "Saved. I'll remember " + learned.map { "\($0.merchant) → \($0.category)" }.joined(separator: ", ") + ".")
            withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: false, text: note)) }
            speak(ar ? "تم الحفظ. شي ثاني؟" : "Saved. Anything else?")
        } catch {
            withAnimation(.snappy) {
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تعذر الحفظ. حاول مرة أخرى." : "Couldn't save. Try again."))
            }
        }
    }

    /// Replies to voice input are always spoken; typed messages only when "read replies aloud" is on.
    // MARK: Voice mode

    private func enterVoiceMode() {
        inputFocused = false
        GhafCloudAI.conversational = true
        if reduceMotion { voiceMode = true } else { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { voiceMode = true } }
        voicePromptNotice = nil
        voiceStartedAt = .now
        fallbackElapsed = 0
        fallbackTimer?.cancel()
        fallbackTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard voiceMode else { return }
                fallbackElapsed = Int(Date().timeIntervalSince(voiceStartedAt))
                if !liveCallActive && fallbackElapsed >= 1_800 {
                    voicePromptNotice = ar ? "اضغط على الموجة لتكمل الكلام" : "Tap the waveform to keep talking"
                    exitVoiceMode()
                    return
                }
            }
        }
        liveInputText = ""; liveOutputText = ""; liveGroundingSources = []
        if GhafCloudAI.isEnabled && !liveConsentAccepted { offerLiveConsent = true }
        else { Task { await beginVoiceCall() } }
    }

    private func beginVoiceCall() async {
        guard GhafCloudAI.isEnabled else {
            appendCallNote(ar ? "المحادثة الصوتية تحتاج الذكاء السحابي — أكمل بالصوت العادي." : "Voice chat needs Cloud AI — using standard voice.")
            startVoice()
            return
        }
        liveFacts = GhafCloudAI.minimized(GhafFinanceFacts.summary(accounts: accounts, transactions: transactions,
                                                                   subscriptions: subscriptions,
                                                                   memories: memoryEnabled ? memories : []))
        if liveGroundingSources.isEmpty { liveGroundingSources = [liveFacts] }
        let firstName = (memoryEnabled ? memories.first(where: { $0.kind == "name" })?.text : nil)
            ?? settings.userName
        let date = Date.now.formatted(date: .complete, time: .omitted)
        let persona = ar
            ? "أنت غاف، شاب إماراتي من أبوظبي، ودود وجمله قصيرة وطبيعية. إذا تحدث المستخدم بالعربية، أجب باللهجة الخليجية الإماراتية، لا بالفصحى أو المصرية أو الشامية. إذا تحدث بالإنجليزية، أجب بإنجليزية بسيطة وودودة. كل رقم مالي يجب أن يأتي من نتيجة أداة أو من كتلة الحقائق؛ إذا لم تكن متأكداً، استدعِ get_finance_answer. استخدم remember أو forget فقط عندما يطلب المستخدم ذلك صراحةً، ولا تستنتج معلومات للحفظ. لا تسجل عملية دون تأكيد المستخدم على البطاقة."
            : "You are Ghaf, a friendly young Emirati man from Abu Dhabi. Use short, natural spoken sentences. Reply in Emirati Gulf Arabic when the user speaks Arabic, never MSA, Egyptian or Levantine. Reply in plain friendly English when they speak English. Every money figure must come from a tool result or the facts block; when unsure, use get_finance_answer. Use remember or forget only when the user explicitly asks; never infer facts to save. Never save a transaction without the user's confirmation on its card."
        let nameLine = firstName.isEmpty ? "" : (ar ? "اسم المستخدم: \(firstName)." : "User's name: \(firstName).")
        let instruction = String("\(persona)\n\(nameLine)\nToday's date: \(date).\n\nFACTS:\n\(liveFacts)".prefix(5_900))
        configureLiveCallbacks()
        do {
            try await liveCall.start(language: ar ? "ar" : "en", systemInstruction: instruction, tools: liveToolDeclarations)
            liveCallActive = true
        } catch GhafCloudAI.Failure.dailyLimit {
            appendCallNote(ar ? "وصلت لحد المحادثة الصوتية اليوم — أكمل بالصوت العادي." : "You've reached today's voice chat limit — using standard voice.")
            startVoice()
        } catch {
            appendCallNote(ar ? "تعذر بدء المحادثة الصوتية — أكمل بالصوت العادي." : "Voice chat couldn't connect — using standard voice.")
            startVoice()
        }
    }

    private var liveToolDeclarations: [LiveFunctionDeclaration] {
        func schema(_ properties: [String: LiveJSON], required: [String]) -> [String: LiveJSON] {
            ["type": .string("OBJECT"), "properties": .object(properties), "required": .array(required.map(LiveJSON.string))]
        }
        let string: LiveJSON = .object(["type": .string("STRING")])
        return [
            LiveFunctionDeclaration(name: "get_finance_answer", description: "Answer a financial question from deterministic ledger records.", parameters: schema(["question": string], required: ["question"])),
            LiveFunctionDeclaration(name: "show_chart", description: "Insert an inline chart built from the user's transactions.", parameters: schema(["question": string, "style": .object(["type": .string("STRING"), "enum": .array(["bar", "donut", "line", "rose"].map(LiveJSON.string))])], required: ["question"])),
            LiveFunctionDeclaration(name: "log_transaction", description: "Parse a transaction and show an editable confirmation card. Never save it.", parameters: schema(["text": string], required: ["text"])),
            LiveFunctionDeclaration(name: "remember", description: "Save a short user fact or preference they explicitly asked Ghaf to remember.", parameters: schema(["fact": string], required: ["fact"])),
            LiveFunctionDeclaration(name: "forget", description: "Forget a user fact they explicitly asked Ghaf to forget.", parameters: schema(["fact": string], required: ["fact"]))
        ]
    }

    private func configureLiveCallbacks() {
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
                if let id = liveInputMessageID, let index = messages.firstIndex(where: { $0.id == id }) { messages[index].isVoice = true }
                liveInputMessageID = nil; liveInputText = ""
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
            let drafts = GhafMessageIntent.drafts(in: text, baseCurrency: settings.currency).map { draft -> GhafVoiceTransactionDraft in
                var result = draft
                result.merchant = Self.tidyTitle(draft.merchant)
                if let match = MerchantCategorizer.suggestion(for: draft.merchant, context: modelContext) {
                    result.category = match.category; result.subcategory = match.subcategory
                } else { result.category = draft.direction == "credit" ? "Other Income" : "Other" }
                return result
            }
            if !drafts.isEmpty {
                messages.append(GhafChatMessage(isUser: false, text: ar ? "وجدت عملية. راجعها ثم احفظ:" : "I found a transaction. Review it, then save:", drafts: drafts))
                response = ar ? "بانتظار تأكيد المستخدم على بطاقة العملية." : "Awaiting the user's confirmation on the transaction card."
            } else { response = ar ? "لم أجد عملية واضحة." : "I couldn't parse a clear transaction." }
        case "remember":
            guard memoryEnabled else { response = ar ? "الذاكرة متوقفة." : "Memory is disabled."; return ["result": .string(response)] }
            do {
                let memory = try GhafMemoryStore.remember(value("fact"), source: "confirmed", in: modelContext)
                var message = GhafChatMessage(isUser: false, text: ar ? "تمام، بحفظ هالمعلومة." : "Got it. I’ll remember that.")
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
        fallbackTimer?.cancel(); fallbackTimer = nil
        if reduceMotion { voiceMode = false } else { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { voiceMode = false } }
        liveCallActive = false
        GhafCloudAI.conversational = false
        GhafCloudVoice.shared.stop()
        speechDone.speaking = false
        listenAfterSpeaking = false
        recorder.reset()
        synthesizer.stopSpeaking(at: .immediate)
    }

    private var orbMood: GhafAIOrb.Mood {
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
        if speechDone.speaking { return .speaking }
        return .idle
    }

    private var orbLevel: Float {
        if liveCallActive { return liveCall.phase == .speaking ? liveCall.outputLevel : liveCall.inputLevel }
        return recorder.isRecording ? recorder.level : speechDone.level
    }

    private func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        GhafCloudVoice.shared.stop()
        speechDone.speaking = false
    }

    /// Ghaf's server voice whenever Cloud AI is on (warmer, Gulf-friendly Arabic); the iPhone's own voice otherwise or offline.
    private func speak(_ text: String, force: Bool = false) {
        guard speakReplies || force || voiceMode, !text.isEmpty else { return }
        if GhafCloudAI.isEnabled {
            GhafCloudVoice.shared.onLevel = { level in speechDone.level = level }
            let spoken = SpokenMoney.speakable(text, arabic: ar)
            Task {
                let played = await GhafCloudVoice.shared.speak(spoken, arabic: ar,
                    onStart: { speechDone.speaking = true },
                    onFinish: {
                        speechDone.speaking = false
                        guard listenAfterSpeaking || voiceMode else { return }
                        listenAfterSpeaking = false
                        startVoice()
                    })
                if !played { speakOnDevice(text) }
            }
            return
        }
        speakOnDevice(text)
    }

    /// The iPhone's own voice: used outside voice mode, without Cloud AI, or when the server is unreachable.
    private func speakOnDevice(_ text: String) {
        // The microphone leaves the session in .record, where speech is silent.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let language = ar ? "ar" : "en"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        let utterance = AVSpeechUtterance(string: SpokenMoney.speakable(text, arabic: ar))
        // A touch slower with a small lead-in reads as conversation rather than a readout.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.1
        // Best installed voice (premium/enhanced when the user downloaded one), Gulf Arabic first.
        utterance.voice = voices.max { ($0.quality.rawValue, $0.language == "ar-AE" ? 1 : 0) < ($1.quality.rawValue, $1.language == "ar-AE" ? 1 : 0) }
            ?? AVSpeechSynthesisVoice(language: ar ? "ar-SA" : "en-US")
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.delegate = speechDone
        speechDone.onFinish = {
            guard listenAfterSpeaking || voiceMode else { return }
            listenAfterSpeaking = false
            startVoice()
        }
        synthesizer.speak(utterance)
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
                            Capsule().fill(.white.opacity(0.1))
                            Capsule().fill(colors[point.label] ?? theme.accent)
                                .frame(width: max(8, geometry.size.width * (grown ? point.value / top : 0)))
                        }
                    }
                    .frame(height: 8)
                    Text(point.value, format: .number.precision(.fractionLength(0)).locale(Locale(identifier: languageCode)))
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

/// Tells the chat when Ghaf has finished speaking, so it can listen for the answer.
@Observable
final class GhafSpeechDone: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (@MainActor () -> Void)?
    /// Whether Ghaf is talking right now, for the voice mode's status line.
    var speaking = false
    /// Loudness of Ghaf's own voice (cloud voice only), so the orb moves with it.
    var level: Float = 0
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = true }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speaking = false
            self.onFinish?()
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
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
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 12)
                    }
                    ForEach(chats) { chat in
                        Button { open(chat) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(chat.title)
                                        .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if chat.id == currentID {
                                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(theme.accent)
                                            .accessibilityLabel(ar ? "مفتوحة الآن" : "Open now")
                                    }
                                }
                                Text(chat.updatedAt.formatted(.relative(presentation: .named).locale(Locale(identifier: languageCode))))
                                    .font(GhafTypography.body(12, languageCode: languageCode))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
