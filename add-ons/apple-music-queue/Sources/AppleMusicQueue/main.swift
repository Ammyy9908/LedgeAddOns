import Foundation
import LedgeKit
import QueueBridge

struct Request: Decodable { let protocolVersion: Int; let action: String }
let input = try FileHandle.standardInput.read(upToCount: 4097) ?? Data()
guard input.count <= 4096,
      let request = try? JSONDecoder().decode(Request.self, from: input),
      request.protocolVersion == 1, request.action == "readQueue" else { exit(1) }
try FileHandle.standardOutput.write(contentsOf: LedgeReadMusicQueue())
