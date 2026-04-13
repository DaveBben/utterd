#!/usr/bin/env swift
// generate-dmg-background.swift
// Renders a 1200x800 dark diagonal gradient PNG for use as a DMG background.
// Usage: swift generate-dmg-background.swift [output-path]
// Default output: scripts/dmg-background.png (relative to this script's directory)
// Note: invoke with an absolute or relative path only — tilde (~) is not expanded.

import CoreGraphics
import CoreImage
import Foundation

// ---------------------------------------------------------------------------
// Resolve output path
// ---------------------------------------------------------------------------

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
    .standardizedFileURL

// The script may be invoked as a relative path; resolve against cwd.
let resolvedScript: URL
if scriptURL.path.hasPrefix("/") {
    resolvedScript = scriptURL
} else {
    resolvedScript = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(CommandLine.arguments[0])
        .standardizedFileURL
}

let scriptDir = resolvedScript.deletingLastPathComponent()
let defaultOutputURL = scriptDir.appendingPathComponent("dmg-background.png")

let outputURL: URL
if CommandLine.arguments.count > 1 {
    let arg = CommandLine.arguments[1]
    if arg.hasPrefix("/") {
        outputURL = URL(fileURLWithPath: arg)
    } else {
        outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(arg)
    }
} else {
    outputURL = defaultOutputURL
}

// ---------------------------------------------------------------------------
// Render gradient
// ---------------------------------------------------------------------------

let width = 1200
let height = 800

// sRGB color space
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    fputs("Error: could not create sRGB color space\n", stderr)
    exit(1)
}

// premultipliedLast: alpha is stored in the last channel and pre-multiplied.
// This ensures the PNG written by CIContext has alpha=255 (fully opaque)
// everywhere. noneSkipLast (the previous setting) caused CIFormat.RGBX8 to
// write the X byte as 0, producing a transparent PNG that Finder rendered as
// the default window background instead of the dark gradient.
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo.rawValue
) else {
    fputs("Error: could not create CGContext\n", stderr)
    exit(1)
}

// Top-left color: sRGB 0.06/0.06/0.12 (dark navy/charcoal)
// Bottom-right color: sRGB 0.10/0.13/0.20 (slightly lighter dark blue)
let startComponents: [CGFloat] = [0.06, 0.06, 0.12, 1.0]
let endComponents: [CGFloat] = [0.10, 0.13, 0.20, 1.0]

guard let startColor = CGColor(colorSpace: colorSpace, components: startComponents),
      let endColor = CGColor(colorSpace: colorSpace, components: endComponents) else {
    fputs("Error: could not create gradient colors\n", stderr)
    exit(1)
}

// Diagonal gradient: start point top-left (0, height), end point bottom-right (width, 0)
// CoreGraphics coordinate system has origin at bottom-left.
let colors = [startColor, endColor] as CFArray
let locations: [CGFloat] = [0.0, 1.0]

guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
    fputs("Error: could not create CGGradient\n", stderr)
    exit(1)
}

let startPoint = CGPoint(x: 0, y: CGFloat(height))      // top-left in CG coords
let endPoint = CGPoint(x: CGFloat(width), y: 0)          // bottom-right in CG coords

// Fill the canvas first so that any pixel not covered by the gradient
// (e.g. anti-aliased edges) inherits the start color rather than being
// left as transparent (alpha=0) in the premultiplied context.
context.setFillColor(startColor)
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

context.drawLinearGradient(
    gradient,
    start: startPoint,
    end: endPoint,
    options: []
)

// ---------------------------------------------------------------------------
// Write PNG
// ---------------------------------------------------------------------------

guard let cgImage = context.makeImage() else {
    fputs("Error: could not create CGImage from context\n", stderr)
    exit(1)
}

let ciImage = CIImage(cgImage: cgImage)
// Software renderer avoids GPU/Metal init overhead for a one-shot offline
// script and prevents macOS from triggering GPU privacy prompts.
let ciContext = CIContext(options: [.useSoftwareRenderer: true])

guard let pngData = ciContext.pngRepresentation(
    of: ciImage,
    format: .RGBA8,
    colorSpace: colorSpace
) else {
    fputs("Error: could not render PNG data\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: outputURL)
    print("Written: \(outputURL.path)")
} catch {
    fputs("Error: could not write PNG to \(outputURL.path): \(error)\n", stderr)
    exit(1)
}
