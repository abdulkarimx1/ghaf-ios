import SwiftUI
import AppIntents
import UIKit

struct GhafAutomationGuideView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let settings: GhafSettings

    @State private var detectedBanks: [GhafBankSupportContact] = []
    @State private var chosenBanks: [String] = []
    @State private var showingBankPicker = false
    @State private var bankSearch = ""
    @State private var expandedAutomation: Automation?
    @State private var refreshTick = false
    @State private var automationPage = 0

    private enum Automation: String { case messages, notifications, wallet }

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
        let _ = refreshTick
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
#if DEBUG
                    if GhafScreenshotFixture.enabled, GhafScreenshotFixture.automationButtonProof {
                        VStack(spacing: 24) { automationsSection; testSection }
                    } else {
                        fullContent {
                            DispatchQueue.main.async {
                                withAnimation { proxy.scrollTo("bank-automation", anchor: .top) }
                            }
                        }
                    }
#else
                    fullContent {
                        DispatchQueue.main.async {
                            withAnimation { proxy.scrollTo("bank-automation", anchor: .top) }
                        }
                    }
#endif
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                LinearGradient(colors: [theme.background, theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                    .allowsHitTesting(false)
            }
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

    private func fullContent(onBankGuideLink: @escaping () -> Void) -> some View {
        VStack(spacing: 24) {
            header
            privacyCard
            banksSection(onGuideTap: onBankGuideLink)
            automationsSection
            testSection
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            Text(text(
                "Ghaf can’t read your bank login or other apps. Shortcuts passes the alert text you choose and, if mapped, its sender app name. Ghaf parses the alert on this iPhone and doesn’t send it to Ghaf’s server. Currency conversion or optional location lookup may use online services.",
                "لا يستطيع غاف قراءة بيانات دخولك إلى البنك أو الاطلاع على التطبيقات الأخرى. يمرر تطبيق الاختصارات نص التنبيه الذي تختاره، واسم التطبيق المُرسِل إن ربطته. يحلل غاف التنبيه على هذا iPhone ولا يرسله إلى خوادم غاف. وقد تستخدم خدمة تحويل العملة أو البحث الاختياري عن الموقع خدمات عبر الإنترنت."
            ))
            .font(GhafTypography.body(14, languageCode: settings.languageCode))
            .foregroundStyle(theme.primaryText)
            .multilineTextAlignment(ar ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme, radius: 24)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(text("Automatic capture", "التسجيل التلقائي"))
                .font(GhafTypography.display(28, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
            Text(text("Ghaf records bank purchases for you. Set up two automations in Shortcuts on iOS 26; app notifications are also available on iOS 27.",
                      "يسجل غاف مشترياتك البنكية. أعدّ أتمتتين في «الاختصارات» على iOS 26، وتتوفر إشعارات التطبيقات أيضاً على iOS 27."))
                .font(GhafTypography.body(15, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GhafStatusChip(kind: overallStatus, title: statusTitle(overallStatus), theme: theme,
                           languageCode: settings.languageCode)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private func banksSection(onGuideTap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text("Your banks", "بنوكك"))
                    .font(GhafTypography.heading(20, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                if !detectedBanks.isEmpty {
                    Text(text("Detected on this iPhone", "تم اكتشافها على هذا iPhone"))
                        .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
            }
            Button {
                expandedAutomation = .messages
                automationPage = 2
                onGuideTap()
            } label: {
                Text(text(
                    "Turning a bank on here doesn’t connect it. In Shortcuts, choose this bank as the sender for text messages or choose its app for notifications.",
                    "تفعيل البنك هنا لا يربطه بغاف. في «الاختصارات»، اختر مُرسِل البنك للرسائل النصية أو تطبيقه للإشعارات."
                ))
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(ar ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: ar ? .trailing : .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(text("Opens step 3 of the bank automation guide", "يفتح الخطوة 3 من دليل أتمتة البنك"))
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
                .ghafCard(theme: theme)
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
            .ghafCard(theme: theme)
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
            Text(text("Automations", "الأتمتة"))
                .font(GhafTypography.heading(20, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            VStack(spacing: 0) {
                if let shortcut = Bundle.main.url(forResource: "Ghaf Bank Automation", withExtension: "shortcut") {
                    ShareLink(item: shortcut) {
                        automationRow(symbol: "square.and.arrow.down", title: text("Install Ghaf shortcut", "تثبيت اختصار غاف"),
                                      hint: text("Adds Ghaf’s bank message action", "يضيف إجراء الرسائل البنكية من غاف"),
                                      timestamp: defaults.double(forKey: GhafAutomationStatus.lastRunKey))
                    }
                    .buttonStyle(.plain)
                }
                insetDivider
                disclosureRow(.messages)
                insetDivider
                if #available(iOS 27, *) {
                    disclosureRow(.notifications)
                    insetDivider
                }
                disclosureRow(.wallet)
            }
            .ghafCard(theme: theme)
            .environment(\.ghafGlass, .off)
        }
    }

    private func automationRow(symbol: String, title: String, hint: String, timestamp: Double) -> some View {
        HStack(spacing: 12) {
            GhafIconBadge(symbol: symbol, tint: theme.accent, size: 40, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(GhafTypography.body(16, languageCode: settings.languageCode, weight: .semibold)).foregroundStyle(theme.primaryText).lineLimit(1)
                Text(hint).font(GhafTypography.body(13, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            automationMark(rowStatus(timestamp))
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
    }

    private func disclosureRow(_ automation: Automation) -> some View {
        VStack(spacing: 0) {
            Button {
                let update = {
                    if expandedAutomation == automation {
                        expandedAutomation = nil
                    } else {
                        automationPage = 0
                        expandedAutomation = automation
                    }
                }
                if reduceMotion { update() } else { withAnimation(.spring(response: 0.34, dampingFraction: 0.86), update) }
            } label: {
                HStack(spacing: 12) {
                    GhafIconBadge(symbol: automation == .wallet ? "apple.logo" : automation == .messages ? "message" : "bell.badge", tint: theme.accent, size: 40, theme: theme)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(automation == .wallet ? text("Apple Pay purchases", "مشتريات Apple Pay") : automation == .messages ? text("Bank text messages", "رسائل البنك النصية") : text("Bank notifications (iOS 27+)", "إشعارات البنك (iOS 27+)") )
                            .font(GhafTypography.body(16, languageCode: settings.languageCode, weight: .semibold)).foregroundStyle(theme.primaryText).lineLimit(1)
                        Text(automation == .wallet ? text("Capture Wallet transactions", "سجل معاملات المحفظة") : automation == .messages ? text("Catch online card purchases by SMS", "التقط مشتريات البطاقة عبر الرسائل النصية") : text("Pass supported app alerts to Ghaf", "مرر إشعارات التطبيقات المدعومة إلى غاف"))
                            .font(GhafTypography.body(13, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    automationMark(rowStatus(defaults.double(forKey: automation == .wallet ? GhafAutomationStatus.walletRunKey : GhafAutomationStatus.messageRunKey)))
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
                .frame(minHeight: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expandedAutomation == automation || isFixtureExpanded(automation) { automationInstructions(automation) }
        }
        .id(automation == .wallet ? "wallet-automation" : automation == .messages ? "bank-automation" : "notification-automation")
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
                GuideStep(screen: "Ghaf", controls: ["Add Apple Pay purchase"], highlight: "Add Apple Pay purchase", caption: text("Choose “Add Apple Pay purchase”.", "اختر “Add Apple Pay purchase”.")),
                GuideStep(screen: "Add Apple Pay purchase", controls: ["Amount", "Merchant", "Card", "Location", "Done"], highlight: "Amount", caption: text("Map “Amount”, “Merchant”, and “Card”, then tap “Done”.", "اربط “Amount” و“Merchant” و“Card”، ثم اضغط “Done”.")),
            ]
        }
        if automation == .messages {
            return [
                GuideStep(screen: "Shortcuts", controls: ["Library", "Automation", "Gallery"], highlight: "Automation", caption: text("Tap “Automation”.", "اضغط على “Automation”."), imageName: "AutomationTab"),
                GuideStep(screen: "Automation", controls: ["New Automation"], highlight: "New Automation", caption: text("Tap “New Automation”.", "اضغط على “New Automation”."), imageName: "NewAutomation"),
                GuideStep(screen: "Personal Automation", controls: ["Message"], highlight: "Message", caption: text("Choose “Message”.", "اختر “Message”.")),
                GuideStep(screen: "When I Get a Message", controls: ["Sender", "Message Contains"], highlight: "Sender", caption: text("Choose the bank’s sender. Leave “Message Contains” empty unless you want to filter messages.", "اختر مُرسِل البنك. اترك “Message Contains” فارغاً ما لم ترغب في تصفية الرسائل.")),
                GuideStep(screen: "When I Get a Message", controls: ["Run Immediately", "Run After Confirmation"], highlight: "Run Immediately", caption: text("Choose “Run Immediately”.", "اختر “Run Immediately”.")),
                GuideStep(screen: "New Automation", controls: ["New Blank Automation"], highlight: "New Blank Automation", caption: text("Choose “New Blank Automation”.", "اختر “New Blank Automation”.")),
                GuideStep(screen: "Automation", controls: ["Add Action"], highlight: "Add Action", caption: text("Tap “Add Action”.", "اضغط على “Add Action”.")),
                GuideStep(screen: "Add Action", controls: ["Apps"], highlight: "Apps", caption: text("Tap “Apps”, then choose “Ghaf”.", "اضغط على “Apps”، ثم اختر “Ghaf”.")),
                GuideStep(screen: "Ghaf", controls: ["Log bank message"], highlight: "Log bank message", caption: text("Choose “Log bank message”.", "اختر “Log bank message”.")),
                GuideStep(screen: "Log bank message", controls: ["Message text", "Content", "Sender", "Done"], highlight: "Message text", caption: text("Set “Message text” to “Shortcut Input › Content” and “Sender” to “Shortcut Input › Sender”, then tap “Done”.", "اربط “Message text” بـ“Shortcut Input › Content”، و“Sender” بـ“Shortcut Input › Sender”، ثم اضغط “Done”."))
            ]
        }
        return [
            GuideStep(screen: "Shortcuts", controls: ["Library", "Automation", "Gallery"], highlight: "Automation", caption: text("Tap “Automation”.", "اضغط على “Automation”."), imageName: "AutomationTab"),
            GuideStep(screen: "Automation", controls: ["New Automation"], highlight: "New Automation", caption: text("Tap “New Automation”.", "اضغط على “New Automation”."), imageName: "NewAutomation"),
            GuideStep(screen: "Personal Automation", controls: ["Notification"], highlight: "Notification", caption: text("Choose “Notification”.", "اختر “Notification”.")),
            GuideStep(screen: "Notification", controls: ["App"], highlight: "App", caption: text("Tap “App”.", "اضغط على “App”.")),
            GuideStep(screen: "App", controls: ["Choose Apps", "Done"], highlight: "Choose Apps", caption: text("Choose your bank apps, then tap “Done”.", "اختر تطبيقات البنوك، ثم اضغط على “Done”.")),
            GuideStep(screen: "Notification", controls: ["Next"], highlight: "Next", caption: text("Tap “Next”.", "اضغط على “Next”.")),
            GuideStep(screen: "New Automation", controls: ["New Blank Automation"], highlight: "New Blank Automation", caption: text("Choose “New Blank Automation”.", "اختر “New Blank Automation”.")),
            GuideStep(screen: "Automation", controls: ["Add Action"], highlight: "Add Action", caption: text("Tap “Add Action”.", "اضغط على “Add Action”.")),
            GuideStep(screen: "Add Action", controls: ["Apps"], highlight: "Apps", caption: text("Tap “Apps”.", "اضغط على “Apps”.")),
            GuideStep(screen: "Apps", controls: ["Ghaf"], highlight: "Ghaf", caption: text("Choose “Ghaf”.", "اختر “Ghaf”.")),
            GuideStep(screen: "Ghaf", controls: ["Log bank message"], highlight: "Log bank message", caption: text("Choose “Log bank message”.", "اختر “Log bank message”.")),
            GuideStep(screen: "Log bank message", controls: ["Message text", "Shortcut Input", "Sender", "Done"], highlight: "Message text", caption: text("Set “Message text” to “Shortcut Input” and “Sender” to your bank app name, then tap “Done”.", "اربط “Message text” بـ“Shortcut Input” و“Sender” باسم تطبيق البنك، ثم اضغط على “Done”."))
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
            .frame(height: automation == .wallet ? 220 : 220)
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule().fill(index == automationPage ? theme.accent : theme.secondaryText.opacity(0.28))
                        .frame(width: index == automationPage ? 18 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            Text(automation == .wallet
                 ? text("Test it: Pay for something small with Apple Pay, then check Transactions.", "اختبره: ادفع مبلغاً صغيراً عبر Apple Pay، ثم تحقق من المعاملات.")
                 : automation == .messages
                    ? text("Test it with your next bank text message, then check Transactions.", "اختبره مع رسالة البنك النصية التالية، ثم راجع المعاملات.")
                    : text("Test it: Wait for a notification from a supported bank app.", "اختبره بانتظار إشعار من تطبيق بنك مدعوم."))
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: ar ? .trailing : .leading)
            Button(action: openShortcuts) {
                Text(text("Open Shortcuts", "فتح الاختصارات"))
                    .font(GhafTypography.body(18, languageCode: settings.languageCode, weight: .semibold))
                    .foregroundStyle(theme.surface)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(theme.primaryText, in: Capsule())
            }
            .buttonStyle(.plain)
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
            Text(text("“Missing amount or merchant. Nothing saved.” means you skipped “Map the fields”.", "تعني رسالة “المبلغ أو التاجر مفقود. لم يتم الحفظ.” أنك تخطيت خطوة “Map the fields”."))
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
                        .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 18))
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
                                        bankBadge(bank, size: 44)
                                        if isChosen { Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(theme.comfortable) }
                                    }
                                    Text(ar ? bank.nameArabic : bank.name)
                                        .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .medium))
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: 88, height: 88)
                                .ghafCard(theme: theme, radius: 18)
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
        if GhafBrand.match(bank.name) != nil {
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
        guard lastSeen > 0 else { return text("No messages yet", "لا توجد رسائل بعد") }
        let date = Date(timeIntervalSince1970: lastSeen)
        return text("Last message \(date.formatted(.relative(presentation: .named).locale(Locale(identifier: settings.languageCode))))",
                    "آخر عملية \(date.formatted(.relative(presentation: .named).locale(Locale(identifier: settings.languageCode))))")
    }

    private func refreshBanks() {
        let detected = GhafBankAppDetector.installedBanks()
        detectedBanks = detected
        chosenBanks = GhafAutomationBanks.selected(using: detected)
    }

    private func isFixtureExpanded(_ automation: Automation) -> Bool {
#if DEBUG
        GhafScreenshotFixture.enabled && GhafScreenshotFixture.screen == "automation" && GhafScreenshotFixture.automationExpanded == automation.rawValue
#else
        false
#endif
    }

    private func openShortcuts() {
        if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
    }
}
