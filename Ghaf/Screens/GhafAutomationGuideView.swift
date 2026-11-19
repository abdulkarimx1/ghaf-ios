import SwiftUI
import AppIntents
import UIKit

struct GhafAutomationGuideView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    let settings: GhafSettings
    @AppStorage(GhafAutomationStatus.messageRunKey) private var messageLastRun: Double = 0
    @AppStorage(GhafAutomationStatus.walletRunKey) private var walletLastRun: Double = 0
    @State private var step = 0
    @State private var tick = false

    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode,
                          systemIsDark: systemColorScheme == .dark)
    }
    private var ar: Bool { settings.languageCode == "ar" }
    private var connected: Bool { messageLastRun > 0 || walletLastRun > 0 }
    private var title: [String] { ar
        ? ["كيف يعمل", "أنشئ أتمتة الرسائل", "أضف إجراء غاف", "مشتريات Apple Pay (اختياري)", "تحقق من الاتصال"]
        : ["Why it works", "Create a message automation", "Add Ghaf’s action", "Apple Pay purchases (optional)", "Verify the connection"] }
    private var detail: [String] { ar
        ? ["يمرر iOS الرسائل التي تختارها إلى غاف. لا يستطيع غاف قراءة إشعارات تطبيقات أخرى. يبقى نص الرسالة على جهازك.",
           "افتح الاختصارات ← الأتمتة ← جديد ← رسالة. اختر المرسل أو احتواء النص وحدد بنكك.",
           "أضف إجراء «Log bank message»، مرر إليه نص الرسالة، واختر «Run Immediately».",
           "في المحفظة ← أتمتة المعاملات، أضف «Add Apple Pay purchase» إذا أردت تسجيل مشتريات Apple Pay.",
           "بانتظار أول رسالة بنك… في الاختصارات، شغّل إجراء غاف مع نص الرسالة GHAF TEST. يؤكد الاتصال ولا ينشئ عملية."]
        : ["iOS passes only the messages you choose to Ghaf. Ghaf cannot read other apps’ notifications. Message text stays on this device.",
           "Open Shortcuts → Automation → New → Message. Choose sender or contains text, then select your bank.",
           "Add the ‘Log bank message’ Ghaf action, pass in the message text, and set ‘Run Immediately’.",
           "In Wallet → Transaction automations, add ‘Add Apple Pay purchase’ if you want Apple Pay purchases captured.",
           "Waiting for your first bank message… In Shortcuts, run Ghaf’s action with message text GHAF TEST. This verifies the connection without creating a transaction."] }

    var body: some View {
        VStack(spacing: 16) {
            Text(title[step]).font(GhafTypography.display(28, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText).multilineTextAlignment(.center)
            Image(systemName: ["lock.shield", "message.badge", "bolt.circle", "applepay", connected ? "checkmark.circle.fill" : "hourglass"] [step])
                .font(.system(size: 54, weight: .light)).foregroundStyle(connected && step == 4 ? theme.credit : theme.accent)
                .frame(height: 90)
            Text(detail[step]).font(GhafTypography.body(16, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if step == 4 {
                GhafStatusChip(kind: connected ? .working : .waiting,
                               title: connected ? (ar ? "غاف متصل" : "Ghaf is connected") : (ar ? "بانتظار أول تشغيل" : "Waiting for first run"),
                               theme: theme, languageCode: settings.languageCode)
                Button(ar ? "اختبر الآن في الاختصارات" : "Test now in Shortcuts") {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                }
                .ghafGlassButton(theme: theme, languageCode: settings.languageCode)
            }
            if step == 1 {
                Button(ar ? "فتح الاختصارات" : "Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                }
                .ghafGlassButton(theme: theme, languageCode: settings.languageCode)
            }
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                ForEach(0..<title.count, id: \.self) { i in
                    Capsule().fill(i == step ? theme.accent : theme.secondaryText.opacity(0.25))
                        .frame(width: i == step ? 22 : 7, height: 7)
                }
            }.accessibilityLabel(ar ? "الخطوة \(step + 1) من 5" : "Step \(step + 1) of 5")
            HStack(spacing: 12) {
                Button(ar ? "رجوع" : "Back") { step = max(0, step - 1) }
                    .frame(maxWidth: .infinity).frame(height: 56).ghafGlassButton(theme: theme, languageCode: settings.languageCode)
                    .disabled(step == 0)
                Button(step == 4 ? (ar ? "تم" : "Done") : (ar ? "التالي" : "Next")) {
                    step = min(title.count - 1, step + 1)
                }
                .frame(maxWidth: .infinity).frame(height: 56).ghafProminentButton(theme: theme, languageCode: settings.languageCode)
            }
        }
        .ghafScreenPadding().padding(.vertical, 24).frame(maxWidth: 560, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .ghafBackground(theme: theme)
        .navigationTitle(ar ? "أتمتة البنك" : "Bank automation")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: settings.languageCode))
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        .onChange(of: scenePhase) { _, phase in if phase == .active { tick.toggle() } }
        .task(id: step) {
            guard step == 4 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                tick.toggle()
            }
        }
        .onChange(of: tick) { _, _ in
            messageLastRun = UserDefaults.standard.double(forKey: GhafAutomationStatus.messageRunKey)
            walletLastRun = UserDefaults.standard.double(forKey: GhafAutomationStatus.walletRunKey)
        }
    }
}
