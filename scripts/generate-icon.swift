import AppKit
import Foundation

// A resolution-independent book-and-sun mark, rendered into macOS's required icon sizes.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("Unable to create icon bitmap") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        NSColor(red: 0.22, green: 0.38, blue: 0.33, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 208, yRadius: 208).fill()
        NSColor(red: 0.98, green: 0.96, blue: 0.89, alpha: 1).setStroke()
        for offset in [0.0, 75.0, 150.0] {
            let path = NSBezierPath(); path.lineWidth = 24; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 236, y: 565 - offset))
            path.curve(to: NSPoint(x: 512, y: 505 - offset), controlPoint1: NSPoint(x: 365, y: 600 - offset), controlPoint2: NSPoint(x: 450, y: 555 - offset))
            path.curve(to: NSPoint(x: 788, y: 565 - offset), controlPoint1: NSPoint(x: 575, y: 555 - offset), controlPoint2: NSPoint(x: 660, y: 600 - offset))
            path.stroke()
        }
        let spine = NSBezierPath(); spine.lineWidth = 20; spine.lineCapStyle = .round
        spine.move(to: NSPoint(x: 512, y: 505)); spine.line(to: NSPoint(x: 512, y: 280)); spine.stroke()
        NSColor(red: 0.90, green: 0.72, blue: 0.42, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 458, y: 673, width: 108, height: 108)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("Unable to encode icon") }
        try data.write(to: destination.appendingPathComponent(name))
    }
}
