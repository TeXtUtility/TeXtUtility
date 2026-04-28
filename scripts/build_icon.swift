#!/usr/bin/env swift
//
// Auto-trim transparent borders of a source PNG and generate a macOS .iconset
// directory ready for `iconutil -c icns`. Optionally also writes a single
// 512×512 cropped PNG for in-app UI use (passed as third arg).
//
// Usage:
//   swift scripts/build_icon.swift <input.png> <output.iconset> [<applogo-out.png>]
//
import Foundation
import AppKit
import CoreGraphics
import ImageIO

guard CommandLine.arguments.count >= 3 else {
    print("usage: build_icon.swift <input.png> <output.iconset> [<applogo-out.png>]")
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputDir = CommandLine.arguments[2]
let appLogoOut: String? = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : nil

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
      let cgImg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("error: cannot read \(inputPath)\n".data(using: .utf8)!)
    exit(1)
}

let w = cgImg.width
let h = cgImg.height

// Render alpha channel into a buffer to find non-transparent bounding box.
let bytesPerRow = w
guard let alphaCtx = CGContext(
    data: nil, width: w, height: h,
    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceGray(),
    bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
) else { exit(1) }
alphaCtx.draw(cgImg, in: CGRect(x: 0, y: 0, width: w, height: h))
guard let buf = alphaCtx.data else { exit(1) }
let alpha = buf.assumingMemoryBound(to: UInt8.self)

// Note: CGContext's pixel buffer for a "alphaOnly" context with default
// bitmap info has y growing UP from bottom. We want image-coord bbox (y=0
// at top), so flip.
let threshold: UInt8 = 16
var minX = w, maxX = -1
var minRowCG = h, maxRowCG = -1
for row in 0..<h {
    for x in 0..<w {
        if alpha[row * bytesPerRow + x] > threshold {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if row < minRowCG { minRowCG = row }
            if row > maxRowCG { maxRowCG = row }
        }
    }
}
if maxX < 0 {
    FileHandle.standardError.write("error: source image is entirely transparent\n".data(using: .utf8)!)
    exit(1)
}
let minY = h - 1 - maxRowCG
let maxY = h - 1 - minRowCG

let cropW = maxX - minX + 1
let cropH = maxY - minY + 1
let bboxSide = max(cropW, cropH)
let breathing = max(4, bboxSide / 24)
let cropSide = bboxSide + 2 * breathing
// Center the square crop on the bbox.
let centerX = (minX + maxX) / 2
let centerY = (minY + maxY) / 2
let cropMinX = centerX - cropSide / 2
let cropMinY = centerY - cropSide / 2

print("source:  \(w) x \(h)")
print("bbox:    (\(minX),\(minY))–(\(maxX),\(maxY)) → \(cropW) x \(cropH)")
print("crop:    (\(cropMinX),\(cropMinY)) → \(cropSide) x \(cropSide)")

// Render the cropped square into a 1024x1024 master, then downscale for each
// icon size. Source pixels outside the source image bounds are transparent
// (which is fine — gives a small transparent halo for asymmetric crops).
let masterSize = 1024
guard let outCS = CGColorSpace(name: CGColorSpace.sRGB),
      let masterCtx = CGContext(
        data: nil, width: masterSize, height: masterSize,
        bitsPerComponent: 8, bytesPerRow: masterSize * 4,
        space: outCS, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { exit(1) }
masterCtx.interpolationQuality = .high

// CG-space draw transform: place a `cropSide`×`cropSide` source crop at
// (cropMinX, cropMinY) onto the full output. CG's y-axis is bottom-up, so the
// source image, when drawn, has its image-top at the higher-y edge of dst.
let scale = CGFloat(masterSize) / CGFloat(cropSide)
let dstW = CGFloat(w) * scale
let dstH = CGFloat(h) * scale
let dstX = -CGFloat(cropMinX) * scale
let dstY = CGFloat(masterSize) - dstH + CGFloat(cropMinY) * scale
masterCtx.draw(cgImg, in: CGRect(x: dstX, y: dstY, width: dstW, height: dstH))
guard let masterImg = masterCtx.makeImage() else { exit(1) }

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func write(_ image: CGImage, to path: String, size: Int) {
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let out = ctx.makeImage(),
          let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                    "public.png" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dst, out, nil)
    CGImageDestinationFinalize(dst)
}

let entries: [(String, Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]
for (name, size) in entries {
    let path = (outputDir as NSString).appendingPathComponent(name)
    write(masterImg, to: path, size: size)
}
print("wrote \(entries.count) PNGs to \(outputDir)")

if let appLogoOut = appLogoOut {
    let parent = (appLogoOut as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
    write(masterImg, to: appLogoOut, size: 512)
    print("wrote app logo: \(appLogoOut)")
}
