import Foundation
import LedgeKit
import CalculatorCore

actor Calculator {
    private var model = CalculatorModel()

    func start() async {
        do {
            if let saved = try await LedgeHost.value(CalculatorState.self, forKey: "calculator") { model = CalculatorModel(saved: saved) }
        } catch { model.showNotice("Settings unavailable") }
        AddOnSession.show(shortcuts: [AddOnShortcut("open", title: "Open calculator", key: "C")])
        send()
    }

    func handle(_ event: SurfaceEvent) async {
        let before = model.saved
        let effect = model.handle(event)
        send()
        if before != model.saved {
            do { try await LedgeHost.set(model.saved, forKey: "calculator") }
            catch { model.showNotice("Save unavailable"); send() }
        }
        do {
            switch effect {
            case .copy(let text): try await LedgeHost.copy(text); model.showNotice("Copied."); send()
            case .openPage: try await LedgeHost.showPage()
            case .holdOpen(let on): try await LedgeHost.holdOpen(on)
            case nil: break
            }
        } catch {
            if case .holdOpen = effect { model.pinFailed() }
            else { model.showNotice(effect == .openPage ? "Open unavailable" : "Copy unavailable") }
            send()
        }
    }

    private func send() {
        AddOnSession.show(model.settingsPage())
        AddOnSession.show(widgets: [model.widget()])
        AddOnSession.show(notchPage: model.page())
    }
}

let calculator = Calculator()
var handlers = AddOnHandlers()
handlers.activate = { await calculator.start() }
handlers.onEvent = { await calculator.handle($0) }
exit(await AddOnSession.run(id: "calculator", handlers: handlers))
