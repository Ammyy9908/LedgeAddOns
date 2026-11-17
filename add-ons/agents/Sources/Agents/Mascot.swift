import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Claude Code's pixel mascot, drawn once as a PNG for the page: the add-on ships as a single binary, with no files
/// beside it to load a picture from.
enum Mascot {
    /// `#` is the body; the gaps are its eyes and the space between its legs.
    private static let pixels = [
        ".##########.",
        ".##.####.##.",
        "###.####.###",
        ".##########.",
        ".#.#....#.#.",
        ".#.#....#.#.",
    ]

    static let png: Data = {
        let cell = 8, width = 12, height = 12
        let top = (height - pixels.count) / 2
        guard let context = CGContext(data: nil, width: width * cell, height: height * cell, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Data() }
        context.setFillColor(CGColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1))
        for (row, line) in pixels.enumerated() {
            for (column, pixel) in line.enumerated() where pixel == "#" {
                // Core Graphics counts rows from the bottom.
                context.fill(CGRect(x: column * cell, y: (height - 1 - top - row) * cell, width: cell, height: cell))
            }
        }
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : Data()
    }()
}
