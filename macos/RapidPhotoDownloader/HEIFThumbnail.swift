import Cocoa
import ImageIO
import Foundation

/// Native macOS HEIF/image thumbnail + metadata helpers.
/// Replaces raphodo/heif.py + raphodo/metadata on the macOS port:
/// ImageIO decodes HEIF/HEIC (and most RAW) with no third-party dependency.

public enum HEIFThumbnail {
    /// Generate a thumbnail (maxPixel on longest side). Prefers an embedded
    /// preview when available for speed, falls back to full decode.
    public static func thumbnail(url: URL, maxPixel: Int = 256) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let embeddedOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        var cg = CGImageSourceCreateThumbnailAtIndex(src, 0, embeddedOpts as CFDictionary)
        if cg == nil {
            let forcedOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            cg = CGImageSourceCreateThumbnailAtIndex(src, 0, forcedOpts as CFDictionary)
        }
        guard let image = cg else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// Read the original capture date from EXIF, falling back to file mtime.
    public static func captureDate(url: URL) -> Date {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            if let d = fmt.date(from: dateStr) { return d }
        }
        // Fallback: file modification date
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let m = attrs[.modificationDate] as? Date {
            return m
        }
        return Date()
    }

    /// Pixel dimensions from image properties (cheap, no decode).
    public static func pixelSize(url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    /// True if ImageIO can read this file (covers HEIF/HEIC, JPEG, PNG, TIFF, RAW).
    public static func isReadable(url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(src) > 0
    }
}
