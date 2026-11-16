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

    @AppStorage(GhafAutomationStatus.lastRunKey) private var automationLastRun: Double = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                shortcutReadyCard
                instructionCard(
                    number: "1",
                    title: localized("Install the automation", "ثبّت الأتمتة"),
                    detail: localized("Tap Install automation, choose Shortcuts, then Add. It already listens to Messages.", "اضغط «تثبيت الأتمتة»، اختر الاختصارات ثم «إضافة». هي تستمع للرسائل مسبقاً.")
                )

                instructionCard(
                    number: "2",
                    title: localized("Catch every Apple Pay purchase", "التقط كل مشتريات Apple Pay"),
                    detail: localized("Shortcuts › Automation › + › Transaction. Select all cards, add Ghaf's “Add Apple Pay purchase”, map Amount, Merchant and Card. One automation covers every bank. For the map, add “Get Current Location” first and pass it as Location.", "الاختصارات › الأتمتة › + › معاملة. اختر كل البطاقات، أضف «أضف عملية Apple Pay» من غاف، واربط المبلغ والتاجر والبطاقة. أتمتة واحدة تغطي كل البنوك. للخريطة، أضف «الحصول على الموقع الحالي» أولاً ومرّره كموقع.")
                )

                instructionCard(
                    number: "3",
                    title: localized("Add your bank apps", "أضف تطبيقات بنوكك"),
                    detail: localized("Shortcuts › Automation › + › Notification. Pick a bank app, add Ghaf's “أضف عملية من رسالة بنكية” and set its text to Shortcut Input. Don't add a title filter. Repeat for each bank app.", "الاختصارات › الأتمتة › + › إشعار. اختر تطبيق البنك، أضف «أضف عملية من رسالة بنكية» من غاف واربط النص بـ Shortcut Input. لا تضف فلتر عنوان. كرّر لكل تطبيق بنك.")
                )

                instructionCard(
                    number: "4",
                    title: localized("Turn on Run Immediately", "فعّل «التشغيل فوراً»"),
                    detail: localized("Open each Ghaf automation and choose Run Immediately. iOS only lets you do this yourself.", "افتح كل أتمتة لغاف واختر «التشغيل فوراً». iOS يسمح لك وحدك بذلك.")
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
                 ? "إعداد لمرة واحدة، وبعدها تُسجَّل مشترياتك تلقائياً."
                 : "Set it up once. After that, purchases log themselves.")
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

            ShortcutsLink(action: {})
                .shortcutsLinkStyle(.automatic)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.outline, lineWidth: 1))
    }

    private func instructionCard(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(GhafTypography.number(13, weight: .bold))
                .foregroundStyle(theme.accentContrast)
                .frame(width: 30, height: 30)
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

            Text(localized("Ghaf only reads the alert text the automation hands it. iOS needs your approval for every automation, so Ghaf can't switch them on for you.", "يقرأ غاف نص التنبيه الذي تمرّره الأتمتة فقط. يحتاج iOS موافقتك على كل أتمتة، لذا لا يستطيع غاف تفعيلها عنك."))
                .font(GhafTypography.body(12, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(18)
        .background(theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}
