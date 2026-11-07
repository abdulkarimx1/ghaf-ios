import AppIntents

struct GhafAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {

        AppShortcut(
            intent: LogBankMessageIntent(),
            phrases: [
                "Log a bank message in \(.applicationName)",
                "Save a transaction in \(.applicationName)"
            ],
            shortTitle: "Log Bank Message",
            systemImageName: "arrow.down.circle"
        )
    }
}
