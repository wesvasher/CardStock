import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Edits images in the site's media folder with macOS's own tools: Core
/// Image for rotating, flipping, cropping, Auto Enhance and photo filters,
/// and Vision for removing the background. Edits replace the full-size file
/// and rebuild its smaller inline version.
enum ImageEditor {
    enum Edit: Equatable, Sendable {
        case rotateLeft, rotateRight, flipHorizontal, flipVertical
        case autoEnhance
        case filter(PhotoFilter)
        case crop(AspectRatio)
    }

    /// Apple's built-in photo effects (the same ones as in Photos).
    enum PhotoFilter: String, CaseIterable, Sendable {
        case mono = "CIPhotoEffectMono"
        case noir = "CIPhotoEffectNoir"
        case tonal = "CIPhotoEffectTonal"
        case chrome = "CIPhotoEffectChrome"
        case fade = "CIPhotoEffectFade"
        case instant = "CIPhotoEffectInstant"
        case process = "CIPhotoEffectProcess"
        case transfer = "CIPhotoEffectTransfer"

        var name: String {
            switch self {
            case .mono: "Mono"
            case .noir: "Noir"
            case .tonal: "Tonal"
            case .chrome: "Chrome"
            case .fade: "Fade"
            case .instant: "Instant"
            case .process: "Process"
            case .transfer: "Transfer"
            }
        }
    }

    enum AspectRatio: String, CaseIterable, Sendable {
        case square = "Square"
        case fourThree = "4:3"
        case threeTwo = "3:2"
        case sixteenNine = "16:9"

        /// Width divided by height, for a landscape crop. Portrait images
        /// get the same shape turned upright.
        var ratio: CGFloat {
            switch self {
            case .square: 1
            case .fourThree: 4.0 / 3
            case .threeTwo: 3.0 / 2
            case .sixteenNine: 16.0 / 9
            }
        }
    }

    /// Formats that can be edited and saved again.
    static func canEdit(_ path: String) -> Bool {
        ["jpg", "jpeg", "png", "heic", "tif", "tiff"].contains((path as NSString).pathExtension.lowercased())
    }

    private static let context = CIContext()

    // MARK: Editing in place

    /// Applies an edit to the full-size file, then rebuilds the inline
    /// `-small` version (when there is one) from the result.
    static func apply(_ edit: Edit, to url: URL, small: URL?) throws {
        guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw SiteError("“\(url.lastPathComponent)” couldn't be read as an image.")
        }
        let output = try transform(input, edit)
        try save(output, to: url)
        if let small { try rebuildSmall(from: url, to: small) }
    }

    static func transform(_ image: CIImage, _ edit: Edit) throws -> CIImage {
        var result: CIImage
        switch edit {
        case .rotateLeft: result = image.oriented(.left)
        case .rotateRight: result = image.oriented(.right)
        case .flipHorizontal: result = image.oriented(.upMirrored)
        case .flipVertical: result = image.oriented(.downMirrored)
        case .autoEnhance:
            result = image
            for filter in image.autoAdjustmentFilters(options: [.redEye: false]) {
                filter.setValue(result, forKey: kCIInputImageKey)
                result = filter.outputImage ?? result
            }
        case .filter(let effect):
            guard let filter = CIFilter(name: effect.rawValue) else { throw SiteError("The \(effect.name) filter isn't available.") }
            filter.setValue(image, forKey: kCIInputImageKey)
            result = filter.outputImage ?? image
        case .crop(let aspect):
            let extent = image.extent
            let portrait = extent.height > extent.width
            let ratio = portrait ? 1 / aspect.ratio : aspect.ratio
            var width = extent.width, height = extent.width / ratio
            if height > extent.height {
                height = extent.height
                width = height * ratio
            }
            let rect = CGRect(x: extent.midX - width / 2, y: extent.midY - height / 2,
                              width: width, height: height).integral
            result = image.cropped(to: rect)
        }
        // Keep the picture's corner at 0,0 so it renders in full.
        return result.transformed(by: CGAffineTransform(translationX: -result.extent.minX, y: -result.extent.minY))
    }

    /// Writes an image in the file's own format, without metadata.
    static func save(_ image: CIImage, to url: URL) throws {
        let type = UTType(filenameExtension: url.pathExtension) ?? .jpeg
        guard let cgImage = context.createCGImage(image, from: image.extent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw SiteError("Couldn't save “\(url.lastPathComponent)”.") }
        var properties: [CFString: Any] = [:]
        if type.conforms(to: .jpeg) || type.conforms(to: .heic) {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw SiteError("Couldn't save “\(url.lastPathComponent)”.") }
    }

    /// Makes the inline version again from the full-size file.
    static func rebuildSmall(from large: URL, to small: URL) throws {
        guard let source = CGImageSourceCreateWithURL(large as CFURL, nil) else { return }
        let type = UTType(filenameExtension: small.pathExtension) ?? .jpeg
        try ImageImporter.write(source, maxPixels: ImageImporter.inlineMaxPixels, type: type, to: small)
    }

    // MARK: Removing the background

    /// Lifts the subject out of the photo (as Photos and Finder do) and saves
    /// it as a new PNG with a transparent background: `name-cutout.png`,
    /// plus an inline version when the image is large. Returns the new
    /// full-size file. The original isn't changed.
    static func removeBackground(from url: URL) throws -> URL {
        guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              let cgImage = context.createCGImage(input, from: input.extent)
        else { throw SiteError("“\(url.lastPathComponent)” couldn't be read as an image.") }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw SiteError("CardStock couldn't find a subject to keep in this photo.")
        }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                    croppedToInstancesExtent: false)
        let cutout = CIImage(cvPixelBuffer: buffer)

        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var name = "\(base)-cutout"
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: "\(name).png").path) {
            name = "\(base)-cutout-\(n)"
            n += 1
        }
        let large = folder.appending(path: "\(name).png")
        try save(cutout, to: large)
        if max(cutout.extent.width, cutout.extent.height) > CGFloat(ImageImporter.inlineMaxPixels) {
            try rebuildSmall(from: large, to: folder.appending(path: "\(name)-small.png"))
        }
        return large
    }
}
