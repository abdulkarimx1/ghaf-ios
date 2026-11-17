import SwiftUI
import SwiftData
import UserNotifications

/// More › Notifications: what Ghaf can tell you, each one optional, and why iOS asks for permission.
struct GhafNotificationSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    let settings: GhafSettings

    @AppStorage(GhafDigestNotifications.autoTransactionKey) private var autoTransaction = true
    @AppStorage(GhafDigestNotifications.morningKey) private var morning = false
    @AppStorage(GhafDigestNotifications.eveningKey) private var evening = false
    @AppStorage(GhafDigestNotifications.weeklyKey) private var weekly = false
    @State private var denied = false

    private var ar: Bool { settings.languageCode == "ar" }
    private var lang: String { settings.languageCode }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(ar ? "اختر ما يهمك فقط. كل الأرقام من سجلك، ولا شيء يُرسل خارج جهازك."
                        : "Pick only what helps. Every number comes from your records, and nothing leaves your iPhone.")
                    .font(GhafTypography.body(14, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if denied {
                    Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                        Label(ar ? "الإشعارات متوقفة لغاف. افتح الإعدادات للسماح بها." : "Notifications are off for Ghaf. Open Settings to allow them.",
                              systemImage: "bell.slash.fill")
                            .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.over)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.over.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.ghafPress)
                }

                VStack(spacing: 0) {
                    row(ar ? "عند إضافة عملية تلقائياً" : "When a transaction is added",
                        ar ? "المبلغ والمكان ورصيد الحساب المحدّث" : "Amount, place and the account's updated balance",
                        icon: "bolt.fill", isOn: $autoTransaction)
                    Divider().overlay(theme.outline)
                    row(ar ? "صباحاً · ٨:٠٠" : "Morning · 8:00",
                        ar ? "كم صرفت أمس" : "What you spent yesterday", icon: "sunrise.fill", isOn: $morning)
                    Divider().overlay(theme.outline)
                    row(ar ? "مساءً · ٩:٠٠" : "Evening · 9:00 pm",
                        ar ? "ملخص صرف اليوم" : "Today's spending in one line", icon: "moon.stars.fill", isOn: $evening)
                    Divider().overlay(theme.outline)
                    row(ar ? "أسبوعياً · أول يوم في أسبوعك" : "Weekly · first day of your week",
                        ar ? "صرف الأسبوع الماضي مقارنة بالذي قبله" : "Last week's spending against the week before",
                        icon: "calendar", isOn: $weekly)
                }
                .padding(.horizontal, 16)
                .ghafCard(theme: theme)

                Text(ar ? "iOS يطلب إذنك مرة واحدة لعرض الإشعارات. التذكيرات لا تسجّل أي عملية ولا تغيّر رصيدك. إشعار «تشغيل الأتمتة» من iOS نفسه؛ أوقفه من الاختصارات › الأتمتة › «الإشعار عند التشغيل»."
                        : "iOS asks once before Ghaf can show notifications. Summaries never record transactions or change balances. The \"automation ran\" banner comes from iOS: turn it off in Shortcuts › Automation › Notify When Run.")
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, GhafMetrics.gutter).padding(.vertical, 12)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .navigationTitle(ar ? "الإشعارات" : "Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshPermission() }
        .onChange(of: [autoTransaction, morning, evening, weekly]) { _, values in
            Task {
                if values.contains(true) { _ = await GhafDigestNotifications.requestPermission() }
                await refreshPermission()
                GhafDigestNotifications.reschedule(context: modelContext)
            }
        }
    }

    private func refreshPermission() async {
        denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    private func row(_ title: String, _ detail: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 34, height: 34)
                    .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                    Text(detail).font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                }
            }
        }
        .tint(theme.accent)
        .frame(minHeight: 64)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }
}
