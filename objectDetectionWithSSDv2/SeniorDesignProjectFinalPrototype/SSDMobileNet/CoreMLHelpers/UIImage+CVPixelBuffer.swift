import UIKit
import CoreVideo
import CoreImage
import VideoToolbox

// MARK: - CVPixelBuffer -> CGImage helpers
extension UIImage {
    /// Create a CGImage from a CVPixelBuffer (RGB only; not grayscale).
    /// Returns nil if VT can't create a CGImage for this buffer format.
    static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        // NOTE: modern signature requires labeled params
        let status = VTCreateCGImageFromCVPixelBuffer(
            pixelBuffer,
            options: nil,
            imageOut: &cgImage
        )
        guard status == noErr else { return nil }
        return cgImage
    }
}

// MARK: - Convenience initializers
extension UIImage {

    /// Create a UIImage from a CVPixelBuffer (RGB only), keeping default scale/orientation.
    public convenience init?(pixelBuffer: CVPixelBuffer) {
        guard let cgImage = UIImage.cgImage(from: pixelBuffer) else { return nil }
        self.init(cgImage: cgImage)
    }

    /// Create a UIImage from a CVPixelBuffer using a Core Image context (works broadly).
    public convenience init?(pixelBuffer: CVPixelBuffer, context: CIContext) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(
            x: 0, y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        guard let cgImage = context.createCGImage(ciImage, from: rect) else { return nil }
        self.init(cgImage: cgImage)
    }

    /// Build a UIImage from RGBA byte array.
    @nonobjc public class func fromByteArrayRGBA(
        _ bytes: [UInt8],
        width: Int,
        height: Int,
        scale: CGFloat = 1.0,
        orientation: UIImage.Orientation = .up
    ) -> UIImage? {

        var image: UIImage?
        bytes.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            let bitmapInfo = CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue)

            if let ctx = CGContext(
                data: UnsafeMutableRawPointer(mutating: base),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ), let cgImage = ctx.makeImage() {
                image = UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
            }
        }
        return image
    }

    /// Build a UIImage from grayscale byte array.
    @nonobjc public class func fromByteArrayGray(
        _ bytes: [UInt8],
        width: Int,
        height: Int,
        scale: CGFloat = 1.0,
        orientation: UIImage.Orientation = .up
    ) -> UIImage? {

        var image: UIImage?
        bytes.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            let colorSpace = CGColorSpaceCreateDeviceGray()
            let bytesPerRow = width

            if let ctx = CGContext(
                data: UnsafeMutableRawPointer(mutating: base),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let cgImage = ctx.makeImage() {
                image = UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
            }
        }
        return image
    }
}

