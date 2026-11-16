import Foundation
import LedgeKit
import EmojiCore

// Emoji: Ledge's floating picker, filled with every emoji this Mac can draw. Ledge shows the panel on the shortcut
// the person picks and types the chosen emoji in; this keeps the skin tone and Recents, and sends the items.

actor Emoji {
    private var settings = EmojiSettings()
    private let catalog: EmojiCatalog = {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return EmojiCatalog(upTo: EmojiCatalog.supportedVersion(macOS: os.majorVersion, minor: os.minorVersion))
    }()

    func start() async {
        settings = (try? await LedgeHost.value(EmojiSettings.self, forKey: EmojiSettings.key)) ?? EmojiSettings()
        send()
    }

    func handle(_ event: SurfaceEvent) async {
        guard event.surface == Surface.settingsPage, settings.handle(event) else { return }
        await save()
        send()
    }

    func picked(_ item: PickedItem) async {
        settings.picked(item.id)
        await save()
        send()
    }

    private func save() async {
        do { try await LedgeHost.set(settings, forKey: EmojiSettings.key) } catch {
            AddOnSession.log("Couldn't save the settings.", level: .error)
        }
    }

    private func send() {
        AddOnSession.show(settings.settingsPage())
        AddOnSession.show(picker: settings.picker(from: catalog))
    }
}

let addOn = Emoji()
var handlers = AddOnHandlers()
handlers.activate = { await addOn.start() }
handlers.onEvent = { event in await addOn.handle(event) }
handlers.onPicked = { item in await addOn.picked(item) }
exit(await AddOnSession.run(id: "emoji", handlers: handlers))
