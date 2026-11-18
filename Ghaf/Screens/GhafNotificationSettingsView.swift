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
    @AppStorage(GhafWidgetSync.liveActivityKey) private var liveActivity = true
    @State private var denied = false
    /// The Pro feature just tapped, if any; drives the Ghaf Pro sheet.
    @State private var proFeature: ProFeature?

    private struct ProFeature: Identifiable {
        let en: String, ar: String
        var id: String { en }
    }

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
                    row(ar ? "النشاط المباشر للعمليات" : "Live Activity for purchases",
                        ar ? "آخر عملية على شاشة القفل وفي Dynamic Island لمدة ١٥ دقيقة" : "The latest purchase on the Lock Screen and Dynamic Island for 15 minutes",
                        icon: "bolt.badge.clock.fill", isOn: $liveActivity)
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

                widgetStatus

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
        .sheet(item: $proFeature) { GhafProSheet(settings: settings, feature: ($0.en, $0.ar)) }
        .onChange(of: liveActivity) { _, on in if on { proFeature = ProFeature(en: "Live Activities", ar: "النشاط المباشر") } }
        .onChange(of: [autoTransaction, morning, evening, weekly]) { _, values in
            Task {
                if values.contains(true) { _ = await GhafDigestNotifications.requestPermission() }
                await refreshPermission()
                GhafDigestNotifications.reschedule(context: modelContext)
            }
        }
    }

    /// Whether the widgets can read Ghaf's data on this install. Sideload tools sometimes drop the App Group,
    /// and then the widgets can only say "Open Ghaf"; this line makes that visible instead of a silent blank.
    private var widgetStatus: some View {
        let channels = GhafWidgetSync.lastChannels ?? (GhafWidgetSnapshot.hasSharedContainer, GhafWidgetKeychain.accessGroup != nil)
        let ok = channels.group || channels.keychain
        let detail: String = if channels.group {
            ar ? "متصلة عبر مجموعة التطبيق (\(GhafWidgetSnapshot.groupID))" : "Connected through the App Group (\(GhafWidgetSnapshot.groupID))"
        } else if channels.keychain {
            ar ? "متصلة عبر سلسلة المفاتيح، لأن أداة التثبيت أزالت مجموعة التطبيق" : "Connected through the keychain; your install tool removed the App Group"
        } else {
            (ar ? "غير متصلة: توقيع التثبيت لا يمنح غاف مجموعة تطبيق، فلا تستطيع الودجت قراءة بياناتك. فعّل App Groups في أداة التثبيت ثم أعد التثبيت."
                : "Not connected: this install's signature gives Ghaf no App Group, so widgets can't read its data. Turn on App Groups in your install tool and reinstall.")
            + "\n" + profileSummary
        }
        return Button { proFeature = ProFeature(en: "Widgets", ar: "الودجت") } label: { Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(ar ? "الودجت" : "Widgets").font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                Text(detail).font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
            }
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? theme.comfortable : theme.over)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme)
        }
        .buttonStyle(.ghafPress)
    }

    /// What the installer's profile grants, so a broken install can be diagnosed from a screenshot.
    private var profileSummary: String {
        let profile = GhafSigningProfile.current
        let groups = profile.appGroups.isEmpty ? "none" : profile.appGroups.joined(separator: ", ")
        let keychain = profile.keychainGroups.isEmpty ? "none" : profile.keychainGroups.joined(separator: ", ")
        return "Profile: \(profile.name ?? "none") · App Groups: \(groups) · Keychain: \(keychain)"
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
