import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CardStock

struct ImageEditorTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-edit-\(UUID().uuidString)")

    private func makeImage(_ name: String, width: Int, height: Int) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = dir.appending(path: name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func size(_ url: URL) -> (Int, Int) {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        return (props[kCGImagePropertyPixelWidth] as! Int, props[kCGImagePropertyPixelHeight] as! Int)
    }

    @Test func rotatesCropsAndRebuildsTheInlineVersion() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let large = try makeImage("photo.jpg", width: 3000, height: 1500)
        let small = try makeImage("photo-small.jpg", width: 1200, height: 600)

        try ImageEditor.apply(.rotateRight, to: large, small: small)
        #expect(size(large) == (1500, 3000))
        #expect(size(small) == (600, 1200))   // rebuilt from the rotated image

        try ImageEditor.apply(.crop(.square), to: large, small: nil)
        #expect(size(large) == (1500, 1500))

        try ImageEditor.apply(.crop(.sixteenNine), to: large, small: nil)
        let (w, h) = size(large)
        #expect(w == 1500 && abs(h - 844) <= 1)
    }

    @Test func filtersAndEnhanceKeepTheSize() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try makeImage("photo.jpg", width: 400, height: 300)
        try ImageEditor.apply(.filter(.noir), to: url, small: nil)
        try ImageEditor.apply(.autoEnhance, to: url, small: nil)
        try ImageEditor.apply(.flipHorizontal, to: url, small: nil)
        #expect(size(url) == (400, 300))
    }

    @Test func onlyEditableFormats() {
        #expect(ImageEditor.canEdit("media/a.JPG"))
        #expect(ImageEditor.canEdit("media/a.png"))
        #expect(!ImageEditor.canEdit("media/a.gif"))
        #expect(!ImageEditor.canEdit("media/a.svg"))
    }
}
