import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    NSColor(calibratedRed: 0.18, green: 0.36, blue: 0.28, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92), xRadius: s * 0.22, yRadius: s * 0.22).fill()
    NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.93, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.24, y: s * 0.17, width: s * 0.53, height: s * 0.66), xRadius: s * 0.055, yRadius: s * 0.055).fill()
    NSColor(calibratedRed: 0.18, green: 0.36, blue: 0.28, alpha: 1).setStroke()
    let heights: [CGFloat] = [0.10, 0.22, 0.36, 0.22, 0.10]
    for (i, h) in heights.enumerated() {
        let x = s * (0.35 + CGFloat(i) * 0.078)
        let p = NSBezierPath(); p.lineWidth = max(1, s * 0.027); p.lineCapStyle = .round
        p.move(to: NSPoint(x: x, y: s * (0.50 - h / 2))); p.line(to: NSPoint(x: x, y: s * (0.50 + h / 2))); p.stroke()
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon render failed") }
    // iconutil expects these exact point-size / scale filenames.
    let names: [Int: [String]] = [16:["icon_16x16.png"],32:["icon_16x16@2x.png","icon_32x32.png"],64:["icon_32x32@2x.png"],128:["icon_128x128.png"],256:["icon_128x128@2x.png","icon_256x256.png"],512:["icon_256x256@2x.png","icon_512x512.png"],1024:["icon_512x512@2x.png"]]
    for name in names[size]! { try png.write(to: root.appendingPathComponent(name)) }
}
