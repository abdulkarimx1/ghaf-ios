import SwiftUI
import SwiftData

struct GhafAIView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @Query private var subscriptions: [GhafSubscription]
    @State private var prompt = ""
    @State private var messages: [String] = []
    let settings: GhafSettings
    private var theme: GhafTheme { GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("GHAF INTELLIGENCE")
                            .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .bold)).tracking(1.5)
                            .foregroundStyle(theme.secondaryText)
                        Text(settings.languageCode == "ar" ? "مساعدك المالي" : "Your financial assistant")
                            .font(GhafTypography.display(32, languageCode: settings.languageCode)).foregroundStyle(theme.primaryText)
                        Text(settings.languageCode == "ar" ? "يفهم بياناتك المالية ويساعدك على اتخاذ قرارات أوضح." : "A connected assistant for understanding your money and making better decisions.")
                            .font(GhafTypography.body(15, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText)
                        VStack(alignment: .leading, spacing: 12) {
                            Label(settings.languageCode == "ar" ? "سياقك المالي" : "Your Ghaf context", systemImage: "brain.head.profile")
                                .font(GhafTypography.heading(17, languageCode: settings.languageCode)).foregroundStyle(theme.primaryText)
                            contextMetric(settings.languageCode == "ar" ? "العمليات المسجلة" : "Recorded transactions", value: "\(transactions.count)")
                            contextMetric(settings.languageCode == "ar" ? "الحسابات النشطة" : "Active accounts", value: "\(accounts.filter { !$0.isArchived }.count)")
                            contextMetric(settings.languageCode == "ar" ? "الاشتراكات النشطة" : "Active subscriptions", value: "\(subscriptions.filter(\.isActive).count)")
                        }.padding(17).ghafCard(theme: theme, radius: 18)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(settings.languageCode == "ar" ? "ابدأ بسؤال" : "Try asking")
                                .font(GhafTypography.heading(17, languageCode: settings.languageCode)).foregroundStyle(theme.primaryText)
                            suggestion(settings.languageCode == "ar" ? "كم صرفت هذا الشهر؟" : "How much did I spend this month?")
                            suggestion(settings.languageCode == "ar" ? "ما الاشتراكات القادمة؟" : "Which subscriptions are coming up?")
                            suggestion(settings.languageCode == "ar" ? "ما أكثر فئة أنفق عليها؟" : "What category do I spend most on?")
                        }.padding(17).ghafCard(theme: theme, radius: 18)
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            Text(message)
                                .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: index.isMultiple(of: 2) ? .bold : .regular))
                                .foregroundStyle(index.isMultiple(of: 2) ? theme.accentContrast : theme.primaryText)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: index.isMultiple(of: 2) ? .trailing : .leading)
                                .background(index.isMultiple(of: 2) ? theme.accent : theme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                        Text(settings.languageCode == "ar" ? "الإجابات محسوبة على جهازك من بياناتك فقط." : "Answers are worked out on your device from your own data.")
                            .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
                HStack(spacing: 10) {
                    TextField(settings.languageCode == "ar" ? "اسأل غاف..." : "Ask Ghaf...", text: $prompt, axis: .vertical)
                        .lineLimit(1...4).padding(13)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    Button(action: submit) {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.accentContrast).frame(width: 48, height: 48)
                            .background(theme.accent, in: Circle())
                    }.disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(14).background(theme.background)
            }
            .ghafBackground(theme: theme).toolbar(.hidden, for: .navigationBar)
        }
    }

    private func contextMetric(_ title: String, value: String) -> some View {
        HStack { Text(title).font(GhafTypography.body(13, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText); Spacer(); Text(value).font(GhafTypography.number(15, weight: .bold)).foregroundStyle(theme.primaryText) }
    }
    private func suggestion(_ value: String) -> some View {
        Button(value) { prompt = value }
            .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
            .foregroundStyle(theme.accent).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7)
    }
    private func submit() {
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        messages.append(question)
        messages.append(answer(to: question.lowercased()))
        prompt = ""
    }

    /// Rule-based answers from local data; no cloud model is connected.
    private func answer(to q: String) -> String {
        let ar = settings.languageCode == "ar"
        let calendar = Calendar.current
        let monthDebits = transactions.filter {
            $0.direction == "debit" && !$0.isReversal && $0.currency == settings.currency
                && calendar.isDate($0.date, equalTo: .now, toGranularity: .month)
        }
        func money(_ value: Decimal, _ currency: String? = nil) -> String {
            GhafFormat.money(value, currency: currency ?? settings.currency, languageCode: settings.languageCode)
        }

        if q.contains("subscription") || q.contains("اشتراك") {
            let soon = subscriptions
                .filter { $0.isActive && $0.nextPaymentDate <= calendar.date(byAdding: .day, value: 30, to: .now)! }
                .sorted { $0.nextPaymentDate < $1.nextPaymentDate }
            guard !soon.isEmpty else {
                return ar ? "لا توجد اشتراكات مستحقة خلال ٣٠ يوماً." : "No subscriptions are due in the next 30 days."
            }
            return soon.map {
                "\($0.name): \(money($0.amount, $0.currency)) · \($0.nextPaymentDate.formatted(.dateTime.day().month(.abbreviated)))"
            }.joined(separator: "\n")
        }
        if q.contains("category") || q.contains("فئة") {
            let byCategory = Dictionary(grouping: monthDebits, by: \.category)
                .mapValues { $0.reduce(Decimal.zero) { $0 + $1.amount } }
            guard let top = byCategory.max(by: { $0.value < $1.value }) else {
                return ar ? "لا توجد مصاريف هذا الشهر بعد." : "No spending recorded this month yet."
            }
            return ar ? "أكثر فئة: \(top.key) بمبلغ \(money(top.value))." : "Top category: \(top.key) at \(money(top.value))."
        }
        if q.contains("spen") || q.contains("صرف") {
            let total = monthDebits.reduce(Decimal.zero) { $0 + $1.amount }
            return ar ? "صرفت \(money(total)) هذا الشهر في \(monthDebits.count) عملية."
                      : "You spent \(money(total)) this month across \(monthDebits.count) transactions."
        }
        return ar ? "أستطيع الإجابة عن: مصروف الشهر، الاشتراكات القادمة، وأكثر فئة تنفق عليها."
                  : "I can answer: spending this month, upcoming subscriptions, and your top category."
    }
}
