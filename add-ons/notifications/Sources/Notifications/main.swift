import Foundation
import NotificationsCore

// One bounded request. No logging of notification contents.
var input = Data()
do {
    while let bytes = try FileHandle.standardInput.read(upToCount: min(4096, 65_537 - input.count)), !bytes.isEmpty {
        input.append(bytes)
        if input.count > 65_536 { break }
    }
    try FileHandle.standardOutput.write(contentsOf: NotificationWorker.respond(to: input))
} catch { exit(1) }
