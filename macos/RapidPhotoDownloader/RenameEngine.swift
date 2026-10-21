import Foundation
import ImageIO

/// Lightweight port of Rapid Photo Downloader's rename engine.
/// Supports a small, well-documented token set; full RPD template parity
/// (80+ tokens) is a later phase.
struct RenameContext {
    let url: URL
    let date: Date
    let cameraMake: String
    let cameraModel: String
    let counter: Int
    let counterDigits: Int

    var originalStem: String { url.deletingPathExtension().lastPathComponent }
    var ext: String { url.pathExtension }
}

enum RenameEngine {
    /// Read camera make/model from image metadata (TIFF/EXIF), if present.
    static func cameraInfo(url: URL) -> (make: String, model: String) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return ("", "")
        }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let make = (tiff?[kCGImagePropertyTIFFMake] as? String) ?? ""
        let model = (tiff?[kCGImagePropertyTIFFModel] as? String) ?? ""
        return (make.trimmingCharacters(in: .whitespaces),
                model.trimmingCharacters(in: .whitespaces))
    }

    /// Apply a template to produce a new filename (without directory).
    /// Unknown tokens are left literally. Result is sanitized for filesystem use.
    static func apply(template: String, context: RenameContext) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")

        df.dateFormat = "yyyyMMdd"
        let dateStr = df.string(from: context.date)
        df.dateFormat = "yyyyMMdd-HHmmss"
        let datetimeStr = df.string(from: context.date)

        let counterStr = String(format: "%0\(context.counterDigits)d", context.counter)

        var result = template
        let tokens: [(String, String)] = [
            ("{date}", dateStr),
            ("{datetime}", datetimeStr),
            ("{camera}", sanitize(context.cameraModel)),
            ("{make}", sanitize(context.cameraMake)),
            ("{original}", sanitize(context.originalStem)),
            ("{ext}", context.ext),
            ("{counter}", counterStr),
        ]
        for (tok, val) in tokens {
            result = result.replacingOccurrences(of: tok, with: val)
        }

        // Handle {counter:N}
        if let regex = try? NSRegularExpression(pattern: "\\{counter:(\\d+)\\}") {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                if m.numberOfRanges > 1 {
                    let n = Int(ns.substring(with: m.range(at: 1))) ?? context.counterDigits
                    let pad = String(format: "%0\(n)d", context.counter)
                    result = (result as NSString).replacingCharacters(in: m.range, with: pad) as String
                }
            }
        }

        // Ensure extension present if template omitted {ext}
        if !result.lowercased().hasSuffix("." + context.ext.lowercased()) && !context.ext.isEmpty {
            result += "." + context.ext
        }

        // Sanitize path separators and control chars
        result = result.replacingOccurrences(of: "/", with: "-")
        result = result.replacingOccurrences(of: ":", with: "-")
        return result
    }

    private static func sanitize(_ s: String) -> String {
        var out = s
        // Replace whitespace runs with a single hyphen for camera names etc. is too aggressive;
        // keep spaces but strip path separators.
        out = out.replacingOccurrences(of: "/", with: "-")
        out = out.replacingOccurrences(of: ":", with: "-")
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Resolve a unique filename in targetDir, appending -1, -2, ... on conflict.
    static func uniqueFilename(in dir: URL, proposed: String, fm: FileManager = .default) -> String {
        let proposedURL = dir.appendingPathComponent(proposed)
        if !fm.fileExists(atPath: proposedURL.path) { return proposed }
        let stem = (proposed as NSString).deletingPathExtension
        let ext = (proposed as NSString).pathExtension
        var i = 1
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)"
            if !fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
                return candidate
            }
            i += 1
            if i > 10000 { return proposed } // safety
        }
    }
}