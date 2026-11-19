import AppIntents

struct GhafAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {

        AppShortcut(
            intent: LogBankMessageIntent(),
            phrases: [
                "Capture a bank alert with \(.applicationName)",
                "Send a bank alert to \(.applicationName)"
            ],
            shortTitle: "Capture Bank Alert",
            systemImageName: "arrow.down.circle"
        )

        AppShortcut(
            intent: LogWalletTransactionIntent(),
            phrases: [
                "Capture an Apple Pay purchase with \(.applicationName)"
            ],
            shortTitle: "Capture Apple Pay",
            systemImageName: "wallet.pass"
        )
    }
}
