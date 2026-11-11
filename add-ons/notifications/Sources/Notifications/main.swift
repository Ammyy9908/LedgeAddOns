import Foundation
import LedgeKit
import NotificationsCore

// A long-lived session: Ledge keeps this running while mirroring is on and sends each banner as a request.
// Nothing here logs notification contents.
exit(await AddOnSession.run(id: "notifications", handlers: NotificationWorker.handlers()))
