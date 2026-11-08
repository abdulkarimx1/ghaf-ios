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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                shortcutReadyCard
                supportedBanksCard

                instructionCard(
                    number: "01",
                    title: localized("Choose the trigger", "اختر مُحفّز التشغيل"),
                    detail: localized("Open Apple Shortcuts → Automation → New Personal Automation → Message. Set the sender filter to the bank's SMS sender, then choose Run Immediately if offered. This trigger only sees SMS delivered to Messages; it does not read notifications from a bank app.", "افتح تطبيق الاختصارات، ثم الأتمتة، وأنشئ أتمتة شخصية باستخدام محفّز الرسائل. اختر مُرسل رسائل البنك النصية. تعمل هذه الطريقة عندما يرسل البنك تفاصيل العملية عبر SMS إلى تطبيق الرسائل.")
                )

                instructionCard(
                    number: "02",
                    title: localized("Add Ghaf's ready-made action", "أضف إجراء غاف الجاهز"),
                    detail: localized("Tap Add Action and search for Ghaf. Choose Log Bank Message. You do not need to build a separate shortcut or write any logic; Ghaf supplies this action automatically.", "اضغط على إضافة إجراء وابحث عن غاف، ثم اختر تسجيل رسالة بنكية. لا تحتاج إلى إنشاء اختصار منفصل أو كتابة أي منطق؛ يوفر غاف هذا الإجراء تلقائياً.")
                )

                instructionCard(
                    number: "03",
                    title: localized("Connect the message", "اربط نص الرسالة"),
                    detail: localized("In the automation's action list, add Ghaf → Log Bank Message. Set Message Text to the incoming Message variable. Leave Notification Title empty for SMS. Set Sender / App Name to the bank name (for example, Mashreq) if the trigger does not expose a sender value. Ghaf combines the title and body when both are supplied by a supported shortcut source.", "عند استخدام مُحفّز SMS، اربط Message Text بمتغير Message واترك Notification Title فارغاً. إذا كان إصدار iOS لديك يوفّر مُحفّزاً لإشعارات البنك مع عنوان ونص منفصلين، اربط العنوان بحقل Notification Title والنص بحقل Message Text. أدخل اسم البنك كنص عادي في Sender / App Name إذا لم يوفّر المُحفّز اسم التطبيق. إذا لم يوفّر تطبيق الاختصارات مُحفّز الإشعارات أو محتواها، فلن يستطيع غاف قراءة التنبيه مباشرة؛ استخدم مُحفّز SMS عند توفره.")
                )

                instructionCard(
                    number: "04",
                    title: localized("Save and test", "احفظ الأتمتة واختبرها"),
                    detail: localized("Choose Run Immediately where iOS offers it, save the automation, then test with a real bank transaction. Confirm the amount and merchant in Ghaf. Unknown merchants are placed in Needs Review.", "اختر التشغيل فوراً إذا أتاح iOS هذا الخيار، ثم احفظ الأتمتة واختبرها بعملية بنكية حقيقية. تحقق من المبلغ واسم المتجر في غاف. تُضاف المتاجر غير المعروفة إلى قائمة تحتاج إلى مراجعة.")
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
                 ? "الإجراء موجود داخل غاف. بعد إعداد أتمتة رسائل SMS مرة واحدة، يمكن معالجة الرسائل البنكية المدعومة دون إدخال كل عملية يدوياً."
                 : "Ghaf provides a ready-made action for Shortcuts. For banks that send transaction SMS messages, one personal automation per bank can pass the message into Ghaf. Cash transactions still need to be entered manually.")
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

            Text(localized("Use the Ghaf action inside the personal automation you create in Shortcuts.", "افتح إجراء غاف الجاهز من هذه الصفحة في تطبيق الاختصارات."))
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

            Text(localized("iOS does not expose a general trigger for another app's incoming notifications to third-party apps or Shortcuts. Ghaf therefore cannot reliably read Mashreq or other bank-app push notifications in the background. The supported route in this version is the Messages automation for transaction SMS. If a bank sends no SMS, that bank cannot be automatically logged through this method. Apple Wallet transaction triggers are separate and depend on the card and issuer.", "لا يسمح iOS للتطبيق بإنشاء أتمتة شخصية نيابةً عنك دون موافقتك. يوفر غاف اختصاراً جاهزاً، لذلك لن تحتاج إلى بناء الإجراء بنفسك؛ تقتصر الخطوة اليدوية على اختيار المُحفّز والموافقة عليه داخل تطبيق الاختصارات. قد تتطلب بعض المُحفّزات تأكيداً، كما قد يخفي البنك تفاصيل العمليات من إشعاراته."))
                .font(GhafTypography.body(12, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(18)
        .background(theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}
