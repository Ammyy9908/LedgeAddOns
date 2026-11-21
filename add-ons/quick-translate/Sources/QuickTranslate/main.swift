import Foundation
import LedgeKit
import QuickTranslateCore

actor QuickTranslate {
    private var model = QuickTranslateModel()

    func start() async {
        do {
            if let saved = try await LedgeHost.value(TranslationPreferences.self, forKey: "languages") { model = .init(preferences: saved) }
            try await LedgeHost.configureTranslation(model.options)
        } catch { model.problem = String(describing: error) }
        AddOnSession.show(shortcuts: model.shortcuts)
        send()
    }

    func handle(_ event: SurfaceEvent) async {
        let previous = model.preferences
        guard let effect = model.handle(event) else { return }
        do {
            switch effect {
            case .configure:
                do { try await LedgeHost.configureTranslation(model.options) }
                catch { model.preferences = previous; throw error }
                do { try await LedgeHost.set(model.preferences, forKey: "languages") }
                catch {
                    model.problem = "These choices apply now, but couldn't be saved. Choose them again after restarting Ledge."
                    send()
                    return
                }
            case .translate:
                try await LedgeHost.translateSelection()
            }
            model.problem = nil
        } catch {
            model.problem = String(describing: error)
        }
        send()
    }

    private func send() {
        AddOnSession.show(model.settingsPage())
        AddOnSession.show(activities: model.problem == nil ? [] : [LiveActivity("problem", symbol: "translate", text: "Translation unavailable", importance: .high, lasts: 5)])
    }
}

let addOn = QuickTranslate()
var handlers = AddOnHandlers()
handlers.activate = { await addOn.start() }
handlers.onEvent = { event in await addOn.handle(event) }
exit(await AddOnSession.run(id: "quick-translate", handlers: handlers))
