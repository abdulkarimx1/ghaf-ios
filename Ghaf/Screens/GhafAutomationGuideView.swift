import SwiftUI
import AppIntents

struct GhafAutomationGuideView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private let bankApps = ["Mashreq", "Mbank", "iVESTOR", "ruya"]
    @AppStorage(GhafAutomationStatus.lastRunKey) private var automationLastRun: Double = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                shortcutReadyCard
                supportedBanksCard

                instructionCard(
                    number: "01",
                    title: localized("Install Ghaf's automation", "ثبّت أتمتة غاف"),
                    detail: localized("Tap Install automation above and choose Shortcuts, then Add Shortcut. It comes with notification automations for Messages, Mashreq and Mbank that pass each alert to Ghaf.", "اضغط «تثبيت الأتمتة» في الأعلى واختر الاختصارات ثم «إضافة اختصار». يأتي مع أتمتة إشعارات للرسائل وMashreq وMbank تمرّر كل تنبيه إلى غاف.")
                )

                instructionCard(
                    number: "02",
                    title: localized("Turn on Run Immediately", "فعّل «التشغيل فوراً»"),
                    detail: localized("In Shortcuts, open Automation, tap each Ghaf automation and choose Run Immediately, so no tap is needed per transaction. iOS asks for this approval once; Ghaf cannot do it for you.", "في الاختصارات افتح «الأتمتة»، واضغط على كل أتمتة لغاف واختر «التشغيل فوراً» حتى لا تحتاج للضغط مع كل عملية. يطلب iOS هذه الموافقة مرة واحدة ولا يستطيع غاف تفعيلها عنك.")
                )

                instructionCard(
                    number: "03",
                    title: localized("Add your other banks", "أضف بنوكك الأخرى"),
                    detail: localized("iOS does not let apps see which apps you have installed, so other banks are added by hand: new Personal Automation, “When I receive a notification”, pick the bank app, add Ghaf's “أضف عملية من رسالة بنكية” and set its text to Shortcut Input.", "لا يسمح iOS للتطبيقات بمعرفة التطبيقات المثبتة، لذا تُضاف البنوك الأخرى يدوياً: أتمتة شخصية جديدة، «عند استلام إشعار»، اختر تطبيق البنك، أضف إجراء غاف «أضف عملية من رسالة بنكية» واربط النص بـ Shortcut Input.")
                )

                instructionCard(
                    number: "04",
                    title: localized("Optional: Apple Pay purchases", "اختياري: مشتريات Apple Pay"),
                    detail: localized("Create a “Transaction” (Wallet) automation, add Ghaf's “Add Apple Pay purchase” and map Amount, Merchant and Card. When the bank's message for the same purchase arrives, Ghaf keeps one record instead of two.", "أنشئ أتمتة «معاملة» من المحفظة، وأضف إجراء غاف «أضف عملية Apple Pay» واربط المبلغ والتاجر والبطاقة. عندما تصل رسالة البنك لنفس العملية، يحتفظ غاف بسجل واحد بدلاً من اثنين.")
                )

                privacyCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(localized("Bank automation", "أتمتة البنك"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: settings.languageCode))
        .environment(\.layoutDirection, settings.languageCode == "ar" ? .rightToLeft : .leftToRight)
    }

    private func localized(_ english: String, _ arabic: String) -> String {
        settings.languageCode == "ar" ? arabic : english
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(settings.languageCode == "ar" ? "اربط بنكك بغاف" : "Let Ghaf capture your spending.")
                .font(GhafTypography.display(30, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(settings.languageCode == "ar"
                 ? "الإجراء موجود داخل غاف. بعد إعداد أتمتة الإشعارات لكل تطبيق بنك مرة واحدة، يمكن معالجة تنبيهات العمليات المدعومة دون إدخال كل عملية يدوياً."
                 : "The Ghaf action is included. After a one-time notification automation setup for each bank app, supported transaction alerts can be processed without manually entering each transaction.")
                .font(GhafTypography.body(14, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var shortcutReadyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(theme.credit)
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("Ghaf action ready", "إجراء غاف جاهز"))
                        .font(GhafTypography.heading(18, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)
                    Text(localized("Available in Apple Shortcuts after Ghaf is installed", "متاح في تطبيق اختصارات Apple بعد تثبيت غاف"))
                        .font(GhafTypography.body(12, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            if automationLastRun > 0 {
                Label(localized("Working · last message ", "تعمل · آخر رسالة ")
                      + Date(timeIntervalSince1970: automationLastRun).formatted(.relative(presentation: .named)
                        .locale(Locale(identifier: settings.languageCode))),
                      systemImage: "checkmark.seal.fill")
                    .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .semibold))
                    .foregroundStyle(theme.credit)
            }
            if let automation = Bundle.main.url(forResource: "Ghaf Bank Automation", withExtension: "shortcut") {
                ShareLink(item: automation) {
                    Label(localized("Install automation", "تثبيت الأتمتة"), systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .ghafProminentButton(theme: theme, languageCode: settings.languageCode)
            }

            Text(localized("Signed shortcut with Ghaf's action and bank notification triggers. Choose Shortcuts in the share sheet.", "اختصار موقّع يحتوي إجراء غاف ومحفّزات إشعارات البنك. اختر «الاختصارات» من قائمة المشاركة."))
                .font(GhafTypography.body(12, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)

            ShortcutsLink(action: {})
                .shortcutsLinkStyle(.automatic)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.outline, lineWidth: 1))
    }

    private var supportedBanksCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(localized("Parser examples", "أمثلة على البنوك المدعومة"))
                .font(GhafTypography.heading(17, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)

            HStack(spacing: 8) {
                ForEach(bankApps, id: \.self) { app in
                    Text(app)
                        .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(theme.background, in: Capsule())
                }
            }

            Text(localized("These banks have parser rules in Ghaf. Only set up automations for apps or message senders that actually deliver alerts to your iPhone.", "تتضمن غاف قواعد لتحليل رسائل هذه البنوك. أنشئ الأتمتة فقط للتطبيقات أو مُرسلي الرسائل الذين يرسلون إشعارات فعلية إلى iPhone."))
                .font(GhafTypography.body(12, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(18)
        .ghafCard(theme: theme, radius: 20)
    }

    private func instructionCard(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(GhafTypography.number(13, weight: .bold))
                .foregroundStyle(theme.accentContrast)
                .frame(width: 34, height: 34)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(GhafTypography.heading(16, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)
                Text(detail)
                    .font(GhafTypography.body(13, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme, radius: 19)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localized("What iOS allows", "ما يسمح به iOS"), systemImage: "lock.shield")
                .font(GhafTypography.heading(16, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)

            Text(localized("iOS does not allow Ghaf to create personal automations without your approval. You choose the notification trigger and bank app in Shortcuts, then connect Shortcut Input to Ghaf's “نص الرسالة” field. The notification text available to Shortcuts depends on what the bank includes and what iOS exposes.", "لا يسمح iOS لغاف بإنشاء أتمتة شخصية دون موافقتك. اختر محفّز الإشعارات وتطبيق البنك في الاختصارات، ثم اربط Shortcut Input بحقل «نص الرسالة» في غاف. يعتمد النص المتاح على محتوى الإشعار الذي يرسله البنك وما يتيحه iOS."))
                .font(GhafTypography.body(12, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(18)
        .background(theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}
