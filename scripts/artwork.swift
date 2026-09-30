import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(width: Int, height: Int, scale: CGFloat = 1, draw: (CGRect) -> Void) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.cgContext.scaleBy(x: scale, y: scale)
    context.imageInterpolation = .high
    draw(CGRect(x: 0, y: 0, width: CGFloat(width) / scale, height: CGFloat(height) / scale))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
func write(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
func centered(_ text: String, y: CGFloat, font: NSFont, color: NSColor, width: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(at: NSPoint(x: (width - size.width) / 2, y: y), withAttributes: attributes)
}
let original = render(width: 1024, height: 1024) { _ in
    let tile = NSBezierPath(roundedRect: CGRect(x: 92, y: 92, width: 840, height: 840), xRadius: 184, yRadius: 184)
    NSGraphicsContext.current!.cgContext.setShadow(offset: CGSize(width: 0, height: -16), blur: 38, color: NSColor.black.withAlphaComponent(0.22).cgColor)
    NSGradient(colors: [NSColor(calibratedRed: 0.25, green: 0.27, blue: 0.36, alpha: 1), NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.12, alpha: 1)])!.draw(in: tile, angle: -70)
    NSGraphicsContext.current!.cgContext.setShadow(offset: .zero, blur: 0)
    NSColor.white.withAlphaComponent(0.18).setStroke(); tile.lineWidth = 2; tile.stroke()
    let orbit = NSBezierPath(ovalIn: CGRect(x: 247, y: 332, width: 530, height: 360))
    orbit.lineWidth = 19
    NSGraphicsContext.current!.cgContext.setShadow(offset: .zero, blur: 35, color: NSColor.systemIndigo.withAlphaComponent(0.55).cgColor)
    NSColor(calibratedRed: 0.57, green: 0.70, blue: 1, alpha: 0.95).setStroke(); orbit.stroke()
    NSGraphicsContext.current!.cgContext.setShadow(offset: .zero, blur: 0)
    let notch = NSBezierPath(roundedRect: CGRect(x: 301, y: 420, width: 422, height: 194), xRadius: 61, yRadius: 61)
    NSGradient(colors: [NSColor(calibratedWhite: 0.09, alpha: 1), NSColor(calibratedWhite: 0.015, alpha: 1)])!.draw(in: notch, angle: -90)
    NSColor.white.withAlphaComponent(0.12).setStroke(); notch.lineWidth = 1.5; notch.stroke()
    NSColor.white.withAlphaComponent(0.88).setFill()
    NSBezierPath(roundedRect: CGRect(x: 347, y: 496, width: 26, height: 42), xRadius: 7, yRadius: 7).fill()
    NSBezierPath(ovalIn: CGRect(x: 652, y: 507, width: 17, height: 17)).fill()
}
let iconURL = resources.appendingPathComponent("AppIcon.png")
try write(original, to: iconURL)
let iconImage = NSImage(data: original.representation(using: .png, properties: [:])!)!
for size in [16, 32, 128, 256, 512] {
    for multiplier in [1, 2] {
        let pixels = size * multiplier
        let bitmap = render(width: pixels, height: pixels) { rect in iconImage.draw(in: rect, from: .zero, operation: .copy, fraction: 1) }
        let suffix = multiplier == 2 ? "@2x" : ""
        try write(bitmap, to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let background = render(width: 1200, height: 800, scale: 2) { rect in
    NSGradient(colors: [NSColor(calibratedRed: 0.975, green: 0.98, blue: 0.99, alpha: 1), NSColor(calibratedRed: 0.90, green: 0.925, blue: 0.955, alpha: 1)])!.draw(in: rect, angle: -65)
    centered("Halo", y: 318, font: .systemFont(ofSize: 34, weight: .medium), color: NSColor(calibratedWhite: 0.15, alpha: 1), width: 600)
    centered("A little more Mac.", y: 292, font: .systemFont(ofSize: 13), color: .secondaryLabelColor, width: 600)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 272, y: 199)); arrow.line(to: NSPoint(x: 328, y: 199))
    arrow.move(to: NSPoint(x: 315, y: 212)); arrow.line(to: NSPoint(x: 328, y: 199)); arrow.line(to: NSPoint(x: 315, y: 186))
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSColor(calibratedWhite: 0.55, alpha: 1).setStroke(); arrow.stroke()
    centered("Drag Halo to Applications.", y: 48, font: .systemFont(ofSize: 13), color: NSColor(calibratedWhite: 0.38, alpha: 1), width: 600)
    centered("Music. Battery. A moment to focus.", y: 24, font: .systemFont(ofSize: 10), color: NSColor(calibratedWhite: 0.55, alpha: 1), width: 600)
}
try write(background, to: resources.appendingPathComponent("InstallerBackground.png"))
print("Created Halo icon and installer artwork.")
