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
                        Text(settings.languageCode == "ar" ? "الاتصال الذكي السحابي قيد الإعداد" : "Secure cloud intelligence is not connected yet")
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
        // Deliberately do not fabricate an AI response. The authenticated cloud
        // reasoning endpoint must be configured before conversational requests are enabled.
        prompt = ""
    }
}
