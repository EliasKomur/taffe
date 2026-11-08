import AppIntents
import WidgetKit
import Foundation

/// Utilisé par le bouton + du widget, Siri et l'app Raccourcis.
struct AddPuffIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter une taffe"
    static var description = IntentDescription("Ajoute une taffe au compteur Taffe.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let puffs = PuffStore.add()
        let today = PuffStore.count(in: puffs)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: TaffeShared.puffsChanged, object: nil)
        return .result(dialog: "Taffe ajoutée. \(today) aujourd'hui.")
    }
}
