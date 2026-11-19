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
    @State private var expandedAutomation: Automation?
    @State private var refreshTick = false

    private enum Automation: String { case bank, wallet }

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
        if realRuns.contains(where: { $0 > Date.now.addingTimeInterval(-14 * 24 * 60 * 60).timeIntervalSince1970 }) { return .working }
        return chosenBanks.isEmpty ? .notSetUp : .waiting
    }

    var body: some View {
        let _ = refreshTick
        ScrollView {
            VStack(spacing: 24) {
                header
                banksSection
                automationsSection
                testSection
                Text(text("iOS can’t create automations or read other apps’ notifications. Shortcuts passes only the data you choose to Ghaf.",
                          "لا يستطيع iOS إنشاء الأتمتة أو قراءة إشعارات التطبيقات الأخرى. يمرر تطبيق الاختصارات إلى غاف البيانات التي تختارها فقط."))
                    .font(GhafTypography.body(12, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 36)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: settings.languageCode))
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showingBankPicker) { bankPicker }
        .onAppear(perform: refreshBanks)
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

    private var header: some View {
        VStack(spacing: 8) {
            Text(text("Automatic capture", "التسجيل التلقائي"))
                .font(GhafTypography.display(28, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
            Text(text("Ghaf records bank purchases for you. iOS needs two one-time automations.",
                      "يسجل غاف مشترياتك البنكية. يتطلب iOS إعداد أتمتتين لمرة واحدة."))
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

    private var banksSection: some View {
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

    private func bankRow(_ bank: GhafBankSupportContact) -> some View {
        let enabledKey = "ghaf.automation.bankEnabled.\(bank.name)"
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        let lastSeen = defaults.double(forKey: "ghaf.automation.lastSeen.\(bank.name)")
        let skipped = GhafAutomationCapturePolicy.skippedCount(for: bank.name, defaults: defaults)
        return HStack(spacing: 12) {
            GhafBrandBadge(name: bank.name, fallbackTint: theme.accent, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(ar ? bank.nameArabic : bank.name)
                    .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text(bankStatus(enabled: enabled, lastSeen: lastSeen, skipped: skipped))
                    .font(GhafTypography.body(12, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
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
                disclosureRow(.bank)
                insetDivider
                disclosureRow(.wallet)
            }
            .ghafCard(theme: theme)
        }
    }

    private func automationRow(symbol: String, title: String, hint: String, timestamp: Double) -> some View {
        HStack(spacing: 12) {
            GhafIconBadge(symbol: symbol, tint: theme.accent, size: 40, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold)).foregroundStyle(theme.primaryText).lineLimit(1)
                Text(hint).font(GhafTypography.body(12, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 4)
            runChip(timestamp)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private func disclosureRow(_ automation: Automation) -> some View {
        VStack(spacing: 0) {
            Button {
                let update = { expandedAutomation = expandedAutomation == automation ? nil : automation }
                if reduceMotion { update() } else { withAnimation(.spring(response: 0.34, dampingFraction: 0.86), update) }
            } label: {
                HStack(spacing: 12) {
                    GhafIconBadge(symbol: automation == .bank ? "bell.badge" : "apple.logo", tint: theme.accent, size: 40, theme: theme)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(automation == .bank ? text("Bank notifications", "إشعارات البنك") : text("Apple Pay purchases", "مشتريات Apple Pay"))
                            .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold)).foregroundStyle(theme.primaryText).lineLimit(1)
                        Text(automation == .bank ? text("Pass supported alerts to Ghaf", "مرر التنبيهات المدعومة إلى غاف") : text("Capture Wallet transactions", "سجل معاملات المحفظة"))
                            .font(GhafTypography.body(12, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    runChip(defaults.double(forKey: automation == .bank ? GhafAutomationStatus.messageRunKey : GhafAutomationStatus.walletRunKey))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expandedAutomation == automation { automationInstructions(automation) }
        }
    }

    private func automationInstructions(_ automation: Automation) -> some View {
        let lines: [String] = automation == .bank
            ? [text("Shortcuts › Automation › + › App notification", "الاختصارات › الأتمتة › + › إشعار تطبيق"),
               text("Choose: \(chosenBanks.joined(separator: ", "))", "اختر: \(chosenBanks.map { name in GhafBankSupportDirectory.contacts.first(where: { $0.name == name })?.nameArabic ?? name }.joined(separator: "، "))"),
               text("Add Ghaf › Log bank message › Run Immediately", "أضف غاف › Log bank message › Run Immediately")]
            : [text("Shortcuts › Automation › + › Transaction", "الاختصارات › الأتمتة › + › Transaction"),
               text("Choose all cards", "اختر كل البطاقات"),
               text("Add Ghaf › Add Apple Pay purchase", "أضف غاف › Add Apple Pay purchase")]
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .bold))
                        .foregroundStyle(theme.accentContrast)
                        .frame(width: 22, height: 22)
                        .background(theme.accent, in: Circle())
                    Text(line)
                        .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: openShortcuts) {
                Text(text("Open Shortcuts", "فتح الاختصارات"))
                    .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .bold))
                    .foregroundStyle(theme.accentContrast)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
        }
        .padding(.horizontal, 16)
        .padding(.leading, 52)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
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
                            .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
                        Text(text("Run Ghaf’s action in Shortcuts with the text GHAF TEST", "شغّل إجراء غاف في الاختصارات بالنص GHAF TEST"))
                            .font(GhafTypography.body(12, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    runChip(defaults.double(forKey: GhafAutomationStatus.testRunKey), waiting: text("Waiting", "بانتظار الاختبار"))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ghafCard(theme: theme)
        }
    }

    private var bankPicker: some View {
        NavigationStack {
            List(GhafBankSupportDirectory.contacts.sorted { $0.name < $1.name }) { bank in
                Button {
                    if chosenBanks.contains(bank.name) { chosenBanks.removeAll { $0 == bank.name } }
                    else { chosenBanks.append(bank.name) }
                    GhafAutomationBanks.save(chosenBanks)
                } label: {
                    HStack(spacing: 12) {
                        GhafBrandBadge(name: bank.name, fallbackTint: theme.accent, size: 36)
                        Text(ar ? bank.nameArabic : bank.name).foregroundStyle(theme.primaryText)
                        Spacer()
                        if chosenBanks.contains(bank.name) { Image(systemName: "checkmark").foregroundStyle(theme.accent) }
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(theme.surface)
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle(text("Add a bank", "إضافة بنك"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Done", "تم")) { showingBankPicker = false }
                }
            }
            .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private var insetDivider: some View {
        Rectangle().fill(theme.outline.opacity(0.55)).frame(height: 0.5).padding(.leading, 68)
    }

    private func runChip(_ timestamp: Double, waiting: String? = nil) -> some View {
        let working = timestamp > 0
        return GhafStatusChip(kind: working ? .working : .waiting,
                              title: working ? text("Working", "يعمل") : (waiting ?? text("Waiting", "بانتظار التشغيل")),
                              theme: theme, languageCode: settings.languageCode)
            .scaleEffect(0.78, anchor: ar ? .leading : .trailing)
            .fixedSize()
    }

    private func statusTitle(_ status: GhafStatusChip.Kind) -> String {
        switch status {
        case .working: text("Working", "يعمل")
        case .waiting: text("Waiting", "بانتظار التشغيل")
        default: text("Not set up", "غير مُعدّ")
        }
    }

    private func bankStatus(enabled: Bool, lastSeen: Double, skipped: Int) -> String {
        if !enabled { return text("Capture off · \(skipped) skipped", "التسجيل متوقف · تم تجاوز \(skipped)") }
        guard lastSeen > 0 else { return text("No messages yet", "لا توجد رسائل بعد") }
        let date = Date(timeIntervalSince1970: lastSeen)
        return text("Last purchase \(date.formatted(.relative(presentation: .named).locale(Locale(identifier: settings.languageCode))))",
                    "آخر عملية \(date.formatted(.relative(presentation: .named).locale(Locale(identifier: settings.languageCode))))")
    }

    private func refreshBanks() {
        let detected = GhafBankAppDetector.installedBanks()
        detectedBanks = detected
        chosenBanks = GhafAutomationBanks.selected(using: detected)
    }

    private func openShortcuts() {
        if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
    }
}
