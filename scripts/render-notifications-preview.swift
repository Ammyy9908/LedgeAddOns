// Standalone illustrative artwork generator; does not capture or control any app.
import AppKit
import AVFoundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let width = 960, height = 540
func draw(_ context: CGContext, progress: Double) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.20, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    func text(_ value: String, _ rect: NSRect, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight = .regular) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    }
    text("Notifications", NSRect(x: 48, y: 58, width: 500, height: 38), 28, .white, .semibold)
    text("Illustrative preview · Example notification", NSRect(x: 48, y: 28, width: 800, height: 24), 15, .lightGray)
    let w = 240 + 320 * progress, h = 36 + 220 * progress
    let rect = NSRect(x: (960 - w) / 2, y: 540 - h, width: w, height: h)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26).fill()
    NSRect(x: rect.minX, y: rect.maxY - 30, width: rect.width, height: 30).fill()
    if progress > 0.9 {
        text("Notification", NSRect(x: rect.minX + 28, y: rect.maxY - 80, width: 400, height: 24), 16, .white, .semibold)
        text("×", NSRect(x: rect.maxX - 48, y: rect.maxY - 80, width: 24, height: 24), 20, .white)
        text("Calendar: Your next meeting starts in 10 minutes.\n\nRead the message here, then dismiss it when you’re ready.", NSRect(x: rect.minX + 28, y: rect.minY + 24, width: rect.width - 56, height: rect.height - 120), 20, .white)
    }
    NSGraphicsContext.restoreGraphicsState()
}
func frame(_ progress: Double) -> CVPixelBuffer {
    var pixel: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                       [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pixel)
    let result = pixel!
    CVPixelBufferLockBaseAddress(result, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(result), width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(result), space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
    draw(context, progress: progress)
    if progress == 1, !FileManager.default.fileExists(atPath: destination.appendingPathComponent("Preview.png").path) {
        let image = NSBitmapImageRep(cgImage: context.makeImage()!)
        try! image.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("Preview.png"))
    }
    CVPixelBufferUnlockBaseAddress(result, [])
    return result
}
let writer = try AVAssetWriter(outputURL: destination.appendingPathComponent("Demo.mp4"), fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
for index in 0..<120 {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    let time = Double(index) / 24
    let linear = min(1, max(0, (time - 0.4) / 0.65))
    let progress = linear * linear * (3 - 2 * linear)
    guard adaptor.append(frame(progress), withPresentationTime: CMTime(value: Int64(index), timescale: 24)) else { fatalError("Video encoding failed") }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("Video encoding did not complete") }
print("Generated labeled example PNG and MP4 previews.")
