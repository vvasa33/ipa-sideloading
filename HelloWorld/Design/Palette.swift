import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct AlbumPalette {
    var primary: Color
    var secondary: Color
    var tertiary: Color

    static let fallback = AlbumPalette(
        primary: Color(red: 0.36, green: 0.38, blue: 0.92),
        secondary: Color(red: 0.12, green: 0.62, blue: 0.58),
        tertiary: Color(red: 0.93, green: 0.42, blue: 0.36)
    )
}

enum ImageSizing {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func fitted(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let largest = max(pixelWidth, pixelHeight)
        guard largest > maxPixel, largest > 0 else { return image }
        let ratio = maxPixel / largest
        let size = CGSize(width: max(1, pixelWidth * ratio), height: max(1, pixelHeight * ratio))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func blurredBackdrop(from image: UIImage) -> UIImage {
        let tiny = fitted(image, maxPixel: 64)
        guard let cgImage = tiny.cgImage else { return tiny }
        let input = CIImage(cgImage: cgImage)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input
        filter.radius = 12
        guard let output = filter.outputImage else { return tiny }
        let cropped = output.cropped(to: input.extent)
        guard let result = context.createCGImage(cropped, from: cropped.extent) else { return tiny }
        return UIImage(cgImage: result)
    }
}

enum PaletteExtractor {
    static func extract(from image: UIImage) -> AlbumPalette {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let cgImage = image.cgImage,
              let context = CGContext(
                data: &pixels,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
              ) else {
            return .fallback
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var vivid: [Swatch] = []
        var calm: [Swatch] = []
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = CGFloat(pixels[index + 3]) / 255
            guard alpha > 0.85 else { continue }
            let red = clamp(CGFloat(pixels[index]) / 255 / alpha)
            let green = clamp(CGFloat(pixels[index + 1]) / 255 / alpha)
            let blue = clamp(CGFloat(pixels[index + 2]) / 255 / alpha)
            let maxChannel = max(red, green, blue)
            let minChannel = min(red, green, blue)
            let saturation = maxChannel == 0 ? 0 : (maxChannel - minChannel) / maxChannel
            let luminance = (red + green + blue) / 3
            guard luminance > 0.12, luminance < 0.92 else { continue }
            let swatch = Swatch(
                red: red,
                green: green,
                blue: blue,
                score: saturation * (1 - abs(luminance - 0.5))
            )
            if saturation > 0.18 {
                vivid.append(swatch)
            } else if luminance > 0.2, luminance < 0.8 {
                calm.append(Swatch(red: red, green: green, blue: blue, score: 1 - abs(luminance - 0.45)))
            }
        }

        let pool = vivid.isEmpty ? calm : vivid
        guard !pool.isEmpty else { return .fallback }
        let ranked = pool.sorted { $0.score > $1.score }
        var picked: [Swatch] = []
        for swatch in ranked where picked.allSatisfy({ distance($0, swatch) > 0.22 }) {
            picked.append(swatch)
            if picked.count == 3 { break }
        }
        if picked.isEmpty, let first = ranked.first {
            picked = [first]
        }
        while picked.count < 3 {
            picked.append(picked[picked.count - 1])
        }
        return AlbumPalette(
            primary: picked[0].color,
            secondary: picked[1].color,
            tertiary: picked[2].color
        )
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }

    private static func distance(_ lhs: Swatch, _ rhs: Swatch) -> CGFloat {
        let dr = lhs.red - rhs.red
        let dg = lhs.green - rhs.green
        let db = lhs.blue - rhs.blue
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    private struct Swatch {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var score: CGFloat
        var color: Color { Color(red: red, green: green, blue: blue) }
    }
}
