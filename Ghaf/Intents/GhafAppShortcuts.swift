import AppIntents

struct GhafAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {

        AppShortcut(
            intent: LogBankMessageIntent(),
            phrases: [
                "Add a transaction from a bank notification in \\(.applicationName)",
                "Log a bank notification in \\(.applicationName)",
                "أضف عملية من رسالة بنكية في \\(.applicationName)",
                "سجّل عملية من إشعار بنكي في \\(.applicationName)"
            ],
            shortTitle: "أضف عملية بنكية",
            systemImageName: "arrow.down.circle"
        )
    }
}
