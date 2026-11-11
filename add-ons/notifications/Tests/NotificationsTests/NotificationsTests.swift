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

@Test func sessionAnswersBannerRequests() async throws {
    let request = NotificationBannerRequest(title: "Calendar", body: "Your meeting starts soon.", showPreview: false)
    let messages: [SessionMessage] = [
        .hello(protocolVersion: 2, apiLevel: SessionProtocol.apiLevel, addOnID: "notifications", generation: 1),
        .request(id: 1, method: SessionProtocol.Method.activate, params: .null),
        .request(id: 2, method: "banner", params: try JSONValue(encoding: request))
    ]
    let input = AsyncThrowingStream<Data, Error> { continuation in
        for message in messages { continuation.yield(try! JSONEncoder().encode(message)) }
    }
    let replies = Replies()
    let session = Task {
        await AddOnSession.run(id: "notifications", handlers: NotificationWorker.handlers(), input: input) { line in
            await replies.add(try! JSONDecoder().decode(SessionMessage.self, from: line.dropLast()))
        }
    }
    for _ in 0..<100 where await replies.all.count < 3 { try await Task.sleep(nanoseconds: 10_000_000) }
    session.cancel()
    let expected = try JSONValue(encoding: NotificationBannerResponse(request: request))
    #expect(await replies.all.contains(.response(id: 2, result: expected, error: nil)))
}

private actor Replies {
    var all: [SessionMessage] = []
    func add(_ message: SessionMessage) { all.append(message) }
}
