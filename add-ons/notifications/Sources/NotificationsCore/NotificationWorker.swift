import Foundation
import LedgeKit

public enum NotificationWorker {
    public enum Failure: Error { case invalidRequest }

    /// Where the add-on keeps its one choice. Ledge's stored settings by default; tests pass their own.
    public struct Settings: Sendable {
        public var load: @Sendable () async -> Bool?
        public var save: @Sendable (Bool) async -> Void
        public init(load: @escaping @Sendable () async -> Bool?, save: @escaping @Sendable (Bool) async -> Void) {
            self.load = load
            self.save = save
        }
        public static let ledge = Settings(
            load: { try? await LedgeHost.value(Bool.self, forKey: "showMessageText") },
            save: { try? await LedgeHost.set($0, forKey: "showMessageText") })
    }

    /// The settings page: whether the notch shows what a message says, or only who it's from.
    public static func page(showsText: Bool) -> SettingsPage {
        SettingsPage([
            SettingsSection("mirroring", title: "Mirroring",
                            footer: "Turn the add-on on above to mirror banners. Ledge reads visible banners with Accessibility access and passes their text only to this add-on, which doesn’t store it. Hidden previews can’t be recovered, and changes to macOS may affect banner detection.",
                            rows: [.toggle("showMessageText", "Show message text",
                                           detail: "Off, the notch shows the sender and “New notification”.", isOn: showsText)])
        ])
    }

    /// The session's handlers: Ledge sends each visible banner as a `banner` request while the add-on is on.
    public static func handlers(settings: Settings = .ledge) -> AddOnHandlers {
        let choice = Choice()
        var handlers = AddOnHandlers()
        handlers.activate = {
            let showsText = await settings.load() ?? false
            await choice.set(showsText)
            AddOnSession.show(page(showsText: showsText))
        }
        handlers.onEvent = { event in
            guard event.surface == Surface.settingsPage, event.control == "showMessageText", case .toggled(let on) = event.action else { return }
            await choice.set(on)
            await settings.save(on)
            AddOnSession.show(page(showsText: on))
        }
        handlers.on("banner") { (request: NotificationBannerRequest) -> NotificationBannerResponse in
            guard request.protocolVersion == 1 else { throw AddOnError("Unsupported banner format.") }
            // Ledge passes the text; it's shown only when the user chose to.
            let showsText = await choice.value && request.showPreview
            return NotificationBannerResponse(request: NotificationBannerRequest(title: request.title, body: showsText ? request.body : "",
                                                                                 showPreview: showsText))
        }
        return handlers
    }

    /// One bounded request, for the protocol-1 path older Ledge builds use.
    public static func respond(to input: Data) throws -> Data {
        guard input.count <= 65_536,
              let request = try? JSONDecoder().decode(NotificationBannerRequest.self, from: input),
              request.protocolVersion == 1 else { throw Failure.invalidRequest }
        return try JSONEncoder().encode(NotificationBannerResponse(request: request))
    }
}

/// The user's choice, as the session last saw it.
private actor Choice {
    private(set) var value = false
    func set(_ value: Bool) { self.value = value }
}
