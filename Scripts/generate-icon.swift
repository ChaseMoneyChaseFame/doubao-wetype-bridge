import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-icon.swift <output.png>\n", stderr)
    exit(2)
}

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    exit(1)
}

bitmap.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let canvas = NSRect(x: 32, y: 32, width: 960, height: 960)
NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
NSBezierPath(roundedRect: canvas, xRadius: 210, yRadius: 210).fill()

let leftBubble = NSBezierPath(roundedRect: NSRect(x: 160, y: 380, width: 390, height: 330), xRadius: 105, yRadius: 105)
leftBubble.lineWidth = 34
NSColor(calibratedRed: 0.97, green: 0.35, blue: 0.30, alpha: 1).setStroke()
leftBubble.stroke()

let rightBubble = NSBezierPath(roundedRect: NSRect(x: 474, y: 314, width: 390, height: 330), xRadius: 105, yRadius: 105)
rightBubble.lineWidth = 34
NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.48, alpha: 1).setStroke()
rightBubble.stroke()

let waveform = NSBezierPath()
waveform.lineWidth = 36
waveform.lineCapStyle = .round
waveform.lineJoinStyle = .round
waveform.move(to: NSPoint(x: 270, y: 500))
waveform.line(to: NSPoint(x: 340, y: 500))
waveform.line(to: NSPoint(x: 390, y: 585))
waveform.line(to: NSPoint(x: 458, y: 435))
waveform.line(to: NSPoint(x: 525, y: 610))
waveform.line(to: NSPoint(x: 594, y: 455))
waveform.line(to: NSPoint(x: 652, y: 535))
waveform.line(to: NSPoint(x: 730, y: 535))
NSColor.white.setStroke()
waveform.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}
try pngData.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
