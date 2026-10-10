import AppKit
let folder = CommandLine.arguments[1]
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.19, green: 0.34, blue: 0.86, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p*0.05, y: p*0.05, width: p*0.9, height: p*0.9), xRadius: p*0.2, yRadius: p*0.2).fill()
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: p*0.24, y: p*0.37, width: p*0.39, height: p*0.39))
        ring.lineWidth = p*0.065; ring.stroke()
        let handle = NSBezierPath(); handle.move(to: NSPoint(x: p*0.57, y: p*0.40)); handle.line(to: NSPoint(x: p*0.76, y: p*0.21)); handle.lineWidth = p*0.08; handle.lineCapStyle = .round; handle.stroke()
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: URL(fileURLWithPath: folder + "/icon_\(size)x\(size)\(suffix).png"))
    }
}
