import AppIntents

struct GhafAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {

        AppShortcut(
            intent: LogBankMessageIntent(),
            phrases: [
                "Log a bank message in \(.applicationName)",
                "Save a transaction in \(.applicationName)",
                "سجّل رسالة بنكية في \(.applicationName)",
                "احفظ عملية في \(.applicationName)"
            ],
            shortTitle: "أضف عملية بنكية",
            systemImageName: "arrow.down.circle"
        )
    }
}
