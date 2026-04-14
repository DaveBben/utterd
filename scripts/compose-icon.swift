#!/usr/bin/env swift
// compose-icon.swift
// Composites the foreground icon artwork over a blue radial gradient background
// to produce the complete app icon, matching the Glass App Icon .icon format:
//   - Background: radial gradient using extended-sRGB(0, 0.533, 1.0) blue
//   - Foreground: the artwork layer composited at 50% opacity (translucency: 0.5)
//
// Usage:
//   swift scripts/compose-icon.swift <foreground-png> <output-dir>
//
// Example:
//   swift scripts/compose-icon.swift \
//     Utterd/Resources/Assets.xcassets/AppIcon.appiconset/1024.png \
//     Utterd/Resources/Assets.xcassets/AppIcon.appiconset

import CoreGraphics
import CoreImage
import Foundation

// ---------------------------------------------------------------------------
// Arguments
// ---------------------------------------------------------------------------

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift compose-icon.swift <foreground-png> <output-dir>\n", stderr)
    exit(1)
}

let fgArg = CommandLine.arguments[1]
let outArg = CommandLine.arguments[2]

func resolveURL(_ arg: String) -> URL {
    if arg.hasPrefix("/") {
        return URL(fileURLWithPath: arg)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(arg)
        .standardizedFileURL
}

let fgURL = resolveURL(fgArg)
let outDir = resolveURL(outArg)

// ---------------------------------------------------------------------------
// Load foreground PNG
// ---------------------------------------------------------------------------

guard let fgDataProvider = CGDataProvider(url: fgURL as CFURL),
      let fgImage = CGImage(
          pngDataProviderSource: fgDataProvider,
          decode: nil,
          shouldInterpolate: true,
          intent: .defaultIntent
      ) else {
    fputs("Error: could not load foreground PNG from \(fgURL.path)\n", stderr)
    exit(1)
}

let size = 1024

guard let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) else {
    fputs("Error: could not create Display P3 color space\n", stderr)
    exit(1)
}

let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo.rawValue
) else {
    fputs("Error: could not create CGContext\n", stderr)
    exit(1)
}

// ---------------------------------------------------------------------------
// Clip to macOS squircle (continuous superellipse)
// Superellipse parametric form: x = a·sign(cos t)·|cos t|^(2/n)
//                               y = b·sign(sin t)·|sin t|^(2/n)
// n ≈ 5 matches macOS's continuous corner curve (~22% corner radius).
// ---------------------------------------------------------------------------

let s = CGFloat(size)
let halfS = s / 2.0
let n: CGFloat = 5.0
let exp2n = 2.0 / n

let squirclePath = CGMutablePath()
let steps = 360
for i in 0...steps {
    let angle = CGFloat(i) * (2.0 * .pi) / CGFloat(steps)
    let cosA = cos(angle)
    let sinA = sin(angle)
    let px = halfS + halfS * copysign(pow(abs(cosA), exp2n), cosA)
    let py = halfS + halfS * copysign(pow(abs(sinA), exp2n), sinA)
    if i == 0 {
        squirclePath.move(to: CGPoint(x: px, y: py))
    } else {
        squirclePath.addLine(to: CGPoint(x: px, y: py))
    }
}
squirclePath.closeSubpath()

context.addPath(squirclePath)
context.clip()

// ---------------------------------------------------------------------------
// Draw background: radial gradient (blue, extended-sRGB 0,0.533,1.0)
// The .icon format "automatic gradient" produces a lighter center fading
// to the full base color at the edges — a subtle depth effect.
// We approximate: center = base+15% lighter, edge = base.
// ---------------------------------------------------------------------------

// Base blue: extended-sRGB (0.00, 0.533, 1.00) → in Display P3 space
// P3 gamut is wider; we target the same perceptual blue.
// For simplicity use sRGB-clamped values: (0.0, 0.533, 1.0)
let baseBlue: [CGFloat] = [0.00, 0.533, 1.00, 1.0]
let lightBlue: [CGFloat] = [0.18, 0.65,  1.00, 1.0]   // lighter for center highlight

guard let edgeColor = CGColor(colorSpace: colorSpace, components: baseBlue),
      let centerColor = CGColor(colorSpace: colorSpace, components: lightBlue) else {
    fputs("Error: could not create gradient colors\n", stderr)
    exit(1)
}

let gradColors = [centerColor, edgeColor] as CFArray
let gradLocations: [CGFloat] = [0.0, 1.0]

guard let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradColors,
    locations: gradLocations
) else {
    fputs("Error: could not create CGGradient\n", stderr)
    exit(1)
}

let center = CGPoint(x: halfS, y: halfS)
let radius = s * 0.70   // gradient covers ~70% radius; edges are edge color

// Fill clipped region with edge color so areas beyond the gradient radius
// (but inside the squircle) get the base blue, not transparent black.
context.setFillColor(edgeColor)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

context.drawRadialGradient(
    gradient,
    startCenter: center,
    startRadius: 0,
    endCenter: center,
    endRadius: radius,
    options: [.drawsAfterEndLocation]
)

// ---------------------------------------------------------------------------
// Draw foreground artwork at 50% opacity (translucency: 0.5)
// ---------------------------------------------------------------------------

context.setAlpha(0.5)
context.draw(fgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
context.setAlpha(1.0)

// ---------------------------------------------------------------------------
// Export composited 1024×1024 PNG, then resize to all required sizes
// ---------------------------------------------------------------------------

guard let composited = context.makeImage() else {
    fputs("Error: could not create composited CGImage\n", stderr)
    exit(1)
}

let ciImage = CIImage(cgImage: composited)
let ciContext = CIContext(options: [.useSoftwareRenderer: true])

guard let colorSpaceSRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
    fputs("Error: could not create sRGB color space for output\n", stderr)
    exit(1)
}

let compositedURL = outDir.appendingPathComponent("1024.png")
guard let pngData = ciContext.pngRepresentation(
    of: ciImage,
    format: .RGBA8,
    colorSpace: colorSpaceSRGB
) else {
    fputs("Error: could not render PNG data\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: compositedURL)
    print("Written: \(compositedURL.path)")
} catch {
    fputs("Error writing 1024.png: \(error)\n", stderr)
    exit(1)
}

// Resize to other required sizes using sips
let sizes = [16, 32, 64, 128, 256, 512]
for sz in sizes {
    let destURL = outDir.appendingPathComponent("\(sz).png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = [
        "-z", "\(sz)", "\(sz)",
        compositedURL.path,
        "--out", destURL.path
    ]
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            print("Written: \(destURL.path)")
        } else {
            fputs("Warning: sips failed for \(sz)px (exit \(process.terminationStatus))\n", stderr)
        }
    } catch {
        fputs("Warning: could not run sips for \(sz)px: \(error)\n", stderr)
    }
}

print("Done.")
