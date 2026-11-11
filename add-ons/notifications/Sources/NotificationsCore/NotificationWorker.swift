import Foundation
import LedgeKit

public enum NotificationWorker {
    public enum Failure: Error { case invalidRequest }

    /// The session's handlers: Ledge sends each visible banner as a `banner` request while mirroring is on.
    public static func handlers() -> AddOnHandlers {
        var handlers = AddOnHandlers()
        handlers.on("banner") { (request: NotificationBannerRequest) -> NotificationBannerResponse in
            guard request.protocolVersion == 1 else { throw AddOnError("Unsupported banner format.") }
            return NotificationBannerResponse(request: request)
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
