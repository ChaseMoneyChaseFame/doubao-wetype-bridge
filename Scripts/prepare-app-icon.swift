import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: prepare-app-icon.swift <input.png> <output.png>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let size = 1024
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
// Leave a small transparent safety zone so Launchpad renders this artwork at
// the same visual size as neighboring macOS application icons.
let artworkRect = canvas.insetBy(dx: 40, dy: 40)

guard let source = NSImage(contentsOf: inputURL),
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
      ),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fputs("unable to load icon source\n", stderr)
    exit(1)
}

bitmap.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

NSColor.clear.setFill()
canvas.fill()

// The generated artwork has a black square and a thin dark outline outside its
// rounded tile. Clip both away instead of changing the artwork itself.
let mask = NSBezierPath(roundedRect: artworkRect, xRadius: 210, yRadius: 210)
mask.addClip()
source.draw(in: artworkRect, from: .zero, operation: .copy, fraction: 1)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode prepared icon\n", stderr)
    exit(1)
}
try pngData.write(to: outputURL)
