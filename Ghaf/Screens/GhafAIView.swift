import SwiftUI
import SwiftData
import AVFoundation
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
}

struct GhafAIView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @Query private var subscriptions: [GhafSubscription]

    @StateObject private var assistant = GhafAssistant()
    @StateObject private var recorder = GhafSpeechRecorder()
    @State private var prompt = ""
    @State private var messages: [GhafChatMessage] = []
    @State private var isThinking = false
    @State private var replyTask: Task<Void, Never>?
    @AppStorage("ghaf.ai.speakReplies") private var speakReplies = false
    @State private var synthesizer = AVSpeechSynthesizer()
    @FocusState private var inputFocused: Bool

    let settings: GhafSettings
    private var ar: Bool { settings.languageCode == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
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
            .ghafBackground(theme: theme)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: recorder.transcript) { _, text in
                if recorder.isRecording { prompt = text }
            }
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
                    }
                    .accessibilityLabel(ar ? "قراءة الردود بصوت" : "Read replies aloud")
                }
                GhafAIOrb(theme: theme, active: isThinking || recorder.isRecording)
                    .frame(width: 54, height: 54)
            }
            Text("Ghaf AI")
                .font(GhafTypography.display(24, languageCode: "en"))
                .foregroundStyle(theme.primaryText)
            Label(engineLabel, systemImage: assistant.engine == .onDevice ? "lock.shield.fill" : "bolt.horizontal.fill")
                .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
    }

    private var engineLabel: String {
        switch assistant.engine {
        case .onDevice: ar ? "ذكاء Apple على جهازك · خاص" : "Apple Intelligence on this iPhone · private"
        case .basic: ar ? "الوضع الأساسي · فعّل Apple Intelligence لمحادثة كاملة" : "Basic mode · turn on Apple Intelligence for full chat"
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 14) {
            Text(ar ? "اسألني عن أموالك، أو قل ما اشتريت وسأسجله." : "Ask about your money, or just say what you bought and I'll log it.")
                .font(GhafTypography.body(15, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            let chips = ar
                ? ["كم صرفت هالأسبوع؟", "وين أكثر مكان صرفت فيه؟", "كم رصيدي؟", "ما الاشتراكات القادمة؟", "٣٥ درهم غداء", "قارن هذا الشهر بالماضي"]
                : ["How much did I spend this week?", "Where did most of my money go?", "What's my balance?", "Which subscriptions are due?", "35 AED lunch", "Compare this month to last month"]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(chips, id: \.self) { chip in
                    Button { send(chip) } label: {
                        Text(chip)
                            .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .padding(.horizontal, 10)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.outline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
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
                    Text(item.text)
                        .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: item.isUser ? .semibold : .regular))
                        .textSelection(.enabled)
                }
                .foregroundStyle(item.isUser ? theme.accentContrast : theme.primaryText)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(item.isUser ? theme.accent : theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.merchant.isEmpty ? (ar ? "بدون اسم" : "No name") : draft.merchant)
                            .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                        Menu {
                            ForEach(settings.categories, id: \.self) { category in
                                Button(GhafLocalization.category(category, languageCode: settings.languageCode)) { draft.category = category }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(GhafLocalization.category(draft.category, languageCode: settings.languageCode))
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                            }
                            .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .semibold))
                            .foregroundStyle(theme.accent)
                        }
                        .disabled(state != .pending)
                    }
                    Spacer(minLength: 6)
                    GhafMoneyLabel(amount: draft.amount, currency: draft.currency, languageCode: settings.languageCode, size: 16)
                        .foregroundStyle(draft.direction == "credit" ? theme.credit : theme.primaryText)
                }
            }
            switch state {
            case .pending:
                HStack(spacing: 10) {
                    Button { message.wrappedValue.draftState = .discarded } label: {
                        Text(ar ? "تجاهل" : "Discard").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered).tint(theme.secondaryText)
                    Button { saveDrafts(message) } label: {
                        Text(ar ? "حفظ" : "Save").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(theme.accent)
                }
                .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .bold))
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
        .padding(14)
        .frame(maxWidth: 340)
        .ghafCard(theme: theme, radius: 18)
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
        .background(theme.surface, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Input

    private var inputBar: some View {
        let hasText = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 6) {
            if recorder.isRecording {
                Text(ar ? "أستمع… اضغط للإرسال" : "Listening… tap to send")
                    .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .bold))
                    .foregroundStyle(theme.accent)
            } else if let error = recorder.errorMessage {
                Text(error)
                    .font(GhafTypography.body(12, languageCode: settings.languageCode))
                    .foregroundStyle(theme.over)
            }
            HStack(spacing: 10) {
                TextField(ar ? "اسأل غاف أو اكتب مصروفاً…" : "Ask Ghaf or type a purchase…", text: $prompt, axis: .vertical)
                    .font(GhafTypography.body(15, languageCode: settings.languageCode))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { send(prompt) }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(theme.outline, lineWidth: 1))

                Button {
                    if recorder.isRecording { finishVoice() }
                    else if hasText { send(prompt) }
                    else { startVoice() }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : (hasText ? "arrow.up" : "mic.fill"))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(theme.accentContrast)
                        .frame(width: 50, height: 50)
                        .background(recorder.isRecording ? theme.over : theme.accent, in: Circle())
                        .symbolEffect(.pulse, isActive: recorder.isRecording)
                }
                .disabled(isThinking && !recorder.isRecording)
                .accessibilityLabel(recorder.isRecording ? (ar ? "إيقاف وإرسال" : "Stop and send")
                                    : hasText ? (ar ? "إرسال" : "Send") : (ar ? "رسالة صوتية" : "Voice message"))
            }
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
        Task { await recorder.start(languageCode: settings.languageCode) }
    }

    private func finishVoice() {
        recorder.stop()
        let text = recorder.transcript.isEmpty ? prompt : recorder.transcript
        recorder.reset()
        send(text, isVoice: true)
    }

    private func send(_ raw: String, isVoice: Bool = false) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        prompt = ""
        withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: true, text: text, isVoice: isVoice)) }

        // A purchase ("35 AED lunch") becomes a draft card; anything else goes to the assistant.
        let drafts = GhafMessageIntent.drafts(in: text, baseCurrency: settings.currency).map { draft -> GhafVoiceTransactionDraft in
            var result = draft
            let direction = TransactionDirection(rawValue: draft.direction) ?? .debit
            result.category = (try? MerchantCategorizer.category(for: draft.merchant, direction: direction, context: modelContext)) ?? "Other"
            return result
        }
        if !drafts.isEmpty {
            let intro = ar
                ? (drafts.count == 1 ? "وجدت عملية. راجع الفئة ثم احفظ:" : "وجدت \(drafts.count) عمليات. راجعها ثم احفظ:")
                : (drafts.count == 1 ? "Got it. Check the category, then save:" : "I found \(drafts.count) transactions. Check them, then save:")
            withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: false, text: intro, drafts: drafts)) }
            speak(intro)
            return
        }

        let history = messages.dropLast().filter { !$0.text.isEmpty }.map { (isUser: $0.isUser, text: $0.text) }
        let facts = GhafFinanceFacts.summary(accounts: accounts, transactions: transactions, subscriptions: subscriptions)
        isThinking = true
        replyTask = Task {
            var index: Int?
            do {
                for try await partial in assistant.reply(to: text, facts: facts, history: Array(history), languageCode: settings.languageCode) {
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
                speak(messages[index].text)
            }
            isThinking = false
        }
    }

    private func saveDrafts(_ message: Binding<GhafChatMessage>) {
        do {
            try GhafDraftSaver.save(message.wrappedValue.drafts, preferredAccountID: nil, accounts: accounts,
                                    context: modelContext, note: ar ? "أضيفت عبر غاف AI" : "Added with Ghaf AI")
            message.wrappedValue.draftState = .saved
            let learned = message.wrappedValue.drafts.filter { !$0.merchant.isEmpty && $0.category != "Other" }
            let note = learned.isEmpty ? (ar ? "تم الحفظ." : "Saved.") : (ar
                ? "تم الحفظ. سأتذكر أن " + learned.map { "\($0.merchant) ← \(GhafLocalization.category($0.category, languageCode: "ar"))" }.joined(separator: "، ") + "."
                : "Saved. I'll remember " + learned.map { "\($0.merchant) → \($0.category)" }.joined(separator: ", ") + ".")
            withAnimation(.snappy) { messages.append(GhafChatMessage(isUser: false, text: note)) }
        } catch {
            withAnimation(.snappy) {
                messages.append(GhafChatMessage(isUser: false, text: ar ? "تعذر الحفظ. حاول مرة أخرى." : "Couldn't save. Try again."))
            }
        }
    }

    private func speak(_ text: String) {
        guard speakReplies, !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: ar ? "ar-SA" : "en-US")
        synthesizer.speak(utterance)
    }
}

/// Breathing gradient orb that shows when Ghaf AI is listening or thinking.
private struct GhafAIOrb: View {
    let theme: GhafTheme
    let active: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [theme.accent, theme.credit, theme.accent.opacity(0.6), theme.accent], center: .center))
                .blur(radius: active ? 6 : 3)
                .scaleEffect(active ? 1.08 : 0.94)
                .animation(active ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: active)
            Circle().fill(theme.surface).padding(5)
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.accent)
                .symbolEffect(.bounce, value: active)
        }
        .accessibilityHidden(true)
    }
}
