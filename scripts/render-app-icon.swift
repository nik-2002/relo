import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("Usage: render-app-icon.swift <source.png> <output.png>\n", stderr)
  exit(64)
}

let sourcePath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let pixelSize = 1024

guard let sourceImage = NSImage(contentsOfFile: sourcePath) else {
  fputs("Could not open source image: \(sourcePath)\n", stderr)
  exit(66)
}

guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: pixelSize,
  pixelsHigh: pixelSize,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bitmapFormat: [],
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fputs("Could not create output bitmap.\n", stderr)
  exit(70)
}

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
  fputs("Could not create graphics context.\n", stderr)
  exit(70)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

let context = graphicsContext.cgContext
let canvas = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
context.clear(canvas)

// A superellipse gives the icon the continuous corners expected of modern
// macOS app icons while retaining transparent outer corners in the ICNS.
let exponent = 5.0
let center = CGPoint(x: canvas.midX, y: canvas.midY)
let radius = Double(pixelSize) / 2.0
let clipPath = CGMutablePath()
let steps = 512

for index in 0...steps {
  let angle = (Double(index) / Double(steps)) * 2.0 * Double.pi
  let cosine = cos(angle)
  let sine = sin(angle)
  let x = Double(center.x) + radius * copysign(pow(abs(cosine), 2.0 / exponent), cosine)
  let y = Double(center.y) + radius * copysign(pow(abs(sine), 2.0 / exponent), sine)
  let point = CGPoint(x: x, y: y)
  if index == 0 {
    clipPath.move(to: point)
  } else {
    clipPath.addLine(to: point)
  }
}
clipPath.closeSubpath()
context.addPath(clipPath)
context.clip()

sourceImage.draw(
  in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
  from: NSRect(origin: .zero, size: sourceImage.size),
  operation: .copy,
  fraction: 1.0
)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
  fputs("Could not encode output PNG.\n", stderr)
  exit(70)
}

do {
  try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
} catch {
  fputs("Could not write output image: \(error)\n", stderr)
  exit(74)
}
