import SwiftUI
import SwiftData
import GhafCore

struct GhafVoiceEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]

    @StateObject private var recorder = GhafSpeechRecorder()
    @State private var transcript = ""
    @State private var drafts: [GhafVoiceTransactionDraft] = []
    @State private var selectedAccountID: UUID?
    @State private var errorMessage = ""
    @State private var isSaving = false

    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: systemColorScheme == .dark)
    }
    private var isArabic: Bool { settings.languageCode == "ar" }
    private var transcriptLanguageCode: String {
        transcript.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) } ? "ar" : "en"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isArabic ? "تحدث، وغاف يتولى الباقي" : "Say it. Ghaf sorts it.")
                        .font(GhafTypography.display(27, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)
                    Text(isArabic
                         ? "اذكر مشترياتك والمبالغ، ويمكنك تسجيل أكثر من عملية في نفس المقطع."
                         : "Describe your purchases and amounts. You can include several transactions in one recording.")
                        .font(GhafTypography.body(14, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                    Text(isArabic
                         ? "مثال: اشتريت بقالة بـ ٥٦٠ درهماً، ثم أدوية بـ ١٢٠ درهماً الساعة ٣ مساءً."
                         : "Example: Groceries for AED 560, then medicine for AED 120 at 3 pm.")
                        .font(GhafTypography.body(11, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        Task { await recorder.start(languageCode: settings.languageCode) }
                    }
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(theme.accentContrast)
                            .frame(width: 76, height: 76)
                            .background(recorder.isRecording ? theme.over : theme.accent, in: Circle())
                            .scaleEffect(recorder.isRecording ? 1.06 : 1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: recorder.isRecording)
                        Text(recorder.isRecording
                             ? (isArabic ? "إيقاف التسجيل" : "Stop recording")
                             : (isArabic ? "ابدأ التحدث" : "Start speaking"))
                            .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 22), fallback: theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.outline, lineWidth: 1))
                }
                .buttonStyle(.ghafPress)
                .disabled(isSaving)

                if recorder.isRecording {
                    HStack(spacing: 8) {
                        Circle().fill(theme.over).frame(width: 7, height: 7)
                        Text(isArabic ? "جاري الاستماع..." : "Listening...")
                            .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(isArabic ? "النص المتعرف عليه" : "RECOGNIZED TEXT")
                        .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(theme.secondaryText)
                    TextEditor(text: $transcript)
                        .font(GhafTypography.body(14, languageCode: settings.languageCode))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 104)
                        .padding(10)
                        .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 15), fallback: theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.outline, lineWidth: 1))
                        .onChange(of: transcript) { _, value in updateDrafts(from: value) }
                    Text(isArabic
                         ? "راجع النص والعمليات المقترحة قبل الحفظ. لا تُحفظ أي عملية تلقائياً."
                         : "Review the transcript and suggested transactions before saving. Nothing is saved automatically.")
                        .font(GhafTypography.body(11, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                    Text(isArabic
                         ? "يستخدم غاف التعرّف على الكلام من iOS، ويفضّل المعالجة على الجهاز عندما تكون متاحة. قد تتطلب بعض اللغات اتصالاً بالإنترنت."
                         : "Ghaf uses iOS Speech Recognition and prefers on-device processing when available. Some languages may require an internet connection.")
                        .font(GhafTypography.body(11, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !drafts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isArabic ? "العمليات المقترحة · \(drafts.count)" : "SUGGESTED TRANSACTIONS · \(drafts.count)")
                            .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(theme.secondaryText)

                        ForEach($drafts) { $draft in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    TextField(isArabic ? "اسم المتجر" : "Merchant", text: $draft.merchant)
                                        .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                                        .foregroundStyle(theme.primaryText)
                                    Spacer(minLength: 8)
                                    HStack(spacing: 5) {
                                        GhafCurrencyIcon(currency: draft.currency, size: 16)
                                        TextField("0.00", text: $draft.amountText)
                                            .font(GhafTypography.number(15, weight: .semibold))
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 92)
                                            .foregroundStyle(theme.primaryText)
                                    }
                                }
                                HStack {
                                    Picker(isArabic ? "الفئة" : "Category", selection: $draft.category) {
                                        ForEach(settings.categories, id: \.self) {
                                            Text(GhafLocalization.category($0, languageCode: settings.languageCode)).tag($0)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(theme.accent)
                                    Spacer()
                                    Picker(isArabic ? "النوع" : "Type", selection: $draft.direction) {
                                        Text(isArabic ? "مصروف" : "Expense").tag("debit")
                                        Text(isArabic ? "دخل" : "Income").tag("credit")
                                    }
                                    .pickerStyle(.menu)
                                    .tint(theme.accent)
                                }
                                DatePicker(isArabic ? "التاريخ والوقت" : "Date and time", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                                    .font(GhafTypography.body(11, languageCode: settings.languageCode))
                                    .tint(theme.accent)
                            }
                            .padding(13)
                            .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 15), fallback: theme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.outline, lineWidth: 1))
                        }

                        if accounts.count > 1 {
                            Text(isArabic ? "الحساب الافتراضي" : "DEFAULT ACCOUNT")
                                .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(theme.secondaryText)
                            Picker(isArabic ? "الحساب" : "Account", selection: $selectedAccountID) {
                                ForEach(accounts.filter { !$0.isArchived }, id: \.id) { account in
                                    Text("\(account.name) · \(account.currency)").tag(Optional(account.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(theme.accent)
                        }

                        Button(action: saveDrafts) {
                            HStack {
                                if isSaving { ProgressView().tint(theme.accentContrast) }
                                Text(isArabic ? "حفظ جميع العمليات" : "Save all transactions")
                            }
                        }
                        .ghafProminentButton(theme: theme, languageCode: settings.languageCode)
                        .disabled(isSaving)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let recorderError = recorder.errorMessage {
                    Text(recorderError)
                        .font(GhafTypography.body(12, languageCode: settings.languageCode))
                        .foregroundStyle(theme.over)
                }
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(GhafTypography.body(12, languageCode: settings.languageCode))
                        .foregroundStyle(theme.over)
                }
            }
            .padding(20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .ghafKeyboardDone()
        .navigationTitle(isArabic ? "إضافة بالصوت" : "Voice entry")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            transcript = recorder.transcript
            selectedAccountID = accounts.first(where: { $0.isPrimary && !$0.isArchived })?.id
                ?? accounts.first(where: { !$0.isArchived })?.id
        }
        .onChange(of: recorder.transcript) { _, value in transcript = value }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { recorder.stop() }
        }
        .onDisappear { recorder.reset() }
        .animation(.easeInOut(duration: 0.2), value: drafts.count)
    }

    private func updateDrafts(from text: String) {
        drafts = GhafVoiceTransactionParser.parse(text, languageCode: text.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) } ? "ar" : "en", baseCurrency: settings.currency).map { parsed in
            var result = parsed
            let direction = TransactionDirection(rawValue: parsed.direction) ?? .debit
            result.category = (try? MerchantCategorizer.category(for: parsed.merchant, direction: direction, context: modelContext)) ?? "Other"
            return result
        }
    }

    private func saveDrafts() {
        guard !drafts.isEmpty else { return }
        guard drafts.allSatisfy({ $0.amount > 0 }) else {
            errorMessage = isArabic ? "راجع المبالغ وأدخل قيمة صحيحة لكل عملية." : "Check the amounts and enter a valid value for every transaction."
            return
        }
        isSaving = true
        errorMessage = ""
        do {
            try GhafDraftSaver.save(drafts, preferredAccountID: selectedAccountID, accounts: accounts,
                                    context: modelContext, note: isArabic ? "تمت الإضافة بالصوت" : "Added by voice")
            dismiss()
        } catch {
            errorMessage = isArabic ? "تعذر حفظ العمليات. حاول مرة أخرى." : "Could not save the transactions. Try again."
            isSaving = false
        }
    }
}
