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
    /// Transactions created when the drafts were saved, so later corrections can update them.
    var savedIDs: [UUID] = []
}

struct GhafAIView: View {
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
    @FocusState private var inputFocused: Bool
    @State private var savedCount = 0
    /// Model availability is costly to query; read it when the tab appears, not on every render.
    @State private var engine: GhafAssistant.Engine = .basic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .background(theme.surface, in: Circle())
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
            Label(engineLabel, systemImage: engine == .onDevice ? "lock.shield.fill" : "bolt.horizontal.fill")
                .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
    }

    private var engineLabel: String {
        switch engine {
        case .onDevice: ar ? "ذكاء Apple على جهازك · خاص" : "Apple Intelligence on this iPhone · private"
        case .basic: ar ? "الوضع الأساسي · فعّل Apple Intelligence لمحادثة كاملة" : "Basic mode · turn on Apple Intelligence for full chat"
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 16) {
            GhafAIOrb(theme: theme, active: false)
                .frame(width: 88, height: 88)
                .padding(.top, 12)
            Text(ar ? "كيف أساعدك اليوم؟" : "How can I help today?")
                .font(GhafTypography.display(28, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
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
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .padding(.horizontal, 12)
                            .ghafCard(theme: theme, radius: 20)
                    }
                    .buttonStyle(.ghafPress)
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
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(item.isUser ? theme.accent : theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: item.isUser ? .clear : theme.shadow, radius: 8, y: 3)
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
                                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
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
        .ghafCard(theme: theme, radius: 22)
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

                Button {
                    if recorder.isRecording { finishVoice() }
                    else if hasText { send(prompt) }
                    else { startVoice() }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : (hasText ? "arrow.up" : "mic.fill"))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(theme.accentContrast)
                        .frame(width: 44, height: 44)
                        .background(recorder.isRecording ? theme.over : theme.accent, in: Circle())
                        .symbolEffect(.pulse, isActive: recorder.isRecording)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.ghafPress)
                .disabled(isThinking && !recorder.isRecording)
                .accessibilityLabel(recorder.isRecording ? (ar ? "إيقاف وإرسال" : "Stop and send")
                                    : hasText ? (ar ? "إرسال" : "Send") : (ar ? "رسالة صوتية" : "Voice message"))
            }
            .padding(5)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
            .shadow(color: theme.shadow, radius: 12, y: 4)
            .overlay { if theme.isDark { RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(theme.outline) } }
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
    /// unclear speech stays in the box to fix and send.
    private func finishVoice() {
        recorder.stop()
        let text = (recorder.transcript.isEmpty ? prompt : recorder.transcript).trimmingCharacters(in: .whitespacesAndNewlines)
        recorder.reset()
        let letters = text.filter(\.isLetter).count
        let understood = GhafMessageIntent.isQuestion(text)
            || !GhafMessageIntent.drafts(in: text, baseCurrency: settings.currency).isEmpty
            || ChatCorrection.parse(text, recent: recentDraftRefs().map(\.name)) != nil
        if letters >= 2 && understood {
            send(text, isVoice: true)
        } else {
            prompt = text
            withAnimation(.snappy) {
                messages.append(GhafChatMessage(isUser: false, text: text.isEmpty
                    ? (ar ? "لم أسمع شيئاً. اضغط الميكروفون وحاول مرة أخرى." : "I didn't hear anything. Tap the mic and try again.")
                    : (ar ? "لم أفهم كل الكلام. عدّل النص في الأسفل ثم أرسله، أو سجّل مرة أخرى."
                          : "I didn't catch all of that. Fix the text below and send it, or record again.")))
            }
        }
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
