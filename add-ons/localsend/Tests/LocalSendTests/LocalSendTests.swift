import Foundation
import Testing
@testable import LocalSendCore

// MARK: Names a sender picks

@Test func sentNamesCantLeaveTheFolder() {
    let folder = URL(fileURLWithPath: "/Users/sam/Downloads")
    for hostile in ["../../.zshrc", "/etc/passwd", "a/../../b", "..", "./.ssh/id_rsa", "~/x", "a\\..\\..\\b"] {
        let place = SafePath.destination(for: hostile, in: folder) { _ in false }
        #expect(place.standardizedFileURL.path.hasPrefix(folder.path + "/"), "\(hostile) → \(place.path)")
        #expect(!place.path.contains("/../"))
    }
    #expect(SafePath.components(of: "../../.zshrc") == ["zshrc"])
    #expect(SafePath.components(of: "") == ["Received file"])
    #expect(SafePath.components(of: "a:b\u{0}c.txt") == ["a-bc.txt"])
}

@Test func foldersKeepTheirShapeAndTakenNamesGetANumber() {
    let folder = URL(fileURLWithPath: "/Users/sam/Downloads")
    #expect(SafePath.destination(for: "Trip/Day 1/photo.jpg", in: folder) { _ in false }.path == "/Users/sam/Downloads/Trip/Day 1/photo.jpg")
    let taken: Set<String> = ["/Users/sam/Downloads/photo.jpg", "/Users/sam/Downloads/photo (1).jpg"]
    #expect(SafePath.destination(for: "photo.jpg", in: folder) { taken.contains($0.path) }.lastPathComponent == "photo (2).jpg")
    #expect(SafePath.destination(for: "README", in: folder) { $0.lastPathComponent == "README" }.lastPathComponent == "README (1)")
    #expect(SafePath.topItem(of: URL(fileURLWithPath: "/Users/sam/Downloads/Trip/Day 1/photo.jpg"), in: folder).path == "/Users/sam/Downloads/Trip")
}

@Test func longNamesAreShortenedKeepingTheExtension() {
    let name = String(repeating: "é", count: 200) + ".jpeg"
    let short = SafePath.components(of: name)[0]
    #expect(short.utf8.count <= 255)
    #expect(short.hasSuffix(".jpeg"))
}

// MARK: HTTP

@Test func aRequestHeadIsReadOnceItHasAllArrived() throws {
    let text = "POST /api/localsend/v2/upload?sessionId=s1&fileId=f%201&token=t HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhello"
    #expect(try HTTPRequestHead.parse(Data(text.prefix(30).utf8)) == nil)
    let (head, length) = try #require(try HTTPRequestHead.parse(Data(text.utf8)))
    #expect(head.method == "POST")
    #expect(head.path == "/api/localsend/v2/upload")
    #expect(head.query == ["sessionId": "s1", "fileId": "f 1", "token": "t"])
    #expect(head.body == .length(5))
    #expect(length == text.utf8.count - 5)
    #expect(throws: (any Error).self) { try HTTPRequestHead.parse(Data("nonsense\r\n\r\n".utf8)) }
    #expect(throws: (any Error).self) { try HTTPRequestHead.parse(Data(repeating: 65, count: HTTPRequestHead.maximumSize + 1)) }
}

@Test func chunkedBodiesDecodeHoweverTheBytesArrive() throws {
    let wire = Data("5\r\nhello\r\n7;ext=1\r\n, world\r\n0\r\n\r\n".utf8)
    for step in [1, 3, 7, wire.count] {
        var decoder = ChunkedDecoder()
        var out = Data()
        var index = 0
        while index < wire.count {
            out.append(try decoder.feed(wire.subdata(in: index..<min(index + step, wire.count))))
            index += step
        }
        #expect(String(decoding: out, as: UTF8.self) == "hello, world")
        #expect(decoder.isFinished)
    }
    var bad = ChunkedDecoder()
    #expect(throws: (any Error).self) { try bad.feed(Data("zz\r\n".utf8)) }
}

// MARK: The protocol

@Test func devicesDecodeAsLocalSendWritesThem() throws {
    let json = #"{"alias":"Nice Orange","version":"2.1","deviceModel":"Samsung","deviceType":"mobile","fingerprint":"ab12","port":53317,"protocol":"https","download":false,"announce":true}"#
    let info = try JSONDecoder().decode(DeviceInfo.self, from: Data(json.utf8))
    #expect(info.scheme == "https")
    #expect(info.announce == true)
    #expect(String(decoding: try JSONEncoder().encode(info), as: UTF8.self).contains(#""protocol":"https""#))
    // A register answer leaves most of it out.
    let short = try JSONDecoder().decode(DeviceInfo.self, from: Data(#"{"alias":"Phone"}"#.utf8))
    #expect(short.fingerprint == nil)
}

@Test func aMessageIsOneTextFileWithItsText() {
    let info = DeviceInfo(alias: "Phone", fingerprint: "F")
    let text = FileInfo(id: "1", fileName: "1.txt", size: 5, fileType: "text/plain", preview: "hello")
    #expect(PrepareUpload(info: info, files: ["1": text]).message == "hello")
    var file = text
    file.preview = nil
    #expect(PrepareUpload(info: info, files: ["1": file]).message == nil)
    #expect(PrepareUpload(info: info, files: ["1": text, "2": FileInfo(id: "2", fileName: "a", size: 1, fileType: "text/plain", preview: "x")]).message == nil)
}

@Test func malformedOffersAreRefused() {
    let info = DeviceInfo(alias: "Phone", fingerprint: "F")
    #expect(!PrepareUpload(info: info, files: [:]).isValid)
    #expect(!PrepareUpload(info: info, files: ["a": FileInfo(id: "b", fileName: "x", size: 1, fileType: "t")]).isValid)
    #expect(!PrepareUpload(info: info, files: ["a": FileInfo(id: "a", fileName: "x", size: -1, fileType: "t")]).isValid)
    #expect(PrepareUpload(info: info, files: ["a": FileInfo(id: "a", fileName: "x", size: 0, fileType: "t")]).isValid)
}

@Test func peersIgnoreThisMacAndExpire() {
    var list = PeerList(ownFingerprint: "MINE")
    let now = Date()
    let mine = list.saw(DeviceInfo(alias: "Me", fingerprint: "mine"), fingerprint: nil, host: "10.0.0.2", at: now)
    let pixel = list.saw(DeviceInfo(alias: "Pixel", fingerprint: "abc"), fingerprint: nil, host: "10.0.0.3", at: now)
    // Heard again with nothing new: the page needn't redraw.
    let again = list.saw(DeviceInfo(alias: "Pixel", fingerprint: "abc"), fingerprint: nil, host: "10.0.0.3", at: now)
    #expect(!mine && pixel && !again)
    #expect(list.peers["ABC"]?.url("upload", ["token": "t", "fileId": "f"])?.absoluteString == "https://10.0.0.3:53317/api/localsend/v2/upload?fileId=f&token=t")
    let early = list.expire(now: now.addingTimeInterval(60))
    let late = list.expire(now: now.addingTimeInterval(PeerList.lifetime + 1))
    #expect(!early && late)
    #expect(list.peers.isEmpty)
}

@Test func responsesCloseTheConnection() {
    let text = String(decoding: HTTPResponse.make(200, json: Data("{}".utf8)), as: UTF8.self)
    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Connection: close\r\n"))
    #expect(text.hasSuffix("\r\n\r\n{}"))
}
