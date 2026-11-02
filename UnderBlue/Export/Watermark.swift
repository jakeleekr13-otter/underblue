import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// The mark on free exports: the app icon and "UnderBlue" in the bottom-right corner (Jake, 2 Nov 2026).
/// Pro exports never carry it. Free exports are SDR only, so the mark is drawn in sRGB.
enum Watermark {
    /// The icon's side as a share of the image's short side.
    static let heightShare: CGFloat = 0.04
    /// The gap to the right and bottom edges, as a share of the short side.
    static let marginShare: CGFloat = 0.03
    static let opacity: CGFloat = 0.9

    /// `image` with the mark over its bottom-right corner, at the same extent.
    static func apply(to image: CIImage) -> CIImage {
        guard let mark = mark(for: image.extent) else { return image }
        return mark.composited(over: image).cropped(to: image.extent)
    }

    /// The mark alone, placed for an image with this extent. A video makes it once and puts it over every frame.
    static func mark(for extent: CGRect) -> CIImage? {
        let short = min(extent.width, extent.height)
        guard short >= 64, let drawn = draw(height: max(16, (short * heightShare).rounded())) else { return nil }
        let margin = (short * marginShare).rounded()
        // Core Image's origin is bottom left, like the bitmap's. The padding holds the shadow.
        let x = extent.maxX - margin - CGFloat(drawn.image.width) + drawn.padding
        let y = extent.minY + margin - drawn.padding
        return CIImage(cgImage: drawn.image).transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    /// The icon colours (UnderBlue/Resources/AppIcon.icon): background fill and wave stroke.
    private static let background = CGColor(srgbRed: 0.03137, green: 0.10980, blue: 0.13333, alpha: 1)
    private static let wave = CGColor(srgbRed: 0x6A / 255.0, green: 0xE6 / 255.0, blue: 0xC8 / 255.0, alpha: 1)

    /// Icon of side `height`, a gap, then the name. `padding` is the empty border on every side.
    private static func draw(height h: CGFloat) -> (image: CGImage, padding: CGFloat)? {
        guard let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, h * 0.62, nil) else { return nil }
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let text = NSAttributedString(string: "UnderBlue", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): white,
        ])
        let line = CTLineCreateWithAttributedString(text)
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let padding = (h * 0.2).rounded(.up), gap = (h * 0.28).rounded()
        let width = Int((padding + h + gap + textWidth + padding).rounded(.up)), height = Int((padding + h + padding).rounded(.up))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setAlpha(opacity)
        // A soft dark shadow keeps the white name readable over bright water and sand.
        context.setShadow(offset: CGSize(width: 0, height: -h * 0.03), blur: h * 0.12, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
        drawIcon(in: CGRect(x: padding, y: padding, width: h, height: h), context: context)
        context.textPosition = CGPoint(x: padding + h + gap, y: padding + (h - CTFontGetCapHeight(font)) / 2)
        CTLineDraw(line, context)
        guard let image = context.makeImage() else { return nil }
        return (image, padding)
    }

    /// The app icon: three waves y = c + 45 sin(2πx / 540 − 2.7925) for x in 230...794, on a 1024 canvas
    /// (fit to the SVG layers within 0.005 px).
    private static func drawIcon(in rect: CGRect, context: CGContext) {
        let scale = rect.width / 1024
        // One layer, so the shadow and the opacity apply to the whole icon, not to each wave.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil))
        context.setFillColor(background)
        context.fillPath()
        context.setStrokeColor(wave)
        context.setLineWidth(44 * scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for centre in [342.0, 502.0, 662.0] {
            let path = CGMutablePath()
            for step in 0...282 {
                let x = 230.0 + Double(step) * 2
                let y = centre + 45 * sin(2 * .pi * x / 540 - 2.7925)
                let point = CGPoint(x: rect.minX + x * scale, y: rect.minY + (1024 - y) * scale)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.addPath(path)
        }
        context.strokePath()
        context.endTransparencyLayer()
    }
}
