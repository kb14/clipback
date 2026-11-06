import AppKit
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

/// An on-screen window, in global screen coordinates with the origin at the top-left of the main display.
struct ScreenWindow {
    var frame: CGRect
    var ownerPID: pid_t
    var ownerName: String
    var title: String?
}

/// Freezes a display into an image, lists windows, and crops pieces out of the frozen image.
@MainActor
enum ScreenGrabber {
    enum Failure: Error { case displayNotFound }

    static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The whole display at full resolution, without Clipback's own windows and without the cursor.
    static func captureDisplay(_ screen: NSScreen) async throws -> CGImage {
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw Failure.displayNotFound }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
        config.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Normal app windows currently on screen, frontmost first.
    static func visibleWindows() -> [ScreenWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width > 40, frame.height > 40 else { return nil }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha == 0 { return nil }
            return ScreenWindow(
                frame: frame,
                ownerPID: pid,
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "Unknown app",
                title: (entry[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }

    /// Top-left corner of a screen in global top-left coordinates.
    static func origin(of screen: NSScreen) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGPoint(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY)
    }

    /// Cuts a rectangle given in global top-left coordinates out of a frozen image of `screen`.
    static func crop(_ image: CGImage, to rect: CGRect, on screen: NSScreen) -> CGImage? {
        let origin = origin(of: screen)
        let scale = CGFloat(image.width) / screen.frame.width
        let local = CGRect(x: (rect.minX - origin.x) * scale, y: (rect.minY - origin.y) * scale,
                           width: rect.width * scale, height: rect.height * scale)
        let clamped = local.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !clamped.isNull, clamped.width >= 2, clamped.height >= 2 else { return nil }
        return image.cropping(to: clamped)
    }
}

/// Image bytes ready to write next to a clip's markdown file.
struct EncodedImage {
    var data: Data
    var fileExtension: String
}

enum ImageEncoder {
    /// PNG keeps small UI captures crisp; large ones fall back to JPEG so the vault doesn't balloon.
    static func encode(_ image: CGImage, maxDimension: Int, pngLimit: Int = 1_500_000) -> EncodedImage? {
        let scaled = downscale(image, maxDimension: maxDimension)
        if let png = data(scaled, type: .png), png.count <= pngLimit {
            return EncodedImage(data: png, fileExtension: "png")
        }
        return data(scaled, type: .jpeg, quality: 0.82).map { EncodedImage(data: $0, fileExtension: "jpg") }
    }

    private static func downscale(_ image: CGImage, maxDimension: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxDimension else { return image }
        let ratio = CGFloat(maxDimension) / CGFloat(longest)
        let width = Int(CGFloat(image.width) * ratio)
        let height = Int(CGFloat(image.height) * ratio)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func data(_ image: CGImage, type: UTType, quality: CGFloat? = nil) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
