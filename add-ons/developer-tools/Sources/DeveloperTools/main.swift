import Foundation
import LedgeKit
import DeveloperToolsCore

actor DeveloperTools {
    private var model = DeveloperToolsModel()

    func start() {
        AddOnSession.show(shortcuts: model.shortcuts)
        send()
    }

    func handle(_ event: SurfaceEvent) async {
        let effect = model.handle(event)
        do {
            switch effect {
            case .openPage: try await LedgeHost.showPage()
            case .copy(let text):
                try await LedgeHost.copy(text)
                model.notice = "Copied."
            case .exportPNG(let image):
                model.notice = try await export(image)
            case nil: break
            }
        } catch {
            switch effect {
            case .copy: model.notice = "Copy unavailable. Allow clipboard access in Ledge’s add-on permissions."
            case .exportPNG: model.notice = "Could not add the PNG. Check shelf access in Ledge’s add-on permissions and try again."
            default: model.notice = "Could not open tools. Allow notch control in Ledge’s add-on permissions."
            }
        }
        send()
    }

    private func export(_ data: Data) async throws -> String {
        let folder = try await LedgeHost.dataFolder()
        let file = folder.appendingPathComponent("QR-\(UUID().uuidString).png")
        try data.write(to: file, options: .atomic)
        var status: String
        do {
            try await LedgeHost.addToShelf([file])
            status = "PNG added to the shelf."
        } catch {
            status = "Could not add the PNG. Check shelf access in Ledge’s add-on permissions and try again."
        }
        do { try FileManager.default.removeItem(at: file) }
        catch { status += " Its temporary PNG remains in the add-on’s data folder." }
        return status
    }

    private func send() {
        AddOnSession.show(model.settingsPage())
        AddOnSession.show(notchPage: model.page())
        AddOnSession.show(widgets: [model.widget()])
    }
}

let addOn = DeveloperTools()
var handlers = AddOnHandlers()
handlers.activate = { await addOn.start() }
handlers.onEvent = { await addOn.handle($0) }
exit(await AddOnSession.run(id: "developer-tools", handlers: handlers))
