import Foundation
import Testing
import LedgeKit
@testable import NotificationsCore

@Test func preservesNotificationAndHidesPrivateBody() throws {
    for preview in [true, false] {
        let request = NotificationBannerRequest(title: "Calendar", body: "Your meeting starts soon.", showPreview: preview)
        let response = try JSONDecoder().decode(NotificationBannerResponse.self,
            from: NotificationWorker.respond(to: JSONEncoder().encode(request)))
        #expect(response.text == (preview ? "Calendar: Your meeting starts soon." : "Calendar: New notification"))
    }
}
@Test func rejectsMalformedUnsupportedAndOversizedRequests() throws {
    for input in [Data("{}".utf8), Data(repeating: 32, count: 65_537),
                  Data(#"{"protocolVersion":99,"title":"Test","body":"Example","showPreview":true}"#.utf8)] {
        #expect(throws: NotificationWorker.Failure.self) { try NotificationWorker.respond(to: input) }
    }
}
