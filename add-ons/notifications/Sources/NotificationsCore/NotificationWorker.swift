import Foundation
import LedgeKit

public enum NotificationWorker {
    public enum Failure: Error { case invalidRequest }
    public static func respond(to input: Data) throws -> Data {
        guard input.count <= 65_536,
              let request = try? JSONDecoder().decode(NotificationBannerRequest.self, from: input),
              request.protocolVersion == 1 else { throw Failure.invalidRequest }
        return try JSONEncoder().encode(NotificationBannerResponse(request: request))
    }
}
