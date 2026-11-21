import Foundation
import ImageIO
import Vision
import Testing
@testable import DeveloperToolsCore

@Test func base64PreservesUnicodeAndRejectsMalformedInput() throws {
    let text = "Hello, Ledge! 👋 नमस्ते"
    let encoded = try ToolEngine.run(.base64, operation: "encode", input: text).text
    #expect(try ToolEngine.run(.base64, operation: "decode", input: encoded).text == text)
    #expect(throws: ToolError.self) { try ToolEngine.run(.base64, operation: "decode", input: "not%base64") }
}

@Test func jsonFormattingAndMinifyingKeepTheSameValues() throws {
    let text = "{\"name\":\"Ledge\",\"enabled\":true,\"count\":3}"
    let formatted = try ToolEngine.run(.json, operation: "format", input: text).text
    #expect(formatted.contains("\n"))
    let compact = try ToolEngine.run(.json, operation: "minify", input: formatted).text
    #expect(!compact.contains("\n"))
    #expect((try JSONSerialization.jsonObject(with: Data(compact.utf8)) as? NSDictionary) == (try JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary))
    #expect(throws: ToolError.self) { try ToolEngine.run(.json, operation: "format", input: "{broken") }
}

@Test func hashesMatchKnownVectors() throws {
    #expect(try ToolEngine.run(.hash, operation: "sha256", input: "abc").text == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(try ToolEngine.run(.hash, operation: "md5", input: "abc").text == "900150983cd24fb0d6963f7d28e17f72")
}

@Test func jsonPreservesLargeNumberTokensAndBoundsExpandedOutput() throws {
    let input = "{\"number\":900719925474099312345,\"empty\":[],\"text\":\"a \\\"b\\\"\"}"
    let formatted = try ToolEngine.run(.json, operation: "format", input: input).text
    #expect(formatted.contains("900719925474099312345"))
    #expect(try ToolEngine.run(.json, operation: "minify", input: formatted).text == input)
    let deep = String(repeating: "[", count: 60) + Array(repeating: "1", count: 1000).joined(separator: ",") + String(repeating: "]", count: 60)
    #expect(throws: ToolError.self) { try ToolEngine.run(.json, operation: "format", input: deep) }
}

@Test func urlEncodingIsForComponentsAndDoesNotTurnPlusIntoSpace() throws {
    let text = "a+b & café/🙂"
    let encoded = try ToolEngine.run(.url, operation: "encode", input: text).text
    #expect(encoded.hasPrefix("a%2Bb%20%26%20caf%C3%A9%2F"))
    #expect(try ToolEngine.run(.url, operation: "decode", input: encoded).text == text)
    #expect(try ToolEngine.run(.url, operation: "decode", input: "a+b").text == "a+b")
    #expect(throws: ToolError.self) { try ToolEngine.run(.url, operation: "decode", input: "%ZZ") }
}

@Test func jwtDecodingNeverClaimsTheSignatureWasVerified() throws {
    let header = Data("{\"alg\":\"none\",\"typ\":\"JWT\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
    let payload = Data("{\"sub\":\"test-user\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
    let result = try ToolEngine.run(.jwt, operation: "decode", input: header + "." + payload + ".")
    #expect(result.note?.contains("not verified") == true)
    #expect(result.text.contains("test-user"))
    #expect(throws: ToolError.self) { try ToolEngine.run(.jwt, operation: "decode", input: "broken.token") }
}

@Test func uuidGeneratorMakesDistinctVersionFourIdentifiers() throws {
    let a = try ToolEngine.run(.uuid, operation: "generate", input: "").text
    let b = try ToolEngine.run(.uuid, operation: "generate", input: "").text
    #expect(UUID(uuidString: a) != nil && a != b)
    #expect(Array(a)[14] == "4")
}

@Test func qrOutputIsAScannablePNGWithTheOriginalMessage() throws {
    let message = "https://www.tryledge.app/?tool=qr"
    let result = try ToolEngine.run(.qr, operation: "generate", input: message)
    let png = try #require(result.image)
    #expect(png.count <= 32_768)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let request = VNDetectBarcodesRequest()
    try VNImageRequestHandler(cgImage: image).perform([request])
    #expect(request.results?.first?.payloadStringValue == message)
}

@Test func inputLimitsAndUnknownOperationsFailWithoutEchoingUserText() {
    for (tool, operation, input) in [(DeveloperTool.base64, "encode", String(repeating: "x", count: 8_193)), (.qr, "generate", String(repeating: "x", count: 1_801)), (.hash, "shell", "private-value")] {
        #expect(throws: ToolError.self) { try ToolEngine.run(tool, operation: operation, input: input) }
    }
}
