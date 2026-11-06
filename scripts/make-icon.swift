// Draws Clipback's app icon into Resources/AppIcon.icns and docs/images/icon.png: a small deck of review cards on
// a teal tile, the top card with a quote mark and a highlighted line. At 32 px and below a simpler deck is drawn
// (two cards, no grey line) so it still reads in Finder's list view and Spotlight.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Renders the icon at `pixels` square. Everything is laid out on Apple's 1024 grid, y pointing down.
func render(_ pixels: Int, simple: Bool) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(pixels) / 1024
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: k, y: -k)
    ctx.interpolationQuality = .high

    // Shadows are set in device pixels and point up, so they're scaled and flipped here.
    func shadow(dy: CGFloat, blur: CGFloat, opacity: CGFloat) {
        ctx.setShadow(offset: CGSize(width: 0, height: -dy * k), blur: blur * k, color: color(0x000000, opacity))
    }
    func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // The tile: Apple's 824-point rounded square with its drop shadow, a teal gradient and a soft top sheen.
    let tile = roundedRect(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
    ctx.saveGState()
    shadow(dy: 10, blur: 24, opacity: 0.30)
    ctx.addPath(tile); ctx.setFillColor(color(0x0A7C6A)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
    let teal = CGGradient(colorsSpace: rgb, colors: [color(0x2CC8AB), color(0x0A7C6A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(teal, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

    // The deck, nudged a little below centre so the stack looks balanced.
    ctx.translateBy(x: 0, y: 18)
    let card = CGRect(x: 282, y: 250, width: 460, height: 560)
    func rotated(_ degrees: CGFloat, _ draw: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: 512, y: 600)
        ctx.rotate(by: degrees * .pi / 180)
        ctx.translateBy(x: -512, y: -600)
        draw()
        ctx.restoreGState()
    }
    let backCards: [(CGFloat, UInt32)] = simple ? [(-7, 0xCDEEE6)] : [(-15, 0x7FCDBE), (-7, 0xCDEEE6)]
    for (angle, fill) in backCards {
        rotated(angle) {
            shadow(dy: 6, blur: 16, opacity: 0.18)
            ctx.addPath(roundedRect(card, 54)); ctx.setFillColor(color(fill)); ctx.fillPath()
        }
    }

    // The top card, drawn as one layer so its shadow falls once, under the whole card.
    rotated(4) {
        shadow(dy: 14, blur: 32, opacity: 0.22)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(roundedRect(card, 54)); ctx.setFillColor(.white); ctx.fillPath()

        // An opening quote mark in Georgia Bold, drawn upright in this flipped context.
        let size: CGFloat = simple ? 400 : 360
        let font = CTFontCreateWithName("Georgia-Bold" as CFString, size, nil)
        let quote = NSAttributedString(string: "\u{201C}", attributes: [.font: font, .foregroundColor: color(0x14917D)])
        let line = CTLineCreateWithAttributedString(quote)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: 322, y: simple ? 600 : 540)
        CTLineDraw(line, ctx)
        ctx.restoreGState()

        // A yellow highlight behind a dark line of text, the way clips are highlighted in the app.
        let highlightY: CGFloat = simple ? 600 : 572
        ctx.addPath(roundedRect(CGRect(x: 312, y: highlightY, width: 400, height: simple ? 110 : 92), 20))
        ctx.setFillColor(color(0xFFD43B)); ctx.fillPath()
        let textBar = simple ? CGRect(x: 340, y: highlightY + 40, width: 320, height: 32)
                             : CGRect(x: 340, y: highlightY + 31, width: 334, height: 30)
        ctx.addPath(roundedRect(textBar, textBar.height / 2)); ctx.setFillColor(color(0x23413C)); ctx.fillPath()
        if !simple {
            ctx.addPath(roundedRect(CGRect(x: 340, y: highlightY + 128, width: 250, height: 30), 15))
            ctx.setFillColor(color(0xC5D6D2)); ctx.fillPath()
        }
        ctx.endTransparencyLayer()
    }
    ctx.translateBy(x: 0, y: -18)

    let sheen = CGGradient(colorsSpace: rgb, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 512), options: [])
    ctx.restoreGState()

    // A hairline edge, so the tile holds its shape on light backgrounds.
    ctx.addPath(tile); ctx.setStrokeColor(color(0x000000, 0.10)); ctx.setLineWidth(2); ctx.strokePath()
    return ctx.makeImage()!
}

func png(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try png(render(pixels, simple: pixels <= 32)).write(to: iconset.appending(path: name))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
try png(render(256, simple: false)).write(to: URL(fileURLWithPath: "docs/images/icon.png"))
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/images/icon.png" : "iconutil failed")
