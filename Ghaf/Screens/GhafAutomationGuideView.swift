import SwiftUI
import AppIntents
import UIKit

struct GhafAutomationGuideView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    let settings: GhafSettings

    @State private var chosenBanks: [String] = []
    @State private var showingBankPicker = false
    @State private var bankSearch = ""
    @State private var refreshTick = false
    @State private var automationPage = 0
    @State private var privacyExpanded = false

    private enum Automation: String { case messages, wallet }

    private let defaults = UserDefaults.standard
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode,
                          systemIsDark: systemColorScheme == .dark)
    }
    private var ar: Bool { settings.languageCode == "ar" }
    private func text(_ en: String, _ arabic: String) -> String { ar ? arabic : en }
    private var realRuns: [Double] {
        [defaults.double(forKey: GhafAutomationStatus.messageRunKey),
         defaults.double(forKey: GhafAutomationStatus.walletRunKey)]
    }
    private var overallStatus: GhafStatusChip.Kind {
#if DEBUG
        if GhafScreenshotFixture.enabled, GhafScreenshotFixture.screen == "automation" {
            switch GhafScreenshotFixture.automationState {
            case "waiting": return .waiting
            case "working": return .working
            default: return .notSetUp
            }
        }
#endif
        if realRuns.contains(where: { $0 > Date.now.addingTimeInterval(-14 * 24 * 60 * 60).timeIntervalSince1970 }) { return .working }
        return chosenBanks.isEmpty ? .notSetUp : .waiting
    }

    var body: some View {
#if DEBUG
        if GhafScreenshotFixture.enabled, GhafScreenshotFixture.screen == "automation" {
            NavigationStack { mainContent }
        } else {
            mainContent
        }
#else
        mainContent
#endif
    }

    private var mainContent: some View {
        let _ = refreshTick
        return ScrollView {
                VStack(spacing: 18) {
#if DEBUG
                    if GhafScreenshotFixture.enabled, GhafScreenshotFixture.automationButtonProof {
                        VStack(spacing: 18) { automationsSection; testSection }
                    } else {
                        fullContent
                    }
#else
                    fullContent
#endif
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [theme.background, theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 40).allowsHitTesting(false)
        }
        .ghafBackground(theme: theme)
        .navigationTitle(text("Your banks", "بنوكك"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(theme.background, for: .navigationBar)
        .environment(\.locale, Locale(identifier: settings.languageCode))
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showingBankPicker) { bankPicker }
        .onAppear {
#if DEBUG
            if GhafScreenshotFixture.enabled, GhafScreenshotFixture.screen == "automation" {
                GhafScreenshotFixture.applyAutomation()
            }
#endif
            refreshBanks()
#if DEBUG
            if GhafScreenshotFixture.enabled { automationPage = max(0, (GhafScreenshotFixture.automationPage ?? 1) - 1) }
#endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshBanks(); refreshTick.toggle() }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, scenePhase == .active else { return }
                refreshTick.toggle()
            }
        }
    }

    private var fullContent: some View {
        VStack(spacing: 18) {
            header
            privacyCard
            automationsSection
            banksSection
            testSection
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
          Button { withAnimation(.easeInOut(duration: 0.2)) { privacyExpanded.toggle() } } label: {
            HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            Text(text("Privacy", "الخصوصية"))
                .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Spacer()
            Text(text("Details", "التفاصيل"))
                .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .medium))
                .foregroundStyle(theme.accent)
            Image(systemName: privacyExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryText)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
          }.buttonStyle(.plain)
          Text(text(
                "Ghaf can’t read your bank login or other apps. Shortcuts passes the alert text you choose and, if mapped, its sender app name. Ghaf parses the alert on this iPhone and doesn’t send it to Ghaf’s server. Currency conversion or optional location lookup may use online services.",
                "لا يستطيع غاف قراءة بيانات دخولك إلى البنك أو الاطلاع على التطبيقات الأخرى. يمرر تطبيق الاختصارات نص التنبيه الذي تختاره، واسم التطبيق المُرسِل إن ربطته. يحلل غاف التنبيه على هذا iPhone ولا يرسله إلى خوادم غاف. وقد تستخدم خدمة تحويل العملة أو البحث الاختياري عن الموقع خدمات عبر الإنترنت."
            ))
            .font(GhafTypography.body(13, languageCode: settings.languageCode))
            .foregroundStyle(theme.secondaryText)
            .multilineTextAlignment(ar ? .trailing : .leading)
            .lineLimit(privacyExpanded ? nil : 2)
            .fixedSize(horizontal: false, vertical: privacyExpanded)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(text("Automatic capture", "التسجيل التلقائي"))
                .font(GhafTypography.display(28, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
            Text(text("Set it up once. Ghaf captures purchases automatically.",
                      "أكمل الإعداد مرة واحدة، ثم يسجّل غاف مشترياتك تلقائيًا."))
                .font(GhafTypography.body(15, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1).minimumScaleFactor(0.82)
            GhafStatusChip(kind: overallStatus, title: statusTitle(overallStatus), theme: theme,
                           languageCode: settings.languageCode)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var banksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text("Your banks", "بنوكك"))
                    .font(GhafTypography.heading(20, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)
                Spacer()
            }
            Text(text("Choose the banks whose messages you want Ghaf to capture.",
                      "اختر البنوك التي تريد من غاف تسجيل رسائلها."))
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(ar ? .trailing : .leading)
            if chosenBanks.isEmpty {
                VStack(spacing: 16) {
                    Text(text("Choose the banks you get messages from", "اختر البنوك التي تصلك رسائل منها"))
                        .font(GhafTypography.body(15, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Button { showingBankPicker = true } label: {
                        Label(text("Add a bank", "إضافة بنك"), systemImage: "plus")
                            .font(GhafTypography.body(17, languageCode: settings.languageCode, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                            .padding(.horizontal, 20)
                            .frame(height: 48)
                            .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            } else {
            VStack(spacing: 0) {
                ForEach(Array(chosenBanks.enumerated()), id: \.element) { index, name in
                    if let bank = GhafBankSupportDirectory.contacts.first(where: { $0.name == name }) {
                        bankRow(bank)
                        if index < chosenBanks.count - 1 { insetDivider }
                    }
                }
                if !chosenBanks.isEmpty { insetDivider }
                Button { showingBankPicker = true } label: {
                    HStack(spacing: 12) {
                        GhafIconBadge(symbol: "plus", tint: theme.accent, size: 38, theme: theme)
                        Text(text("Add a bank", "إضافة بنك"))
                            .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            }
        }
    }

    private func bankRow(_ bank: GhafBankSupportContact) -> some View {
        let enabledKey = "ghaf.automation.bankEnabled.\(bank.name)"
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        let lastSeen = defaults.double(forKey: "ghaf.automation.lastSeen.\(bank.name)")
        let skipped = GhafAutomationCapturePolicy.skippedCount(for: bank.name, defaults: defaults)
        return HStack(spacing: 12) {
            bankBadge(bank, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(ar ? bank.nameArabic : bank.name)
                    .font(GhafTypography.body(16, languageCode: settings.languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text(bankStatus(enabled: enabled, lastSeen: lastSeen, skipped: skipped))
                    .font(GhafTypography.body(13, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Toggle(isOn: Binding(
                get: { defaults.object(forKey: enabledKey) as? Bool ?? true },
                set: { defaults.set($0, forKey: enabledKey); refreshTick.toggle() }
            )) { EmptyView() }
            .labelsHidden()
            .toggleStyle(GhafToggleStyle(theme: theme, languageCode: settings.languageCode))
            .accessibilityLabel(text("Capture for \(bank.name)", "التسجيل من \(bank.nameArabic)"))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
    }

    private var automationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("Add a shortcut", "إضافة اختصار"))
                .font(GhafTypography.heading(20, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            HStack(alignment: .top, spacing: 12) {
                shortcutCard(.messages, title: text("Bank messages", "رسائل البنك"), button: text("Add Bank Automation", "إضافة أتمتة البنك"), url: GhafLinks.bankAlertShortcutURL)
                shortcutCard(.wallet, title: text("Apple Pay", "Apple Pay"), button: text("Add Capture Apple Pay", "إضافة اختصار تسجيل Apple Pay"), url: GhafLinks.applePayShortcutURL)
            }
        }
    }

    private func shortcutCard(_ automation: Automation, title: String, button: String, url: String) -> some View {
        let stamp = defaults.double(forKey: automation == .wallet ? GhafAutomationStatus.walletRunKey : GhafAutomationStatus.messageRunKey)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold)).foregroundStyle(theme.primaryText).lineLimit(2).minimumScaleFactor(0.82)
                Spacer(minLength: 0)
                automationMark(rowStatus(stamp))
            }
            if let link = URL(string: url), !url.isEmpty {
                // The card title names the template, so the button stays short and on one line.
                Link(destination: link) {
                    Text(text("Add shortcut", "إضافة الاختصار"))
                        .lineLimit(1).minimumScaleFactor(0.85)
                }.ghafProminentButton(theme: theme, languageCode: settings.languageCode).accessibilityLabel(button)
            }
            NavigationLink { manualSetupPage(automation) } label: {
                Text(text("Set it up manually", "الإعداد يدوياً"))
                    .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .medium))
                    .foregroundStyle(theme.accent).frame(maxWidth: .infinity, minHeight: 44)
                    .multilineTextAlignment(.center)
            }.buttonStyle(.plain)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme, radius: 24)
    }

    private func manualSetupPage(_ automation: Automation) -> some View {
        ScrollView {
            automationInstructions(automation).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .navigationTitle(automation == .wallet ? text("Apple Pay setup", "إعداد Apple Pay") : text("Bank message setup", "إعداد رسائل البنك"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { automationPage = 0 }
        .overlay(alignment: .top) {
            LinearGradient(colors: [theme.background, theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 40).allowsHitTesting(false)
        }
    }

    private struct GuideStep: Identifiable {
        let screen: String
        let controls: [String]
        let highlight: String
        let caption: String
        var imageName: String? = nil
        var id: String { caption }
    }

    private func guideSteps(_ automation: Automation) -> [GuideStep] {
        if automation == .wallet {
            return [
                GuideStep(screen: "Shortcuts", controls: ["Library", "Automation", "Gallery"], highlight: "Automation", caption: text("Tap “Automation”.", "اضغط على “Automation”."), imageName: "AutomationTab"),
                GuideStep(screen: "Automation", controls: ["New Automation"], highlight: "New Automation", caption: text("Tap “New Automation”.", "اضغط على “New Automation”."), imageName: "NewAutomation"),
                GuideStep(screen: "Personal Automation", controls: ["Wallet", "When I tap a Wallet Card or Pass"], highlight: "Wallet", caption: text("Choose “Wallet”.", "اختر “Wallet”."), imageName: "WalletTrigger"),
                GuideStep(screen: "When I tap", controls: ["Wallet Card or Pass"], highlight: "Wallet Card or Pass", caption: text("Choose “Wallet Card or Pass”.", "اختر “Wallet Card or Pass”.")),
                GuideStep(screen: "When I tap", controls: ["Run After Confirmation", "Run Immediately", "Next"], highlight: "Run Immediately", caption: text("Choose “Run Immediately”.", "اختر “Run Immediately”."), imageName: "RunImmediately"),
                GuideStep(screen: "When I tap", controls: ["Next"], highlight: "Next", caption: text("Tap “Next”.", "اضغط على “Next”.")),
                GuideStep(screen: "New Automation", controls: ["New Blank Automation"], highlight: "New Blank Automation", caption: text("Choose “New Blank Automation”.", "اختر “New Blank Automation”.")),
                GuideStep(screen: "Automation", controls: ["Add Action"], highlight: "Add Action", caption: text("Tap “Add Action”.", "اضغط على “Add Action”.")),
                GuideStep(screen: "Add Action", controls: ["Apps"], highlight: "Apps", caption: text("Tap “Apps”.", "اضغط على “Apps”.")),
                GuideStep(screen: "Apps", controls: ["Ghaf"], highlight: "Ghaf", caption: text("Choose “Ghaf”.", "اختر “Ghaf”.")),
                GuideStep(screen: "Ghaf", controls: ["Capture Apple Pay"], highlight: "Capture Apple Pay", caption: text("Choose “Capture Apple Pay”.", "اختر “Capture Apple Pay”.")),
                GuideStep(screen: "Capture Apple Pay", controls: ["Wallet transaction", "Location", "Done"], highlight: "Wallet transaction", caption: text("Leave “Wallet transaction” connected automatically, then tap “Done”. Do not fill Amount, Merchant, or Card.", "اترك “Wallet transaction” متصلاً تلقائياً، ثم اضغط “Done”. لا تُدخل Amount أو Merchant أو Card.")),
            ]
        }
        return [
                GuideStep(screen: "Shortcuts", controls: ["Library", "Automation", "Gallery"], highlight: "Automation", caption: text("Tap “Automation”.", "اضغط على “Automation”."), imageName: "AutomationTab"),
                GuideStep(screen: "Automation", controls: ["New Automation"], highlight: "New Automation", caption: text("Tap “New Automation”.", "اضغط على “New Automation”."), imageName: "NewAutomation"),
                GuideStep(screen: "Personal Automation", controls: ["Message"], highlight: "Message", caption: text("Choose “Message”.", "اختر “Message”.")),
                GuideStep(screen: "When I Get a Message", controls: ["Sender", "Message Contains"], highlight: "Sender", caption: text("Choose the bank’s sender. Leave “Message Contains” empty unless you want to filter messages.", "اختر مُرسِل البنك. اترك “Message Contains” فارغاً ما لم ترغب في تصفية الرسائل.")),
                GuideStep(screen: "When I Get a Message", controls: ["Run Immediately", "Run After Confirmation"], highlight: "Run Immediately", caption: text("Choose “Run Immediately”.", "اختر “Run Immediately”.")),
                GuideStep(screen: "New Automation", controls: ["New Blank Automation"], highlight: "New Blank Automation", caption: text("Choose “New Blank Automation”.", "اختر “New Blank Automation”.")),
                GuideStep(screen: "Automation", controls: ["Add Action"], highlight: "Add Action", caption: text("Tap “Add Action”.", "اضغط على “Add Action”.")),
                GuideStep(screen: "Add Action", controls: ["Apps"], highlight: "Apps", caption: text("Tap “Apps”, then choose “Ghaf”.", "اضغط على “Apps”، ثم اختر “Ghaf”.")),
                GuideStep(screen: "Ghaf", controls: ["Capture Bank Alert"], highlight: "Capture Bank Alert", caption: text("Choose “Capture Bank Alert”.", "اختر “Capture Bank Alert”.")),
                GuideStep(screen: "Capture Bank Alert", controls: ["Alert text", "Content", "Sender", "Done"], highlight: "Alert text", caption: text("Set “Alert text” to “Shortcut Input › Content” and “Sender” to “Shortcut Input › Sender”, then tap “Done”.", "اربط “Alert text” بـ“Shortcut Input › Content”، و“Sender” بـ“Shortcut Input › Sender”، ثم اضغط “Done”."))
            ]
        }

    private func automationInstructions(_ automation: Automation) -> some View {
        let steps = guideSteps(automation)
        return VStack(spacing: 14) {
            HStack {
                Text(text("Step \(automationPage + 1) of \(steps.count)", "الخطوة \(automationPage + 1) من \(steps.count)"))
                    .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            }
            if automationPage == 1 {
                Text(text("If you already have automations, tap “+” at the top instead.", "إذا سبق أن أنشأت أتمتة، فاضغط على “+” أعلى الشاشة."))
                    .font(GhafTypography.body(12, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: ar ? .trailing : .leading)
            }
            TabView(selection: $automationPage) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(spacing: 10) {
                        if let imageName = step.imageName {
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                                .accessibilityLabel("Shortcuts screen: \(step.screen), highlighted \(step.highlight)")
                        } else {
                            shortcutScreen(step)
                        }
                        Text(step.caption)
                            .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                            .multilineTextAlignment(ar ? .trailing : .leading)
                            .frame(maxWidth: .infinity, alignment: ar ? .trailing : .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tag(index)
                    .padding(.horizontal, 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 220)
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule().fill(index == automationPage ? theme.accent : theme.secondaryText.opacity(0.28))
                        .frame(width: index == automationPage ? 18 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            Text(automation == .wallet
                 ? text("Test it: Pay for something small with Apple Pay, then check Transactions.", "اختبره: ادفع مبلغاً صغيراً عبر Apple Pay، ثم تحقق من المعاملات.")
                 : text("Test it with your next bank text message, then check Transactions.", "اختبره مع رسالة البنك النصية التالية، ثم راجع المعاملات."))
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: ar ? .trailing : .leading)
            Button(action: openShortcuts) {
                Text(text("Open Shortcuts", "فتح الاختصارات"))
            }
            .ghafProminentButton(theme: theme, languageCode: settings.languageCode)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    private func shortcutScreen(_ step: GuideStep) -> some View {
        VStack(spacing: 7) {
            HStack {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryText)
                Spacer()
                Text(step.screen).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.primaryText)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryText)
            }
            .padding(.bottom, 2)
            ForEach(step.controls, id: \.self) { control in
                HStack(spacing: 8) {
                    Image(systemName: control.contains("Location") ? "location" : control.contains("Amount") ? "dollarsign.circle" : control.contains("Merchant") ? "storefront" : control.contains("Card") ? "creditcard" : "circle")
                        .font(.system(size: 11, weight: .medium))
                    Text(control).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if control == step.highlight { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                    else { Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium)) }
                }
                .foregroundStyle(control == step.highlight ? theme.surface : theme.primaryText)
                .padding(.horizontal, 9)
                .frame(minHeight: 23)
                .background(control == step.highlight ? theme.accent : theme.primaryText.opacity(theme.isDark ? 0.07 : 0.045), in: RoundedRectangle(cornerRadius: 7))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.outline.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shortcuts screen: \(step.screen), highlighted \(step.highlight)")
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("Check it works", "تحقق من عمله"))
                .font(GhafTypography.heading(20, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Button(action: openShortcuts) {
                HStack(spacing: 12) {
                    GhafIconBadge(symbol: "checkmark.shield", tint: theme.accent, size: 40, theme: theme)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text("Send a test", "إرسال اختبار"))
                            .font(GhafTypography.body(16, languageCode: settings.languageCode, weight: .semibold)).foregroundStyle(theme.primaryText).lineLimit(1)
                        Text(text("Run Ghaf’s action in Shortcuts with the text GHAF TEST", "شغّل إجراء غاف في الاختصارات بالنص GHAF TEST"))
                            .font(GhafTypography.body(13, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    automationMark(rowStatus(defaults.double(forKey: GhafAutomationStatus.testRunKey)))
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
                .frame(minHeight: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ghafCard(theme: theme)
            Text(text("“Ghaf got no transaction details” means nothing was saved. Make a real Wallet payment to test it.", "تعني رسالة “لم يتلقَّ غاف تفاصيل المعاملة” أنه لم يُحفظ شيء. اختبره بعملية دفع حقيقية عبر Wallet."))
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 4)
        }
    }

    private var bankPicker: some View {
        let banks = GhafBankSupportDirectory.contacts.sorted { $0.name < $1.name }.filter { bank in
            bankSearch.isEmpty || bank.name.localizedCaseInsensitiveContains(bankSearch) || bank.nameArabic.localizedCaseInsensitiveContains(bankSearch)
        }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextField(text("Search banks", "ابحث عن بنك"), text: $bankSearch)
                        .font(GhafTypography.body(17, languageCode: settings.languageCode))
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(theme.surface, in: Capsule())
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(banks) { bank in
                            let isChosen = chosenBanks.contains(bank.name)
                            Button {
                                if isChosen { chosenBanks.removeAll { $0 == bank.name } }
                                else { chosenBanks.append(bank.name) }
                                GhafAutomationBanks.save(chosenBanks)
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack(alignment: .topTrailing) {
                                        bankBadge(bank, size: 54)
                                        if isChosen {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(theme.accent)
                                                .background(theme.background, in: Circle())
                                        }
                                    }
                                    Text(ar ? bank.nameArabic : bank.name)
                                        .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .medium))
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 94)
                                .padding(8)
                                .background(isChosen ? theme.accent.opacity(theme.isDark ? 0.18 : 0.10) : .clear, in: RoundedRectangle(cornerRadius: 18))
                                .contentShape(RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ar ? bank.nameArabic : bank.name)
                            .accessibilityAddTraits(isChosen ? .isSelected : [])
                        }
                    }
                }
                .padding(20)
            }
            .background(theme.background)
            .navigationTitle(text("Choose banks", "اختر البنوك"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Done", "تم")) { showingBankPicker = false; bankSearch = "" }
                }
            }
            .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private var insetDivider: some View {
        Rectangle().fill(theme.outline.opacity(0.55)).frame(height: 0.5).padding(.leading, 68)
    }

    @ViewBuilder
    private func bankBadge(_ bank: GhafBankSupportContact, size: CGFloat) -> some View {
        if let source = UIImage(named: "Bank-\(bank.id)"), let logo = Self.logoCache.object(forKey: bank.id as NSString) ?? removeWhiteBackdrop(source).map({ image in
            Self.logoCache.setObject(image, forKey: bank.id as NSString)
            return image
        }) {
            Group {
                if logoIsMostlyWhite(logo) {
                    ZStack {
                        Image(uiImage: logo).renderingMode(.template).resizable().foregroundStyle(theme.outline).scaledToFit()
                        Image(uiImage: logo).resizable().scaledToFit().padding(1)
                    }
                } else {
                    Image(uiImage: logo).resizable().scaledToFit()
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else if GhafBrand.match(bank.name) != nil {
            GhafBrandBadge(name: bank.name, fallbackTint: theme.accent, size: size)
        } else {
            let hex = GhafUAEBank.match([bank.name])?.colors.0 ?? bankMonogramColor(for: bank.id)
            let color = Color(red: Double((hex >> 16) & 0xFF) / 255,
                              green: Double((hex >> 8) & 0xFF) / 255,
                              blue: Double(hex & 0xFF) / 255)
            Text(String((ar ? bank.nameArabic : bank.name).trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private static let logoCache = NSCache<NSString, UIImage>()

    private func removeWhiteBackdrop(_ image: UIImage) -> UIImage? {
        guard let source = image.cgImage else { return nil }
        let scale = min(160 / CGFloat(max(source.width, source.height)), 1)
        let width = max(1, Int(CGFloat(source.width) * scale))
        let height = max(1, Int(CGFloat(source.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var queue: [Int] = []
        func eraseWhite(at index: Int) {
            let offset = index * 4
            guard pixels[offset + 3] > 220, pixels[offset] > 220, pixels[offset + 1] > 220, pixels[offset + 2] > 220 else { return }
            pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0; pixels[offset + 3] = 0
            queue.append(index)
        }
        for x in 0..<width { eraseWhite(at: x); eraseWhite(at: (height - 1) * width + x) }
        for y in 0..<height { eraseWhite(at: y * width); eraseWhite(at: y * width + width - 1) }
        var cursor = 0
        while cursor < queue.count {
            let i = queue[cursor], x = i % width, y = i / width
            cursor += 1
            if x > 0 { eraseWhite(at: i - 1) }
            if x + 1 < width { eraseWhite(at: i + 1) }
            if y > 0 { eraseWhite(at: i - width) }
            if y + 1 < height { eraseWhite(at: i + width) }
        }
        return pixels.withUnsafeMutableBytes { bytes -> UIImage? in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cgImage = context.makeImage() else { return nil }
            return UIImage(cgImage: cgImage)
        }
    }

    private func logoIsMostlyWhite(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let width = 24, height = 24
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        let visible = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 180 }
        let white = visible.filter { alphaIndex in
            let i = alphaIndex - 3
            return pixels[i] > 225 && pixels[i + 1] > 225 && pixels[i + 2] > 225
        }
        return !visible.isEmpty && Double(white.count) / Double(visible.count) > 0.65
    }

    private func bankMonogramColor(for id: String) -> UInt32 {
        [
            "alrajhi": 0x008B68, "snb": 0x005A4A, "riyad": 0x005B45,
            "nbk": 0x009B61, "qnb": 0x6F1D5B, "dohabank": 0xAF1E2D,
            "nbb": 0xC92335, "bankmuscat": 0xB51E2D, "alinma": 0x008D72,
            "albilad": 0x225E42, "kfh": 0x14713D, "boubyan": 0xA6193C,
            "bbk": 0xB31F35, "sohar": 0x008E79, "nbo": 0x6E2C91,
            "bankdhofar": 0x064A79, "qib": 0x851B4B
        ][id] ?? 0x475569
    }

    private func automationMark(_ kind: GhafStatusChip.Kind) -> some View {
        let color: Color = switch kind {
        case .working: theme.comfortable
        case .waiting: theme.close
        case .notSetUp: theme.secondaryText
        case .failed: theme.over
        }
        let symbol: String = switch kind {
        case .working: "checkmark"
        case .waiting: "clock"
        case .notSetUp: "circle.dashed"
        case .failed: "exclamationmark"
        }
        let label = statusTitle(kind)
        return Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(Circle().fill(color.opacity(0.14)))
            .overlay(Circle().stroke(color.opacity(0.35), lineWidth: 1))
            .accessibilityLabel(label)
    }

    private func statusTitle(_ status: GhafStatusChip.Kind) -> String {
        switch status {
        case .working: text("Working", "يعمل")
        case .waiting: text("Waiting", "بانتظار التشغيل")
        default: text("Not set up", "غير مُعدّ")
        }
    }

    private func rowStatus(_ timestamp: Double) -> GhafStatusChip.Kind {
        if timestamp > 0 { return .working }
#if DEBUG
        if GhafScreenshotFixture.enabled, GhafScreenshotFixture.screen == "automation",
           GhafScreenshotFixture.automationState == "none" { return .notSetUp }
#endif
        return .waiting
    }

    private func bankStatus(enabled: Bool, lastSeen: Double, skipped: Int) -> String {
        if !enabled { return text("Off: Ghaf ignores this bank’s alerts · \(skipped) skipped", "متوقف: يتجاهل غاف تنبيهات هذا البنك · تم تجاهل \(skipped)") }
        guard lastSeen > 0 else { return text("Waiting for first alert", "بانتظار أول تنبيه") }
        let date = Date(timeIntervalSince1970: lastSeen)
        return text("Working · last alert \(date.formatted(.relative(presentation: .named).locale(Locale(identifier: settings.languageCode))))",
                    "يعمل · آخر تنبيه \(date.formatted(.relative(presentation: .named).locale(Locale(identifier: settings.languageCode))))")
    }

    private func refreshBanks() {
        chosenBanks = GhafAutomationBanks.selected()
    }

    private func openShortcuts() {
        if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
    }
}
