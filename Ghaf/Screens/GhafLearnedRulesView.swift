import SwiftUI
import SwiftData
import GhafCore

/// Shows the merchant → category rules Ghaf learned from the user's own corrections, with reset.
struct GhafLearnedRulesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \MerchantCategoryRule.updatedAt, order: .reverse) private var rules: [MerchantCategoryRule]
    @Query(sort: \GhafMemory.updatedAt, order: .reverse) private var memories: [GhafMemory]
    @AppStorage(MerchantCategorizer.modelLearningKey) private var modelLearning = true
    @AppStorage(GhafCloudAI.enabledKey) private var cloudEnabled = false
    @AppStorage(GhafMemoryStore.enabledKey) private var memoryEnabled = GhafMemoryStore.defaultEnabled
    let settings: GhafSettings

    private var ar: Bool { settings.languageCode == "ar" }
    private var groupedRules: [(key: String, name: String, category: String, subcategory: String?, hits: Int)] {
        let groups = Dictionary(grouping: rules, by: { rule in
            MerchantName.key(GhafMerchantAliasStore.displayName(rule.normalizedMerchant) ?? rule.normalizedMerchant)
        })
        return groups.compactMap { key, values in
            guard !key.isEmpty, let latest = values.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
            let normalized = latest.normalizedMerchant
            let resolvedName = GhafMerchantAliasStore.displayName(normalized)
            let displayName = resolvedName == normalized ? normalized.capitalized : (resolvedName ?? normalized.capitalized)
            return (key, displayName,
                    latest.category, latest.subcategory, values.reduce(0) { $0 + $1.hits })
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
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
                Toggle(ar ? "دع غاف يتذكر" : "Let Ghaf remember", isOn: $memoryEnabled)
            } footer: {
                Text(ar ? "تُحفظ الذكريات على هذا الـ iPhone. عند تشغيل الذكاء السحابي، تُرسل مع أسئلتك لمساعدتك في الإجابة."
                        : "Memories are stored on this iPhone. When Cloud AI is on, they are sent with your questions to answer them.")
            }
            if !memories.isEmpty {
                Section(ar ? "ما يتذكره غاف" : "What Ghaf remembers") {
                    ForEach(memories) { memory in
                        Text(memory.text).font(GhafTypography.body(14, languageCode: settings.languageCode))
                    }
                    .onDelete { offsets in
                        offsets.map { memories[$0] }.forEach(context.delete)
                        try? context.save()
                    }
                }
                Section {
                    GhafSplitDeleteButton(title: ar ? "انسَ كل الذكريات" : "Forget everything", confirmTitle: ar ? "انسَ الكل" : "Forget all",
                                          theme: theme, languageCode: settings.languageCode) {
                        memories.forEach(context.delete)
                        try? context.save()
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
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
                    .onChange(of: cloudEnabled) { _, enabled in
                        if !enabled { UserDefaults.standard.set(false, forKey: "ghaf.ai.liveConsentAccepted") }
                    }
            } header: {
                Text(ar ? "اختياري" : "Optional")
            } footer: {
                Text(GhafCloudAI.disclosure(ar: ar))
            }
            if rules.isEmpty {
                Text(ar ? "لم يتعلم غاف شيئاً بعد." : "Ghaf hasn't learned anything yet.")
                    .foregroundStyle(theme.secondaryText)
            } else {
                Section(ar ? "التجار" : "Merchants") {
                    ForEach(Array(groupedRules.enumerated()), id: \.offset) { element in
                        let row = element.element
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name).font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold))
                                Text(GhafLocalization.category(row.category, languageCode: settings.languageCode)
                                     + (row.subcategory.map { " › " + GhafLocalization.category($0, languageCode: settings.languageCode) } ?? ""))
                                    .font(GhafTypography.body(13, languageCode: settings.languageCode)).foregroundStyle(theme.accent)
                            }
                            Spacer(minLength: 4)
                            let count = row.hits.formatted(.number.locale(Locale(identifier: ar ? "ar_AE" : "en_US")))
                            let arabicCount = row.hits == 1 ? "مرة واحدة" : (row.hits == 2 ? "مرتان" : "\(count) مرات")
                            Text(ar ? arabicCount : "\(count)×")
                                .font(GhafTypography.body(12, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText)
                                .accessibilityLabel(ar ? "تأكيدات: \(count)" : "Confirmed \(count) times")
                        }
                    }
                    .onDelete { offsets in
                        let keys = Set(offsets.compactMap { index in groupedRules.indices.contains(index) ? groupedRules[index].key : nil })
                        rules.filter { keys.contains(MerchantName.key(GhafMerchantAliasStore.displayName($0.normalizedMerchant) ?? $0.normalizedMerchant)) }.forEach(context.delete)
                        try? context.save()
                    }
                }
                Section {
                    GhafSplitDeleteButton(title: ar ? "مسح كل ما تعلّمه غاف" : "Reset everything Ghaf learned", confirmTitle: ar ? "مسح" : "Reset",
                                          theme: theme, languageCode: settings.languageCode) {
                        rules.forEach(context.delete)
                        try? context.save()
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
        }
        .scrollContentBackground(.hidden)
        .ghafBackground(theme: theme)
        .ghafPageTitle(ar ? "ما تعلّمه غاف" : "What Ghaf learned", languageCode: settings.languageCode, theme: theme)
        .toolbar(.visible, for: .navigationBar)
    }
}
