import AppKit

/// The menubar glyph: the app icon's deck reduced to a template image, a solid card with a quote mark and a
/// highlighted line cut out of it, and a second card peeking out behind. macOS tints it for light, dark and paused.
enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let back = CGRect(x: 6.6, y: 1.2, width: 10.2, height: 13)
            let front = CGRect(x: 1.6, y: 4, width: 11.2, height: 13.4)

            ctx.addPath(CGPath(roundedRect: back, cornerWidth: 2.6, cornerHeight: 2.6, transform: nil))
            ctx.setStrokeColor(.black)
            ctx.setLineWidth(1.4)
            ctx.strokePath()

            // Clear a gap around the front card so the back card's outline stops short of it.
            let frontPath = CGPath(roundedRect: front, cornerWidth: 2.6, cornerHeight: 2.6, transform: nil)
            ctx.setBlendMode(.clear)
            ctx.addPath(frontPath); ctx.setLineWidth(3); ctx.strokePath()
            ctx.setBlendMode(.normal)
            ctx.addPath(frontPath); ctx.setFillColor(.black); ctx.fillPath()

            // Cut out an opening quote (two round dots with tails) at the top left, then two lines of text of
            // different lengths, so it reads as a card of writing rather than a face.
            ctx.setBlendMode(.clear)
            for x in [3.4, 6.3] {
                ctx.fillEllipse(in: CGRect(x: x, y: 7.0, width: 2.2, height: 2.2))
                let tail = CGMutablePath()
                tail.move(to: CGPoint(x: x + 0.1, y: 7.9))
                tail.addQuadCurve(to: CGPoint(x: x + 1.9, y: 5.8), control: CGPoint(x: x + 0.15, y: 6.1))
                ctx.addPath(tail); ctx.setLineWidth(1.0); ctx.setLineCap(.round); ctx.strokePath()
            }
            for line in [CGRect(x: 3.4, y: 11.0, width: 7.8, height: 2.0), CGRect(x: 3.4, y: 14.0, width: 4.6, height: 1.6)] {
                ctx.addPath(CGPath(roundedRect: line, cornerWidth: line.height / 2, cornerHeight: line.height / 2, transform: nil))
                ctx.fillPath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clipback"
        return image
    }
}
