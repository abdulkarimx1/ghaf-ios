import SwiftUI
import SwiftData

/// Shows the merchant → category rules Ghaf learned from the user's own corrections, with reset.
struct GhafLearnedRulesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \MerchantCategoryRule.updatedAt, order: .reverse) private var rules: [MerchantCategoryRule]
    @State private var confirmReset = false
    @AppStorage(MerchantCategorizer.modelLearningKey) private var modelLearning = true
    @AppStorage(GhafCloudAI.enabledKey) private var cloudEnabled = false
    @AppStorage(GhafCloudAI.urlKey) private var cloudURL = ""
    @State private var cloudToken = Keychain.read(GhafCloudAI.tokenKey) ?? ""
    let settings: GhafSettings

    private var ar: Bool { settings.languageCode == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        List {
            Section {
                Text(ar ? "عندما تختار فئة لتاجر، يحفظ غاف ذلك على جهازك ويستخدمه في المرات القادمة. لا يُرسل شيء إلى أي خادم."
                        : "When you pick a category for a merchant, Ghaf saves it on this iPhone and uses it next time. Nothing is sent to a server.")
                    .font(GhafTypography.body(13, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
            Section {
                Toggle(ar ? "التعلّم من عملياتي" : "Learn from my transactions", isOn: $modelLearning)
                    .onChange(of: modelLearning) { _, _ in MerchantCategorizer.invalidateLearner() }
            } footer: {
                Text(ar ? "يدرّب غاف نموذجاً صغيراً على جهازك من العمليات التي أكدتها (اسم التاجر، المبلغ، الوقت) ليقترح الفئة للتجار الجدد. يُعاد بناؤه من سجلاتك فقط، ولا يغادر جهازك، والاقتراحات غير المؤكدة تذهب للمراجعة."
                        : "Ghaf trains a small model on this iPhone from transactions you've confirmed (merchant, amount, time) to suggest categories for new merchants. It's rebuilt only from your records, never leaves the device, and unsure guesses go to review.")
            }
            Section {
                Toggle(ar ? "الذكاء السحابي" : "Cloud AI", isOn: $cloudEnabled)
                if cloudEnabled {
                    TextField(ar ? "رابط الخادم (https://…)" : "Server URL (https://…)", text: $cloudURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(ar ? "رمز الوصول" : "Access token", text: $cloudToken)
                        .onChange(of: cloudToken) { _, value in
                            value.isEmpty ? Keychain.delete(GhafCloudAI.tokenKey) : Keychain.save(value, for: GhafCloudAI.tokenKey)
                        }
                    if !cloudURL.isEmpty && GhafCloudAI.endpoint == nil {
                        Text(ar ? "يجب أن يبدأ الرابط بـ https://" : "The URL must start with https://")
                            .foregroundStyle(theme.over)
                    }
                }
            } header: {
                Text(ar ? "اختياري" : "Optional")
            } footer: {
                Text(ar ? "يستخدم خادمك الخاص (Cloudflare Worker مجاني) مع Gemini لإجابات أذكى. يُرسل سؤالك وملخص المجاميع وإجابة سجلك فقط، ولا تُرسل قائمة عملياتك. تطبّق شروط Google على الطلب. عند أي خطأ يجيب غاف من جهازك."
                        : "Uses your own server (a free Cloudflare Worker) with Gemini for richer replies. Sends your question, a summary of totals and the ledger's answer, never your transaction list. Google's terms apply to the request. If anything fails, Ghaf answers on the device.")
            }
            if rules.isEmpty {
                Text(ar ? "لم يتعلم غاف شيئاً بعد." : "Ghaf hasn't learned anything yet.")
                    .foregroundStyle(theme.secondaryText)
            } else {
                Section(ar ? "التجار" : "Merchants") {
                    ForEach(rules) { rule in
                        HStack {
                            Text(rule.normalizedMerchant.capitalized)
                                .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold))
                            Spacer()
                            Text(GhafLocalization.category(rule.category, languageCode: settings.languageCode))
                                .font(GhafTypography.body(14, languageCode: settings.languageCode))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { rules[$0] }.forEach(context.delete)
                        try? context.save()
                    }
                }
                Section {
                    Button(ar ? "مسح كل ما تعلّمه غاف" : "Reset everything Ghaf learned", role: .destructive) { confirmReset = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .ghafBackground(theme: theme)
        .navigationTitle(ar ? "ما تعلّمه غاف" : "What Ghaf learned")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog(ar ? "مسح كل القواعد المتعلَّمة؟" : "Reset all learned rules?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button(ar ? "مسح" : "Reset", role: .destructive) {
                rules.forEach(context.delete)
                try? context.save()
            }
        } message: {
            Text(ar ? "لن تتأثر عملياتك المسجلة." : "Your recorded transactions are not changed.")
        }
    }
}
