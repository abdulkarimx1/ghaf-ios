import SwiftUI
import SwiftData
import GhafCore

struct GhafVoiceEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
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
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.outline, lineWidth: 1))
                }
                .buttonStyle(.plain)
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
                        .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(theme.secondaryText)
                    TextEditor(text: $transcript)
                        .font(GhafTypography.body(14, languageCode: settings.languageCode))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 104)
                        .padding(10)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.outline, lineWidth: 1))
                        .onChange(of: transcript) { _, value in updateDrafts(from: value) }
                    Text(isArabic
                         ? "راجع النص والعمليات المقترحة قبل الحفظ. لا تُحفظ أي عملية تلقائياً."
                         : "Review the transcript and suggested transactions before saving. Nothing is saved automatically.")
                        .font(GhafTypography.body(11, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                }

                if !drafts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isArabic ? "العمليات المقترحة · \(drafts.count)" : "SUGGESTED TRANSACTIONS · \(drafts.count)")
                            .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(theme.secondaryText)

                        ForEach($drafts) { $draft in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    TextField(isArabic ? "اسم المتجر" : "Merchant", text: $draft.merchant)
                                        .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                                        .foregroundStyle(theme.primaryText)
                                    Spacer(minLength: 8)
                                    Text(GhafFormat.money(draft.amount, currency: draft.currency, languageCode: settings.languageCode))
                                        .font(GhafTypography.number(15, weight: .semibold))
                                        .foregroundStyle(theme.primaryText)
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
                                    Text(draft.direction == "credit" ? (isArabic ? "دخل" : "Income") : (isArabic ? "مصروف" : "Expense"))
                                        .font(GhafTypography.body(11, languageCode: settings.languageCode))
                                        .foregroundStyle(theme.secondaryText)
                                }
                                DatePicker(isArabic ? "التاريخ والوقت" : "Date and time", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                                    .font(GhafTypography.body(11, languageCode: settings.languageCode))
                                    .tint(theme.accent)
                            }
                            .padding(13)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.outline, lineWidth: 1))
                        }

                        if accounts.count > 1 {
                            Text(isArabic ? "الحساب الافتراضي" : "DEFAULT ACCOUNT")
                                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
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
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(isArabic ? "إضافة بالصوت" : "Voice entry")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            transcript = recorder.transcript
            selectedAccountID = accounts.first(where: { $0.isPrimary && !$0.isArchived })?.id
                ?? accounts.first(where: { !$0.isArchived })?.id
        }
        .onChange(of: recorder.transcript) { _, value in transcript = value }
        .onDisappear { recorder.reset() }
        .animation(.easeInOut(duration: 0.2), value: drafts.count)
    }

    private func updateDrafts(from text: String) {
        drafts = GhafVoiceTransactionParser.parse(text, languageCode: settings.languageCode, baseCurrency: settings.currency).map { parsed in
            var result = parsed
            let direction = TransactionDirection(rawValue: parsed.direction) ?? .debit
            result.category = (try? MerchantCategorizer.category(for: parsed.merchant, direction: direction, context: modelContext)) ?? "Other"
            return result
        }
    }

    private func saveDrafts() {
        guard !drafts.isEmpty else { return }
        isSaving = true
        errorMessage = ""
        do {
            for draft in drafts {
                let direction = TransactionDirection(rawValue: draft.direction) ?? .debit
                let parsed = ParsedTransaction(amount: draft.amount, currency: draft.currency, merchant: draft.merchant.isEmpty ? nil : draft.merchant, date: draft.date, direction: direction, confidence: 0.82, bank: nil)
                let category = draft.category == "Other"
                    ? ((try? MerchantCategorizer.category(for: draft.merchant, direction: direction, context: modelContext)) ?? "Other")
                    : draft.category
                let matchingAccount = accounts.first { !$0.isArchived && $0.currency == draft.currency }
                let transaction = GhafTransaction(fingerprint: "voice-\(UUID().uuidString)", parsed: parsed, category: category, needsReview: draft.merchant.isEmpty || category == "Other", isReversal: false, accountID: matchingAccount?.id ?? selectedAccountID)
                transaction.note = isArabic ? "تمت الإضافة بالصوت" : "Added by voice"
                modelContext.insert(transaction)
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = isArabic ? "تعذر حفظ العمليات. حاول مرة أخرى." : "Could not save the transactions. Try again."
            isSaving = false
        }
    }
}
