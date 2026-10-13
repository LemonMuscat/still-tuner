import AppKit
let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.07, green: 0.095, blue: 0.10, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 210, yRadius: 210).fill()
let mint = NSColor(calibratedRed: 0.53, green: 0.94, blue: 0.74, alpha: 1)
for i in -5...5 {
    let x = 512 + CGFloat(i) * 68
    let line = NSBezierPath(); line.move(to: NSPoint(x: x, y: 270)); line.line(to: NSPoint(x: x, y: i == 0 ? 370 : 315))
    (i == 0 ? mint : NSColor.white.withAlphaComponent(0.23)).setStroke(); line.lineWidth = i == 0 ? 9 : 5; line.stroke()
}
let text: NSString = "E"
let font = NSFont.systemFont(ofSize: 420, weight: .medium)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let size = text.size(withAttributes: attrs)
text.draw(at: NSPoint(x: (1024 - size.width) / 2, y: 385), withAttributes: attrs)
let needle = NSBezierPath(); needle.move(to: NSPoint(x: 512, y: 252)); needle.line(to: NSPoint(x: 512, y: 397)); needle.lineWidth = 12; needle.lineCapStyle = .round; mint.setStroke(); needle.stroke()
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
