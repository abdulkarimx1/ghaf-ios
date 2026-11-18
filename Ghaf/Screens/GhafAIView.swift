import SwiftUI
import SwiftData
import AVFoundation
import Charts
import GhafCore

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
}

struct GhafAIView: View {
    static let night = Color(red: 0.02, green: 0.024, blue: 0.031)
    static let blue = Color(red: 0.18, green: 0.42, blue: 1)
    static let light = Color(red: 0.61, green: 0.77, blue: 1)
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @Query private var subscriptions: [GhafSubscription]
    @Query(sort: \MerchantCategoryRule.hits, order: .reverse) private var rules: [MerchantCategoryRule]

    @StateObject private var assistant = GhafAssistant()
    @StateObject private var recorder = GhafSpeechRecorder()
    @State private var prompt = ""
    @State private var messages: [GhafChatMessage] = []
    @State private var isThinking = false
    @State private var replyTask: Task<Void, Never>?
    @AppStorage("ghaf.ai.speakReplies") private var speakReplies = false
    @State private var synthesizer = AVSpeechSynthesizer()
    @State private var speechDone = GhafSpeechDone()
    /// Set when Ghaf asked something out loud: it listens for the answer once it stops speaking.
    @State private var listenAfterSpeaking = false
    /// Hands-free conversation: listen, answer aloud, listen again, until the user ends it.
    @State private var voiceMode = false
    @FocusState private var inputFocused: Bool
    @State private var savedCount = 0
    /// Model availability is costly to query; read it when the tab appears, not on every render.
    @State private var engine: GhafAssistant.Engine = .basic
    @State private var offerCloud = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let settings: GhafSettings
    private var ar: Bool { settings.languageCode == "ar" }
    /// Ghaf AI has one look in every theme: near-black glass with blue light (Dubai's dark palette).
    private var theme: GhafTheme {
        GhafTheme.resolve(name: "Dubai", appearanceMode: "Dark", systemIsDark: true)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            if messages.isEmpty { welcome }
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
                inputBar
            }
            .background {
                ZStack(alignment: .bottom) {
                    GhafAIView.night.ignoresSafeArea()
                    // Blue light rising from the bottom edge, brighter while Ghaf listens or thinks.
                    Ellipse()
                        .fill(RadialGradient(colors: [GhafAIView.light.opacity(0.9), GhafAIView.blue.opacity(0.6), .clear],
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
            .overlay {
                if voiceMode {
                    AnyView(voiceModeView).transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
            }
            .sensoryFeedback(.success, trigger: savedCount)
            .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isRecording)
            .onChange(of: recorder.finishedSpeakingCount) { _, _ in finishVoice() }
            .onChange(of: recorder.transcript) { _, text in
                if recorder.isRecording { prompt = text }
            }
            .onAppear { engine = assistant.engine }
            .onDisappear {
                recorder.reset()
                synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                HStack {
                    Spacer()
                    Button {
                        speakReplies.toggle()
                        if !speakReplies { synthesizer.stopSpeaking(at: .immediate) }
                    } label: {
                        Image(systemName: speakReplies ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(speakReplies ? theme.accent : theme.secondaryText)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.07), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.14)))
                    }
                    .buttonStyle(.ghafPress)
                    .accessibilityLabel(ar ? "قراءة الردود بصوت" : "Read replies aloud")
                }
                HStack(spacing: 10) {
                    // The welcome shows the big orb; the header orb appears once a chat starts.
                    if !messages.isEmpty {
                        GhafAIOrb(theme: theme, active: (isThinking || recorder.isRecording) && !reduceMotion)
                            .frame(width: 36, height: 36)
                    }
                    Text("Ghaf AI")
                        .font(GhafTypography.heading(22, languageCode: "en"))
                        .foregroundStyle(theme.primaryText)
                }
            }
            Label(engineLabel, systemImage: engine == .onDevice ? "lock.shield.fill" : engine == .cloud ? "cloud.fill" : "bolt.horizontal.fill")
                .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
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
        VStack(spacing: 16) {
            GhafAIOrb(theme: theme, active: false)
                .frame(width: 150, height: 150)
                .padding(.top, 28).padding(.bottom, 12)
            let name = settings.userName.split(separator: " ").first.map(String.init) ?? ""
            if !name.isEmpty {
                Text(ar ? "أهلاً \(name)" : "Hello \(name)")
                    .font(GhafTypography.body(16, languageCode: settings.languageCode, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            Text(ar ? "كيف أساعدك في أموالك؟" : "How can I help with your money?")
                .font(GhafTypography.display(30, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
            Text(ar ? "المصروف والميزانية والاشتراكات، أو قل ما اشتريت وأسجّله لك."
                    : "Spending, budgets, subscriptions. Or just say what you bought and I'll log it.")
                .font(GhafTypography.body(15, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            let chips = ar
                ? ["كم صرفت هالأسبوع؟", "وين أكثر مكان صرفت فيه؟", "كم رصيدي؟", "ما الاشتراكات القادمة؟", "٣٥ درهم غداء", "قارن هذا الشهر بالماضي", "ارسم مصروفي حسب الفئة"]
                : ["How much did I spend this week?", "Where did most of my money go?", "What's my balance?", "Which subscriptions are due?", "35 AED lunch", "Compare this month to last month", "Chart my spending by category"]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(chips, id: \.self) { chip in
                    Button { send(chip) } label: {
                        Text(chip)
                            .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .padding(.horizontal, 12)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.14)))
                    }
                    .buttonStyle(.ghafPress)
                }
            }
            if engine != .cloud {
                Button { offerCloud = true } label: {
                    Label(ar ? "فعّل الذكاء السحابي لإجابات أذكى" : "Turn on Cloud AI for smarter answers", systemImage: "cloud.fill")
                        .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(theme.accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.ghafPress)
                .confirmationDialog(ar ? "الذكاء السحابي" : "Cloud AI", isPresented: $offerCloud, titleVisibility: .visible) {
                    Button(ar ? "تفعيل" : "Turn On") {
                        UserDefaults.standard.set(true, forKey: GhafCloudAI.enabledKey)
                        engine = assistant.engine
                    }
                } message: {
                    Text(GhafCloudAI.disclosure(ar: ar) + (ar ? " يمكنك إيقافه من «ما تعلّمه غاف»." : " Turn it off anytime in What Ghaf learned."))
                }
            }
            Label(ar ? "يتعلم غاف من تصحيحاتك: غيّر الفئة مرة وسيتذكرها." : "Ghaf learns from you: change a category once and it remembers.",
                  systemImage: "brain.head.profile")
                .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: Messages

    @ViewBuilder
    private func bubble(_ message: Binding<GhafChatMessage>) -> some View {
        let item = message.wrappedValue
        VStack(alignment: item.isUser ? .trailing : .leading, spacing: 8) {
            if !item.text.isEmpty {
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
            if let chart = item.chart {
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
                                    .foregroundStyle(theme.accent)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(theme.accent.opacity(0.1), in: Capsule())
                                    .overlay(Capsule().stroke(theme.accent.opacity(0.25), lineWidth: 1))
                            }
                            .buttonStyle(.ghafPress)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !item.drafts.isEmpty { draftCard(message) }
        }
        .frame(maxWidth: .infinity, alignment: item.isUser ? .trailing : .leading)
        .padding(item.isUser ? .leading : .trailing, 40)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
            if recorder.isRecording {
                HStack(spacing: 8) {
                    GhafLevelBars(level: recorder.level, tint: theme.accent)
                    Text(ar ? "أستمع… توقف عن الكلام للإرسال · العربية والإنجليزية"
                            : "Listening… pause to send · Arabic & English")
                        .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
                .transition(.opacity)
            } else if let error = recorder.errorMessage {
                Text(error)
                    .font(GhafTypography.body(12, languageCode: settings.languageCode))
                    .foregroundStyle(theme.over)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(ar ? "اسأل غاف أو اكتب مصروفاً…" : "Ask Ghaf or type a purchase…", text: $prompt, axis: .vertical)
                    .font(GhafTypography.body(15, languageCode: settings.languageCode))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { send(prompt) }
                    .padding(.leading, 18).padding(.vertical, 12)

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

                if !hasText && !recorder.isRecording {
                    Button { enterVoiceMode() } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 44, height: 44)
                            .background(theme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.ghafPress)
                    .disabled(isThinking)
                    .accessibilityLabel(ar ? "وضع المحادثة الصوتية" : "Voice mode")
                }
                Button {
                    if recorder.isRecording { finishVoice() }
                    else if hasText { send(prompt) }
                    else { startVoice() }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : (hasText ? "arrow.up" : "mic.fill"))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(recorder.isRecording ? .white : GhafAIView.night)
                        .frame(width: 46, height: 46)
                        .background(recorder.isRecording ? theme.over : theme.primaryText, in: Circle())
                        .symbolEffect(.pulse, isActive: recorder.isRecording)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.ghafPress)
                .disabled(isThinking && !recorder.isRecording)
                .accessibilityLabel(recorder.isRecording ? (ar ? "إيقاف وإرسال" : "Stop and send")
                                    : hasText ? (ar ? "إرسال" : "Send") : (ar ? "رسالة صوتية" : "Voice message"))
            }
            .padding(5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                // Gradient rim that glows while Ghaf listens, thinks or the field is focused.
                let lit = recorder.isRecording || isThinking || inputFocused
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .strokeBorder(AngularGradient(colors: [theme.accent, theme.glow, theme.accent.opacity(0.4), theme.accent],
                                                  center: .center), lineWidth: lit ? 1.5 : 0.8)
                    .opacity(lit ? 1 : 0.45)
                    .allowsHitTesting(false)
            }
            .shadow(color: theme.accent.opacity(recorder.isRecording || isThinking ? 0.35 : 0.14), radius: 14)
            .animation(.easeInOut(duration: 0.35), value: recorder.isRecording || isThinking || inputFocused)
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.22)) }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Actions

    private func startVoice() {
        synthesizer.stopSpeaking(at: .immediate)
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
        let facts = GhafFinanceFacts.summary(accounts: accounts, transactions: transactions, subscriptions: subscriptions)
        isThinking = true
        replyTask = Task {
            var index: Int?
            do {
                GhafLedgerContext.accounts = accounts
                GhafLedgerContext.transactions = transactions
                GhafLedgerContext.subscriptions = subscriptions
                GhafLedgerContext.currency = settings.currency
                GhafLedgerContext.languageCode = settings.languageCode
                GhafLedgerContext.requestedChart = nil
                let direct = GhafLedgerAnswers.answer(to: resolved, accounts: accounts, transactions: transactions,
                                                      subscriptions: subscriptions, currency: settings.currency,
                                                      languageCode: settings.languageCode)
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
                }
                speak(messages[index].text, force: isVoice)
            }
            isThinking = false
        }
    }

    /// Three useful next questions, chosen from what was just asked, never repeating it.
    private func suggestions(after question: String) -> [String] {
        let q = question.lowercased()
        let pool: [(match: [String], en: String, ar: String)] = [
            (["compare", "قارن"], "Compare with last month", "قارن بالشهر الماضي"),
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
        GhafCloudVoice.shared.onLevel = { level in speechDone.level = level }
        withAnimation(.spring(duration: 0.45)) { voiceMode = true }
        startVoice()
    }

    private func exitVoiceMode() {
        withAnimation(.spring(duration: 0.4)) { voiceMode = false }
        GhafCloudAI.conversational = false
        GhafCloudVoice.shared.stop()
        speechDone.speaking = false
        listenAfterSpeaking = false
        recorder.reset()
        synthesizer.stopSpeaking(at: .immediate)
    }

    private var voiceStatus: String {
        if recorder.isRecording { return ar ? "أستمع…" : "Listening…" }
        if isThinking { return ar ? "أفكر…" : "Thinking…" }
        if speechDone.speaking { return ar ? "أتكلم… اضغط للمقاطعة" : "Speaking… tap to interrupt" }
        return ar ? "اضغط على الدائرة للتحدث" : "Tap the orb to talk"
    }

    private var voiceModeView: some View {
        let lastReply = messages.last { !$0.isUser }?.text ?? ""
        return ZStack {
            GhafAIView.night.opacity(0.98).ignoresSafeArea()
            RadialGradient(colors: [GhafAIView.blue.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 340)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Ghaf AI")
                    .font(GhafTypography.heading(18, languageCode: "en"))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.top, 24)
                Spacer()
                Button {
                    // Tap to interrupt Ghaf, or to start talking.
                    if speechDone.speaking {
                        synthesizer.stopSpeaking(at: .immediate); GhafCloudVoice.shared.stop()
                        speechDone.speaking = false; startVoice()
                    }
                    else if recorder.isRecording { finishVoice() }
                    else if !isThinking { startVoice() }
                } label: {
                    GhafAIOrb(theme: theme, active: (recorder.isRecording || isThinking || speechDone.speaking) && !reduceMotion)
                        .frame(width: 220, height: 220)
                        .scaleEffect(1 + CGFloat(min(recorder.isRecording ? recorder.level : speechDone.level, 1)) * 0.25)
                        .animation(.easeOut(duration: 0.12), value: recorder.isRecording ? recorder.level : speechDone.level)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(voiceStatus)
                Text(voiceStatus)
                    .font(GhafTypography.body(16, languageCode: settings.languageCode, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .contentTransition(.opacity)
                if !GhafCloudAI.isEnabled {
                    Button {
                        UserDefaults.standard.set(true, forKey: GhafCloudAI.enabledKey)
                        engine = assistant.engine
                    } label: {
                        Label(ar ? "فعّل الصوت الطبيعي والذكاء السحابي" : "Turn on the natural voice and Cloud AI", systemImage: "waveform.badge.plus")
                            .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .semibold))
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .background(theme.accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.ghafPress)
                    Text(GhafCloudAI.disclosure(ar: ar))
                        .font(GhafTypography.body(11, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .lineLimit(4)
                }
                Text(recorder.isRecording ? recorder.transcript : lastReply)
                    .font(GhafTypography.body(recorder.isRecording ? 20 : 17, languageCode: settings.languageCode,
                                              weight: recorder.isRecording ? .semibold : .regular))
                    .foregroundStyle(recorder.isRecording ? theme.primaryText : theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 120, alignment: .top)
                    .animation(.easeOut(duration: 0.2), value: recorder.transcript)
                Spacer()
                HStack(spacing: 40) {
                    Button {
                        speakReplies.toggle()
                        if !speakReplies { synthesizer.stopSpeaking(at: .immediate) }
                    } label: {
                        Image(systemName: speechDone.speaking ? "speaker.wave.2.fill" : "speaker.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .frame(width: 64, height: 64)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.ghafPress)
                    .accessibilityLabel(ar ? "الصوت" : "Sound")
                    Button { exitVoiceMode() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(theme.over, in: Circle())
                    }
                    .buttonStyle(.ghafPress)
                    .accessibilityLabel(ar ? "إنهاء المحادثة الصوتية" : "End voice mode")
                }
                .padding(.bottom, 36)
            }
            .frame(maxWidth: 520)
        }
    }

    private func speak(_ text: String, force: Bool = false) {
        guard speakReplies || force || voiceMode, !text.isEmpty else { return }
        if voiceMode && GhafCloudAI.isEnabled {
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

/// Ghaf AI's mark: a blue glass orb with two rings of light turning inside it and a soft halo.
/// It turns faster while Ghaf listens or thinks and stays still with Reduce Motion.
private struct GhafAIOrb: View {
    let theme: GhafTheme
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let speed = active ? 1.8 : 0.6
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                ZStack {
                    // Halo.
                    Circle()
                        .fill(GhafAIView.blue.opacity(active ? 0.55 : 0.4))
                        .blur(radius: size * 0.3)
                        .scaleEffect(1.25 + 0.08 * sin(t * speed * 1.5))
                    // Glass body.
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.35), GhafAIView.light.opacity(0.15), GhafAIView.night.opacity(0.3)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6))
                        .overlay(Circle().stroke(GhafAIView.light.opacity(0.5), lineWidth: 1))
                        .shadow(color: GhafAIView.blue.opacity(0.6), radius: size * 0.12)
                    // Two rings of light turning in opposite directions.
                    Circle()
                        .trim(from: 0, to: 0.55)
                        .stroke(AngularGradient(colors: [GhafAIView.light.opacity(0), GhafAIView.light, .white], center: .center),
                                style: StrokeStyle(lineWidth: max(2, size * 0.035), lineCap: .round))
                        .padding(size * 0.08)
                        .rotationEffect(.degrees(t * 70 * speed))
                        .blur(radius: 0.6)
                    Circle()
                        .trim(from: 0, to: 0.4)
                        .stroke(AngularGradient(colors: [GhafAIView.blue.opacity(0), GhafAIView.blue, Color(red: 0.86, green: 0.91, blue: 1)], center: .center),
                                style: StrokeStyle(lineWidth: max(1.5, size * 0.022), lineCap: .round))
                        .padding(size * 0.2)
                        .rotationEffect(.degrees(-t * 110 * speed + 120))
                    // Specular highlight.
                    Ellipse()
                        .fill(.white.opacity(0.5))
                        .frame(width: size * 0.22, height: size * 0.1)
                        .blur(radius: size * 0.03)
                        .offset(x: -size * 0.16, y: -size * 0.26)
                }
                .frame(width: size, height: size)
                .scaleEffect(1 + 0.03 * sin(t * speed * 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
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
