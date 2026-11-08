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
                    title: localized("Choose the notification trigger", "اختر محفّز الإشعارات"),
                    detail: localized("In Apple Shortcuts, open Automation, create a Personal Automation, and choose “When I receive a notification”. Select the bank app (for example Mashreq or Mbank). If you also want bank SMS alerts, create a separate automation for Messages.", "افتح تطبيق الاختصارات من Apple، ثم الأتمتة، وأنشئ أتمتة شخصية واختر «عند استلام إشعار». حدّد تطبيق البنك مثل Mashreq أو Mbank. وإذا أردت التقاط رسائل البنك النصية أيضاً، أنشئ أتمتة منفصلة لتطبيق الرسائل.")
                )

                instructionCard(
                    number: "02",
                    title: localized("Add Ghaf's action", "أضف إجراء غاف"),
                    detail: localized("Add an action, search for Ghaf, then choose “أضف عملية من رسالة بنكية”. This is Ghaf's own App Shortcut action; you do not need to create a separate shortcut.", "أضف إجراءً وابحث عن غاف، ثم اختر «أضف عملية من رسالة بنكية». هذا هو إجراء غاف نفسه، ولا تحتاج إلى إنشاء اختصار منفصل.")
                )

                instructionCard(
                    number: "03",
                    title: localized("Pass the notification content", "مرّر محتوى الإشعار"),
                    detail: localized("Set “نص الرسالة” to Shortcut Input (the notification content). Ghaf accepts one text input; no sender field is required.", "اربط حقل «نص الرسالة» بمتغير Shortcut Input (محتوى الإشعار). يستقبل غاف حقلاً نصياً واحداً فقط، ولا يحتاج إلى حقل منفصل لاسم البنك.")
                )

                instructionCard(
                    number: "04",
                    title: localized("Repeat for each bank and test", "كرّر لكل بنك ثم اختبر"),
                    detail: localized("Create one automation per bank app, connect each one to the same Ghaf action, and choose Run Immediately if available. Test with a real notification. If iOS or the bank hides the transaction text, Ghaf cannot extract details from that notification.", "أنشئ أتمتة مستقلة لكل تطبيق بنك، واربطها جميعاً بإجراء غاف نفسه، واختر التشغيل فوراً إذا كان متاحاً. اختبر بإشعار حقيقي. إذا أخفى iOS أو البنك نص العملية، فلن يتمكن غاف من استخراج تفاصيلها.")
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

            Text(localized("Find Ghaf's bank-message action in the Shortcuts action search.", "ابحث عن إجراء غاف للرسائل البنكية في قائمة إجراءات تطبيق الاختصارات."))
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
