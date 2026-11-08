import AppIntents

struct TodayCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Taffes aujourd'hui"
    static var description = IntentDescription("Donne le nombre de taffes du jour.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let today = PuffStore.count(in: PuffStore.load())
        return .result(value: today, dialog: "\(today) taffes aujourd'hui.")
    }
}

struct TaffeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddPuffIntent(),
            phrases: [
                "Ajouter une taffe dans \(.applicationName)",
                "Nouvelle taffe \(.applicationName)"
            ],
            shortTitle: "Ajouter une taffe",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TodayCountIntent(),
            phrases: [
                "Combien de taffes dans \(.applicationName)"
            ],
            shortTitle: "Taffes aujourd'hui",
            systemImageName: "number.circle"
        )
    }
}
