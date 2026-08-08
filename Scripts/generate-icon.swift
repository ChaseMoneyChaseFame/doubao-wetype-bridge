import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("usage: generate-icon.swift <output.png>\n", stderr)
  exit(2)
}

let size = 1024
guard
  let bitmap = NSBitmapImageRep(
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
  )
else {
  exit(1)
}

bitmap.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let canvas = NSRect(x: 32, y: 32, width: 960, height: 960)

func color(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
  NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

let iconPath = NSBezierPath(roundedRect: canvas, xRadius: 220, yRadius: 220)
let backgroundGradient = NSGradient(colors: [
  color(red: 0.10, green: 0.15, blue: 0.26),
  color(red: 0.04, green: 0.07, blue: 0.14),
])!
backgroundGradient.draw(in: iconPath, angle: -35)

// A restrained highlight keeps the icon legible on both light and dark desktops.
color(red: 1, green: 1, blue: 1, alpha: 0.12).setStroke()
iconPath.lineWidth = 4
iconPath.stroke()

func drawBubble(
  rect: NSRect,
  stroke: NSColor,
  tailOnRight: Bool
) {
  let body = NSBezierPath(roundedRect: rect, xRadius: 112, yRadius: 112)
  body.lineWidth = 38

  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
  shadow.shadowBlurRadius = 20
  shadow.shadowOffset = NSSize(width: 0, height: -12)
  shadow.set()

  color(red: 1, green: 1, blue: 1, alpha: 0.035).setFill()
  body.fill()
  stroke.setStroke()
  body.stroke()

  let tail = NSBezierPath()
  tail.lineWidth = 38
  tail.lineCapStyle = .round
  tail.lineJoinStyle = .round
  if tailOnRight {
    tail.move(to: NSPoint(x: rect.maxX - 132, y: rect.minY + 22))
    tail.line(to: NSPoint(x: rect.maxX - 92, y: rect.minY - 46))
    tail.line(to: NSPoint(x: rect.maxX - 48, y: rect.minY + 28))
  } else {
    tail.move(to: NSPoint(x: rect.minX + 132, y: rect.minY + 22))
    tail.line(to: NSPoint(x: rect.minX + 92, y: rect.minY - 46))
    tail.line(to: NSPoint(x: rect.minX + 48, y: rect.minY + 28))
  }
  stroke.setStroke()
  tail.stroke()
  NSGraphicsContext.restoreGraphicsState()
}

// The warm bubble is the voice-input side; the green bubble is the everyday
// typing side. Their overlap is the bridge this utility provides.
drawBubble(
  rect: NSRect(x: 128, y: 388, width: 510, height: 292),
  stroke: color(red: 1.00, green: 0.66, blue: 0.18),
  tailOnRight: false
)
drawBubble(
  rect: NSRect(x: 386, y: 312, width: 510, height: 292),
  stroke: color(red: 0.24, green: 0.80, blue: 0.48),
  tailOnRight: true
)

let waveform = NSBezierPath()
waveform.lineWidth = 42
waveform.lineCapStyle = .round
waveform.lineJoinStyle = .round
waveform.move(to: NSPoint(x: 254, y: 514))
waveform.line(to: NSPoint(x: 340, y: 514))
waveform.line(to: NSPoint(x: 394, y: 594))
waveform.line(to: NSPoint(x: 462, y: 432))
waveform.line(to: NSPoint(x: 530, y: 610))
waveform.line(to: NSPoint(x: 596, y: 456))
waveform.line(to: NSPoint(x: 654, y: 536))
waveform.line(to: NSPoint(x: 770, y: 536))
NSColor.white.setStroke()
waveform.stroke()

// A small center point makes the bridge read at menu-sized previews while
// remaining quiet at the full app-icon size.
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 500, y: 488, width: 42, height: 42)).fill()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
  exit(1)
}
try pngData.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
