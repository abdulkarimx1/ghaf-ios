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
                    title: "Choose the trigger",
                    detail: "In Shortcuts, open Automation and create a personal automation for a message from your bank. Select the bank sender. Use a notification trigger instead only when your iOS version exposes the bank app and its notification content."
                )

                instructionCard(
                    number: "02",
                    title: "Add Ghaf's ready-made action",
                    detail: "Tap Add Action and search for Ghaf. Choose Log Bank Message. You do not need to build a separate shortcut or write any logic; Ghaf supplies this action automatically."
                )

                instructionCard(
                    number: "03",
                    title: "Connect the message",
                    detail: "Set Message Text to the incoming Message variable. Set Sender / App Name to the sender or source-app variable when Shortcuts provides it. Leave that field empty if the source is not available."
                )

                instructionCard(
                    number: "04",
                    title: "Save and test",
                    detail: "Choose Run Immediately where iOS offers it, save the automation, then test with a real bank transaction. Confirm the amount and merchant in Ghaf. Unknown merchants are placed in Needs Review."
                )

                privacyCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Bank automation")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: settings.languageCode))
        .environment(\.layoutDirection, settings.languageCode == "ar" ? .rightToLeft : .leftToRight)
        .toolbarBackground(theme.background, for: .navigationBar)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(settings.languageCode == "ar" ? "اربط بنكك بغاف" : "Let Ghaf capture your spending.")
                .font(GhafTypography.display(30, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(settings.languageCode == "ar"
                 ? "الإجراء جاهز داخل التطبيق. تحتاج فقط إلى اختيار الرسالة التي تشغّله."
                 : "The Ghaf action is already included. You only choose which bank message triggers it.")
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
                    Text("Ghaf action ready")
                        .font(GhafTypography.heading(18, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)
                    Text("Available in Apple Shortcuts after Ghaf is installed")
                        .font(GhafTypography.body(12, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            ShortcutsLink(action: {}) {
                Label("Open Ghaf in Shortcuts", systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GhafPrimaryButtonStyle(theme: theme))
        }
        .padding(18)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.outline, lineWidth: 1))
    }

    private var supportedBanksCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Parser examples")
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

            Text("These banks have parser rules in Ghaf. Only set up automations for apps or message senders that actually deliver alerts to your iPhone.")
                .font(GhafTypography.body(12, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(18)
        .ghafGlass(theme: theme, radius: 20)
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
        .ghafGlass(theme: theme, radius: 19)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What iOS allows", systemImage: "lock.shield")
                .font(GhafTypography.heading(16, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)

            Text("iOS does not allow an app to silently create a personal automation on your behalf. Ghaf does provide its own ready-to-use App Shortcut, so you do not build the action yourself; the only manual part is choosing and approving the trigger in Shortcuts. Some triggers may require confirmation, and a bank may hide transaction details in its notifications.")
                .font(GhafTypography.body(12, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(18)
        .background(theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}
