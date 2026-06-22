import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift generate-app-icon.swift OUTPUT_PNG\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("error: unable to create graphics context\n", stderr)
    exit(1)
}

let outer = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 220, yRadius: 220)
NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.48, green: 0.18, blue: 0.82, alpha: 1),
])!.draw(in: outer, angle: -45)

NSColor.white.withAlphaComponent(0.16).setStroke()
outer.lineWidth = 12
outer.stroke()

let glass = NSBezierPath(roundedRect: NSRect(x: 112, y: 112, width: 800, height: 800), xRadius: 170, yRadius: 170)
NSColor.white.withAlphaComponent(0.14).setFill()
glass.fill()
NSColor.white.withAlphaComponent(0.28).setStroke()
glass.lineWidth = 8
glass.stroke()

let gaugeRect = NSRect(x: 292, y: 338, width: 440, height: 440)
context.saveGState()
context.setStrokeColor(NSColor.cyan.withAlphaComponent(0.82).cgColor)
context.setLineWidth(42)
context.setLineCap(.round)
context.addArc(center: CGPoint(x: gaugeRect.midX, y: gaugeRect.midY), radius: 200, startAngle: .pi * 0.15, endAngle: .pi * 1.85, clockwise: false)
context.strokePath()
context.restoreGState()

context.saveGState()
context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
context.setLineWidth(25)
context.setLineCap(.round)
context.addArc(center: CGPoint(x: gaugeRect.midX, y: gaugeRect.midY), radius: 200, startAngle: .pi * 0.15, endAngle: .pi * 0.95, clockwise: false)
context.strokePath()
context.restoreGState()

context.saveGState()
context.translateBy(x: 512, y: 558)
context.rotate(by: -.pi / 4)
context.setFillColor(NSColor.systemOrange.cgColor)
context.fill(CGRect(x: -13, y: -20, width: 26, height: 190))
context.restoreGState()

NSColor.systemOrange.setFill()
NSBezierPath(ovalIn: NSRect(x: 472, y: 518, width: 80, height: 80)).fill()

let barHeights: [CGFloat] = [70, 110, 150, 110, 70]
for (index, height) in barHeights.enumerated() {
    let rect = NSRect(x: 400 + CGFloat(index) * 50, y: 220, width: 24, height: height)
    NSColor.cyan.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
}

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("error: unable to encode application icon\n", stderr)
    exit(1)
}
try png.write(to: outputURL, options: .atomic)
