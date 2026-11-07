import SwiftUI

struct GhafAutomationGuideView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.openURL) private var openURL

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        GhafTreeMark(color: theme.accent)
                            .frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bank notification setup")
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundStyle(theme.primaryText)
                            Text("One automation can listen for several bank apps and send each supported alert to Ghaf.")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Supported banks")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                        HStack(spacing: 8) {
                            ForEach(bankApps, id: \.self) { app in
                                Text(app)
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 9)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                            }
                        }
                        Text("Only choose apps that are installed and send transaction alerts to this iPhone.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(18)
                    .ghafGlass(theme: theme, radius: 22)

                    instructionCard(number: "01", title: "Create one personal automation", detail: "Open Shortcuts → Automation → New Automation → Notification. Select the first bank app, for example Mashreq.")
                    instructionCard(number: "02", title: "Add the other bank triggers", detail: "Use the + beside the app in the trigger to add another Notification trigger. Add Mbank, iVESTOR and ruya as separate triggers. In the automation editor they appear as alternatives joined by “or”, like the example in your setup screenshot.")
                    instructionCard(number: "03", title: "Add Ghaf's transaction action", detail: "Below the triggers, add Ghaf's Log Bank Message action. Set Message Text to Shortcut Input, which carries the notification input into the action.")
                    instructionCard(number: "04", title: "Pass the bank name when available", detail: "If Shortcuts offers the notification's source app as a variable, connect it to Sender / App Name. If not, leave Sender / App Name empty; Ghaf can still parse a supported transaction body using its general parser.")
                    instructionCard(number: "05", title: "Save and test the automation", detail: "Save it and wait for a real bank transaction alert. Confirm the amount, merchant and category in Ghaf. Known merchants are categorized automatically. New or uncertain merchants appear in Needs Review, where correcting the category teaches Ghaf for next time.")

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Privacy and iOS controls", systemImage: "lock.shield")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                        Text("Ghaf cannot read notifications by itself. Shortcuts must pass their input to Ghaf. Some banks hide the amount or merchant in notification previews, and iOS determines whether this notification automation can run without confirmation. Ghaf cannot bypass those restrictions.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(18)
                    .ghafGlass(theme: theme, radius: 22)

                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        Label("Open Shortcuts", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(GhafGlassButtonStyle(theme: theme))
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Bank connection")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.locale, Locale(identifier: settings.languageCode))
        .environment(\.layoutDirection, settings.languageCode == "ar" ? .rightToLeft : .leftToRight)
    }

    private func instructionCard(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.accent)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafGlass(theme: theme, radius: 22)
    }
}
