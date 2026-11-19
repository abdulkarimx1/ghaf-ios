import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit
import UIKit

/// More › Notifications: what Ghaf can tell you, each one optional, and why iOS asks for permission.
struct GhafNotificationSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query private var subscriptions: [GhafSubscription]
    let settings: GhafSettings

    @AppStorage(GhafEventNotifications.transactionReviewKey) private var transactionReview = true
    @AppStorage(GhafEventNotifications.detectedSubscriptionKey) private var detectedSubscription = true
    @AppStorage(GhafEventNotifications.budgetThresholdKey) private var budgetThreshold = true
    @AppStorage(GhafEventNotifications.subscriptionDueKey) private var subscriptionDue = true
    @AppStorage(GhafDigestNotifications.morningKey) private var morning = false
    @AppStorage(GhafDigestNotifications.eveningKey) private var evening = false
    @AppStorage(GhafDigestNotifications.weeklyKey) private var weekly = false
    @AppStorage(GhafWidgetSync.liveActivityKey) private var liveActivity = true
    @State private var denied = false
    @State private var widgetStatusVersion = 0
    @State private var placedWidgetsReport = "Checking placed widgets…"
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
                            .padding(GhafMetrics.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.over.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.ghafPress)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(ar ? "تنبيهات الأحداث" : "Event alerts")
                        .font(GhafTypography.heading(18, languageCode: lang)).foregroundStyle(theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
                    row(ar ? "عملية تحتاج مراجعتك" : "Transaction needs review",
                        ar ? "عندما تُحفظ عملية آلية لتراجع تفاصيلها." : "When an automatic transaction is saved for review.",
                        icon: "tray.full.fill", isOn: $transactionReview)
                    Divider().overlay(theme.outline)
                    row(ar ? "اشتراك متكرر مرصود" : "Recurring charge detected",
                        ar ? "عندما تبدو عملية بنكية اشتراكاً متكرراً." : "When a bank charge looks like a recurring subscription.",
                        icon: "repeat", isOn: $detectedSubscription)
                    Divider().overlay(theme.outline)
                    row(ar ? "حدود الميزانية" : "Budget thresholds",
                        ar ? "عند بلوغ ٨٠٪ و١٠٠٪ من ميزانية الفئة هذا الشهر." : "When a category reaches 80% and 100% of its monthly budget.",
                        icon: "chart.bar.fill", isOn: $budgetThreshold)
                    Divider().overlay(theme.outline)
                    row(ar ? "موعد دفع اشتراك" : "Subscription due date",
                        ar ? "تذكير قبل الموعد. لا يؤكد الدفع ولا يسجّله." : "A reminder before the date; it doesn't confirm or record payment.",
                        icon: "calendar", isOn: $subscriptionDue)
                    Divider().overlay(theme.outline)
                    row(ar ? "النشاط المباشر للعمليات" : "Live Activity for purchases",
                        ar ? "آخر عملية على شاشة القفل وفي الجزيرة الديناميكية لمدة ٥ دقائق" : "The latest purchase on the Lock Screen and Dynamic Island for 5 minutes",
                        icon: "bolt.badge.clock.fill", isOn: $liveActivity)
                }
                .padding(.horizontal, 16)
                .ghafCard(theme: theme)

                VStack(alignment: .leading, spacing: 0) {
                    Text(ar ? "ملخصات مجدولة" : "Scheduled summaries")
                        .font(GhafTypography.heading(18, languageCode: lang)).foregroundStyle(theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
                    row(ar ? "صباحاً · ٨:٠٠" : "Morning · 8:00",
                        ar ? "مصروفات أمس" : "Yesterday's spending", icon: "sunrise.fill", isOn: $morning)
                    Divider().overlay(theme.outline)
                    row(ar ? "مساءً · ٩:٠٠" : "Evening · 9:00 pm",
                        ar ? "ملخص مصروفات اليوم" : "Today's spending", icon: "moon.stars.fill", isOn: $evening)
                    Divider().overlay(theme.outline)
                    row(ar ? "أسبوعياً · أول يوم في أسبوعك" : "Weekly · first day of your week",
                        ar ? "مصروفات الأسبوع الماضي ومقارنتها" : "Last week's spending and comparison",
                        icon: "calendar", isOn: $weekly)
                }
                .padding(.horizontal, 16).ghafCard(theme: theme)

                widgetStatus

                Text(ar ? "لا يسجّل تذكير الاشتراك عملية دفع ولا يغيّر الرصيد. ملخصات الصباح والمساء والأسبوع اختيارية ومتوقفة افتراضياً."
                        : "A subscription reminder doesn't record a payment or change a balance. Morning, evening and weekly summaries are optional and off by default.")
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
            }
            .ghafScreenPadding().padding(.vertical, 12)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .ghafPageTitle(ar ? "الإشعارات" : "Notifications", languageCode: settings.languageCode, theme: theme)
        .task { GhafEventNotifications.configure(); await refreshPermission() }
        .sheet(item: $proFeature) { GhafProSheet(settings: settings, feature: ($0.en, $0.ar)).ghafDirection(settings.languageCode) }
        .onChange(of: liveActivity) { _, on in if on { proFeature = ProFeature(en: "Live Activities", ar: "النشاط المباشر") } }
        .onChange(of: [transactionReview, detectedSubscription, budgetThreshold, subscriptionDue, morning, evening, weekly]) { oldValues, values in
            Task {
                if zip(oldValues, values).contains(where: { !$0.0 && $0.1 }) {
                    _ = await GhafDigestNotifications.requestPermission()
                }
                await refreshPermission()
                if oldValues[3] != values[3] {
                    if values[3] {
                        subscriptions.filter(\.isActive).forEach { GhafSubscriptionReminderService.schedule($0, language: lang) }
                    } else {
                        await GhafSubscriptionReminderService.cancelAll()
                    }
                }
                GhafDigestNotifications.reschedule(context: modelContext)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshPermission() } } }
    }

    /// Whether the widgets can read Ghaf's data on this install. Sideload tools sometimes drop the App Group,
    /// and then the widgets can only say "Open Ghaf"; this line makes that visible instead of a silent blank.
    private var widgetStatus: some View {
        _ = widgetStatusVersion
        let channels = GhafWidgetSync.lastChannels ?? (GhafWidgetSnapshot.hasSharedContainer, GhafWidgetKeychain.accessGroup != nil)
        let heartbeat = GhafWidgetSnapshot.lastHeartbeat
        let snapshot = GhafWidgetSnapshot.loadWithSource().snapshot
        let dateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: ar ? "ar-AE" : "en-AE"))
        return VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ar ? "حالة الودجت" : "Widget status").font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                    GhafStatusChip(kind: (!channels.group && !channels.keychain) ? .notSetUp : (snapshot == nil ? .waiting : .working),
                                   title: (!channels.group && !channels.keychain) ? (ar ? "غير مُعد" : "Not set up") : (snapshot == nil ? (ar ? "بانتظار لقطة" : "Waiting for snapshot") : (ar ? "الودجت متصل" : "Widget connected")),
                                   theme: theme, languageCode: lang)
                    Text((ar ? "آخر حفظ: " : "Last snapshot: ") + (snapshot?.updated.formatted(dateStyle) ?? (ar ? "لا يوجد" : "None")) + " · " + (ar ? "مجموعة التطبيق " : "App Group ") + (channels.group ? "✓" : "✗") + " · " + (ar ? "سلسلة المفاتيح " : "Keychain ") + (channels.keychain ? "✓" : "✗"))
                    Text((ar ? "مجموعة التطبيق: " : "App Group: ") + GhafWidgetSnapshot.groupID + " (" + (ar ? (GhafWidgetSnapshot.hasSharedContainer ? "متاحة" : "غير متاحة") : (GhafWidgetSnapshot.hasSharedContainer ? "reachable" : "unavailable")) + ")")
                    Text((ar ? "مجموعة سلسلة المفاتيح: " : "Keychain group: ") + (GhafWidgetKeychain.accessGroup ?? (ar ? "غير متاحة" : "unavailable")))
                    Text(heartbeat.map {
                        (ar ? "آخر تشغيل للودجت: " : "Widget heartbeat: ") + "\($0.kind), \($0.family), " + (ar ? ($0.loadedFrom == "group" ? "مجموعة التطبيق" : $0.loadedFrom == "keychain" ? "سلسلة المفاتيح" : "بلا بيانات") : $0.loadedFrom) + " · \($0.date.formatted(dateStyle))"
                    } ?? (ar ? "لم تشغّل الودجت بعد" : "The widget hasn't run yet"))
                    Text(placedWidgetsReport)
                    Text(diagnosticReport)
                        .textSelection(.enabled)
                    if (!channels.group && !channels.keychain) || heartbeat?.loadedFrom == "none" {
                        Text(ar ? "لا تستطيع الودجت الوصول إلى بيانات غاف — لم تجد لقطة مشتركة قابلة للقراءة. تحقق من مجموعات المشاركة في أداة التوقيع.\n" + profileSummary
                             : "The widget can't reach Ghaf's data — it found no readable shared snapshot. Check the sharing groups in the signing tool.\n" + profileSummary)
                    }
                }
                .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
            } icon: {
                Image(systemName: channels.group || channels.keychain ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(channels.group || channels.keychain ? theme.comfortable : theme.over)
            }
            Button(ar ? "تحديث الودجت" : "Refresh widgets", systemImage: "arrow.clockwise") {
                GhafWidgetSync.refresh(context: modelContext)
                widgetStatusVersion += 1
            }
            .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
            Button(ar ? "نسخ التقرير" : "Copy report", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = diagnosticReport + "\n" + placedWidgetsReport
            }
            .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme)
        .task { refreshPlacedWidgets() }
    }

    private var diagnosticReport: String {
        let app = Bundle.main
        let appID = app.bundleIdentifier ?? "unknown"
        let appProfile = GhafSigningProfile.current
        let extensionURL = app.builtInPlugInsURL?.appendingPathComponent("GhafWidgets.appex")
        let widget = extensionURL.flatMap(Bundle.init(url:))
        let widgetID = widget?.bundleIdentifier
        let widgetProfile = widget.map(GhafSigningProfile.load(from:)) ?? GhafSigningProfile()
        let sharedGroups = Set(appProfile.appGroups).intersection(widgetProfile.appGroups).sorted()
        let sharedKeychains = GhafSigningProfile.sharedKeychainGroups(app: appProfile.keychainGroups, widget: widgetProfile.keychainGroups)
        let dateStyle = Date.FormatStyle(date: .numeric, time: .shortened).locale(Locale(identifier: ar ? "ar-AE" : "en-AE"))
        func list(_ values: [String]) -> String { values.isEmpty ? (ar ? "لا يوجد" : "none") : values.sorted().joined(separator: ", ") }
        func profile(_ value: GhafSigningProfile) -> String {
            "\(ar ? "الاسم" : "name")=\(value.name ?? "none"); \(ar ? "الفريق" : "team")=\(value.teamID ?? "none"); \(ar ? "انتهاء الصلاحية" : "expires")=\(value.expiry?.formatted(dateStyle) ?? "none"); \(ar ? "مجموعات التطبيق" : "app groups")=[\(list(value.appGroups))]; \(ar ? "مجموعات سلسلة المفاتيح" : "keychain groups")=[\(list(value.keychainGroups))]"
        }
        var lines = ["\(ar ? "معرّف التطبيق" : "App bundle ID"): \(appID)",
                     "\(ar ? "ملف توقيع التطبيق" : "App signing profile"): \(appProfile.exists ? profile(appProfile) : (ar ? "لا يوجد ملف توقيع مضمن" : "no embedded signing profile"))",
                     "\(ar ? "معرّف الودجت" : "Widget bundle ID"): \(widgetID ?? (ar ? "ملف GhafWidgets.appex مفقود" : "missing GhafWidgets.appex"))",
                     "\(ar ? "ملف توقيع الودجت" : "Widget signing profile"): \(widgetProfile.exists ? profile(widgetProfile) : (ar ? "لا يوجد ملف توقيع مضمن" : "no embedded signing profile"))",
                     "\(ar ? "مجموعات التطبيق المشتركة" : "Shared App Groups"): [\(list(Array(sharedGroups)))]",
                     "\(ar ? "مجموعات سلسلة المفاتيح المشتركة" : "Shared keychain groups"): [\(list(sharedKeychains))]"]
        if widget == nil { lines.append(ar ? "تعذر العثور على امتداد الودجت داخل التطبيق" : "The widget extension is missing from the app") }
        let widgetIDMatches = widgetID?.hasPrefix(appID + ".") == true
        lines.append("\(ar ? "يبدأ معرّف الودجت بمعرّف التطبيق" : "Widget ID starts with app ID"): \(widgetIDMatches ? (ar ? "نعم" : "yes") : (ar ? "لا" : "no"))")
        if widgetID != nil && !widgetIDMatches { lines.append(ar ? "معرّف الودجت لا يبدأ بمعرّف التطبيق" : "The widget's ID doesn't start with the app's ID") }
        if appProfile.teamID != nil, widgetProfile.teamID != nil, appProfile.teamID != widgetProfile.teamID {
            lines.append(ar ? "وُقّع الودجت بفريق مختلف" : "The widget was signed by a different team")
        }
        if widget != nil && !widgetProfile.exists {
#if targetEnvironment(simulator)
            lines.append(ar ? "لا يوجد ملف توقيع مضمن في إصدار المحاكي" : "No embedded signing profile in this simulator build")
#else
            lines.append(ar ? "لا يوجد ملف توقيع للودجت — لن يشغله iOS" : "The widget has no signing profile — iOS won't run it")
#endif
        }
        if widget != nil && sharedGroups.isEmpty { lines.append(ar ? "لا توجد مجموعة تطبيق مشتركة بين التطبيق والودجت" : "App and widget share no App Group") }
        return lines.joined(separator: "\n")
    }

    private func refreshPlacedWidgets() {
        let kinds = ["GhafBalance", "GhafToday", "GhafRecent", "GhafSpending", "GhafBudget", "GhafCategories", "GhafBills", "GhafTrends"]
        WidgetCenter.shared.getCurrentConfigurations { result in
            Task { @MainActor in
                switch result {
                case .success(let configurations):
                    let counts = Dictionary(grouping: configurations.map { $0.kind }, by: { $0 }).mapValues { $0.count }
                    placedWidgetsReport = kinds.map { "\($0): \(counts[$0, default: 0])" }.joined(separator: "\n")
                case .failure(let error):
                    placedWidgetsReport = (ar ? "تعذر قراءة الأدوات الموضوعة: " : "Could not read placed widgets: ") + error.localizedDescription
                }
            }
        }
    }

    /// What the installer's profile grants, so a broken install can be diagnosed from a screenshot.
    private var profileSummary: String {
        let profile = GhafSigningProfile.current
        let groups = profile.appGroups.isEmpty ? "none" : profile.appGroups.joined(separator: ", ")
        let keychain = profile.keychainGroups.isEmpty ? "none" : profile.keychainGroups.joined(separator: ", ")
        return ar ? "الملف: \(profile.name ?? "غير متاح") · مجموعات التطبيق: \(groups) · سلسلة المفاتيح: \(keychain)"
                    : "Profile: \(profile.name ?? "none") · App Groups: \(groups) · Keychain: \(keychain)"
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
