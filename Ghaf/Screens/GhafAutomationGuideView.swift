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
    @AppStorage(GhafAutomationStatus.messageRunKey) private var messageLastRun: Double = 0
    @AppStorage(GhafAutomationStatus.walletRunKey) private var walletLastRun: Double = 0
    @State private var step = 0

    /// Which steps Ghaf has seen work. "Run Immediately" lives in iOS settings Ghaf can't read, so it never ticks itself.
    private var stepDone: [Bool] {
        [automationLastRun > 0, walletLastRun > 0, messageLastRun > 0, false]
    }

    private var steps: [(title: String, detail: String)] {
        [(localized("Install the automation", "ثبّت الأتمتة"),
          localized("Tap Install automation, choose Shortcuts, then Add. It already listens to Messages.", "اضغط «تثبيت الأتمتة»، اختر الاختصارات ثم «إضافة». هي تستمع للرسائل مسبقاً.")),
         (localized("Catch every Apple Pay purchase", "التقط كل مشتريات Apple Pay"),
          localized("Shortcuts › Automation › + › Transaction. Select all cards, add Ghaf's “Add Apple Pay purchase”, map Amount, Merchant and Card. One automation covers every bank. For the map, add “Get Current Location” first and pass it as Location.", "الاختصارات › الأتمتة › + › معاملة. اختر كل البطاقات، أضف «أضف عملية Apple Pay» من غاف، واربط المبلغ والتاجر والبطاقة. أتمتة واحدة تغطي كل البنوك. للخريطة، أضف «الحصول على الموقع الحالي» أولاً ومرّره كموقع.")),
         (localized("Add your bank apps", "أضف تطبيقات بنوكك"),
          localized("Shortcuts › Automation › + › Notification. Pick a bank app, add Ghaf's “أضف عملية من رسالة بنكية” and set its text to Shortcut Input. Don't add a title filter. Repeat for each bank app.", "الاختصارات › الأتمتة › + › إشعار. اختر تطبيق البنك، أضف «أضف عملية من رسالة بنكية» من غاف واربط النص بـ Shortcut Input. لا تضف فلتر عنوان. كرّر لكل تطبيق بنك.")),
         (localized("Turn on Run Immediately", "فعّل «التشغيل فوراً»"),
          localized("Open each Ghaf automation, choose Run Immediately and turn off Notify When Run, so it works silently. Only you can change this in iOS.", "افتح كل أتمتة لغاف، اختر «التشغيل فوراً» وأوقف «الإشعار عند التشغيل» لتعمل بصمت. iOS يسمح لك وحدك بذلك."))]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                shortcutReadyCard
                AnyView(stepCards)
                AnyView(checklist)

                privacyCard
            }
            .padding(.horizontal, GhafMetrics.gutter)
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
        VStack(spacing: 7) {
            Text(settings.languageCode == "ar" ? "اربط بنكك بغاف" : "Let Ghaf capture your spending.")
                .font(GhafTypography.display(30, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(settings.languageCode == "ar"
                 ? "إعداد لمرة واحدة، وبعدها تُسجَّل مشترياتك تلقائياً."
                 : "Set it up once. After that, purchases log themselves.")
                .font(GhafTypography.body(14, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
            let done = stepDone.filter { $0 }.count
            Text(localized("\(done) of \(steps.count) steps done. Ghaf ticks each one itself the first time it works.",
                           "\(done) من \(steps.count) خطوات تمت. يعلّم غاف كل خطوة بنفسه أول مرة تعمل."))
                .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .padding(.top, 4)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.primaryText.opacity(0.08))
                    Capsule().fill(theme.credit)
                        .frame(width: proxy.size.width * CGFloat(done) / CGFloat(max(steps.count, 1)))
                }
            }
            .frame(height: 8)
            .environment(\.layoutDirection, settings.languageCode == "ar" ? .rightToLeft : .leftToRight)
            .accessibilityElement()
            .accessibilityLabel(localized("\(done) of \(steps.count) steps done", "\(done) من \(steps.count) خطوات تمت"))
            .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// Canvas checklist: one row per step, ticked only when Ghaf detected it; a tap jumps to that card.
    private var checklist: some View {
        let waits = [localized("Waits for a run", "بانتظار تشغيل"), localized("Waits for a purchase", "بانتظار عملية شراء"),
                     localized("Waits for a bank alert", "بانتظار رسالة بنك"), localized("Check in Shortcuts", "تحقق في الاختصارات")]
        return VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                let done = stepDone[index]
                Button { withAnimation(.snappy) { step = index } } label: {
                    HStack(spacing: 12) {
                        Text(done ? "✓" : "\(index + 1)")
                            .font(GhafTypography.number(13, weight: .bold))
                            .foregroundStyle(done ? .white : theme.primaryText)
                            .frame(width: 26, height: 26)
                            .background(done ? theme.credit : theme.primaryText.opacity(0.08), in: Circle())
                        Text(item.title)
                            .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Text(done ? localized("Done", "تم") : waits[index])
                            .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.ghafPress)
                .accessibilityLabel(item.title + ", " + (done ? localized("done", "تم") : waits[index]))
                if index < steps.count - 1 { Divider().overlay(theme.primaryText.opacity(0.06)) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

    /// The setup steps as big numbered cards you swipe through, with dots and arrows under them.
    private var stepCards: some View {
        let items = steps
        return VStack(spacing: 14) {
            TabView(selection: $step) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(format: "%02d", index + 1))
                            .font(GhafTypography.number(56, weight: .heavy))
                            .foregroundStyle(theme.inkText)
                            .environment(\.layoutDirection, .leftToRight)
                        Text(item.title)
                            .font(GhafTypography.heading(20, languageCode: settings.languageCode))
                            .foregroundStyle(theme.inkText)
                        Text(item.detail)
                            .font(GhafTypography.body(14, languageCode: settings.languageCode))
                            .foregroundStyle(theme.inkText.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        // Only a real run proves setup worked; Ghaf records that, so step 1 can say so.
                        if stepDone[index] {
                            Label(localized("Done · detected by Ghaf", "تم · رصده غاف"), systemImage: "checkmark.circle.fill")
                                .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .bold))
                                .foregroundStyle(theme.inkCredit)
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 4)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 300)

            HStack {
                Button { withAnimation(.snappy) { step = max(0, step - 1) } } label: {
                    Image(systemName: "chevron.backward").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 48, height: 48).background(theme.surface, in: Circle())
                }
                .disabled(step == 0)
                .accessibilityLabel(localized("Previous step", "الخطوة السابقة"))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(items.indices, id: \.self) { index in
                        Capsule().fill(index == step ? theme.primaryText : theme.secondaryText.opacity(0.3))
                            .frame(width: index == step ? 20 : 7, height: 7)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(localized("Step \(step + 1) of \(items.count)", "الخطوة \(step + 1) من \(items.count)"))
                Spacer()
                Button { withAnimation(.snappy) { step = min(items.count - 1, step + 1) } } label: {
                    Image(systemName: "chevron.forward").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.accentContrast)
                        .frame(width: 48, height: 48).background(theme.accent, in: Circle())
                }
                .disabled(step == items.count - 1)
                .accessibilityLabel(localized("Next step", "الخطوة التالية"))
            }
            .buttonStyle(.ghafPress)
        }
        .sensoryFeedback(.selection, trigger: step)
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
