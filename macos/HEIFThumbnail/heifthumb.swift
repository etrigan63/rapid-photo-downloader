//
// heifthumb.swift
//
// Native macOS HEIF/HEIC (and general image) thumbnail generator.
//
// Demonstrates the fix for Rapid Photo Downloader's Linux HEIF thumbnail
// problem: on macOS, ImageIO (CGImageSource) decodes HEIF/HEIC natively,
// with no libheif / pillow-heif dependency.
//
// Build:   swiftc -O -o heifthumb heifthumb.swift
// Usage:   heifthumb <image> [out.png] [maxPixel]

import Foundation
import ImageIO
import CoreGraphics

func makeThumbnail(url: URL, maxPixel: Int, preferEmbedded: Bool) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: !preferEmbedded,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
        return cg
    }
    if preferEmbedded {
        let forced: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, forced as CFDictionary)
    }
    return nil
}

func imageProperties(url: URL) -> [CFString: Any]? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
}

let args = CommandLine.arguments
if args.count < 2 {
    print("usage: heifthumb <image> [out.png] [maxPixel]")
    exit(1)
}
let inputPath = args[1]
let outputPath = args.count > 2 ? args[2] : "/tmp/heifthumb_out.png"
let maxPixel = args.count > 3 ? (Int(args[3]) ?? 512) : 512

let inputURL = URL(fileURLWithPath: inputPath)
let outputURL = URL(fileURLWithPath: outputPath)

guard let cg = makeThumbnail(url: inputURL, maxPixel: maxPixel, preferEmbedded: true) else {
    print("failed to create thumbnail for \(inputPath)")
    exit(2)
}

guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
    print("failed to create destination \(outputPath)")
    exit(3)
}
CGImageDestinationAddImage(dest, cg, nil)
if CGImageDestinationFinalize(dest) {
    print("wrote \(outputPath) \(cg.width)x\(cg.height)")
} else {
    print("finalize failed")
    exit(4)
}

if let props = imageProperties(url: inputURL) {
    if let w = props[kCGImagePropertyPixelWidth] { print("source width: \(w)") }
    if let h = props[kCGImagePropertyPixelHeight] { print("source height: \(h)") }
    if let orient = props[kCGImagePropertyOrientation] { print("orientation: \(orient)") }
    if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
       let date = exif[kCGImagePropertyExifDateTimeOriginal] {
        print("exif date: \(date)")
    }
}
