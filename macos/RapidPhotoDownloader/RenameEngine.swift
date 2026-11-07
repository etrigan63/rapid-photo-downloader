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

    /// Image number extracted from the original filename (digits immediately
    /// before the extension), mirroring RPD's NUMBER_SOURCE=exif behaviour.
    /// Falls back to the session counter when the name has no trailing digits.
    var imageNumber: String {
        let stem = originalStem
        // trailing digit run
        var i = stem.count
        let chars = Array(stem)
        while i > 0 && chars[i-1].isNumber { i -= 1 }
        let digits = String(chars[i...])
        if digits.isEmpty { return String(format: "%0\(counterDigits)d", counter) }
        // pad to counterDigits if shorter
        if digits.count < counterDigits {
            return String(repeating: "0", count: counterDigits - digits.count) + digits
        }
        return digits
    }
}

enum RenameEngine {
    /// Read camera make/model from image metadata or video sidecar/exiftool.
    static func cameraInfo(url: URL) -> (make: String, model: String) {
        let ext = url.pathExtension.lowercased()
        let videoExts: Set<String> = ["mp4","mov","m4v","avi","mts","m2ts","3gp","mod"]
        if videoExts.contains(ext) {
            // 1. Sony sidecar XML: C0028.MP4 -> C0028M01.XML
            let sidecar = url.deletingPathExtension().appendingPathExtension("M01.XML")
            // Actually Sony naming: C0028M01.XML
            let altSidecar = url.deletingLastPathComponent()
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "M01.XML")
            for sc in [sidecar, altSidecar] {
                if let data = try? Data(contentsOf: sc),
                   let xml = String(data: data, encoding: .utf8) {
                    if let range = xml.range(of: "modelName=\"") {
                        let after = xml[range.upperBound...]
                        if let end = after.firstIndex(of: "\"") {
                            let model = String(after[..<end])
                            // manufacturer
                            var make = ""
                            if let mr = xml.range(of: "manufacturer=\"") {
                                let a = xml[mr.upperBound...]
                                if let e = a.firstIndex(of: "\"") { make = String(a[..<e]) }
                            }
                            if !model.isEmpty { return (make, model) }
                        }
                    }
                }
            }
            // 2. exiftool fallback
            if let exif = runExiftool(url: url) {
                let model = exif["DeviceModelName"] ?? exif["CameraModelName"] ?? exif["Model"] ?? ""
                let make = exif["Make"] ?? exif["Manufacturer"] ?? ""
                if !model.isEmpty { return (make, model) }
            }
            return ("", "UNKNOWN")
        }
        // Images: ImageIO
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

    private static func runExiftool(url: URL) -> [String: String]? {
        let exiftoolPath = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "exiftool"]
            .first { FileManager.default.isExecutableFile(atPath: $0) || $0 == "exiftool" } ?? "exiftool"
        guard let exe = (exiftoolPath == "exiftool" ? (shellWhich("exiftool") ?? nil) : exiftoolPath) as String? else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = ["-s", "-s", "-s", "-j", "-DeviceModelName", "-CameraModelName", "-Model", "-Make", "-Manufacturer", url.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let dict = arr.first else { return nil }
        var out: [String: String] = [:]
        for (k,v) in dict {
            if let s = v as? String { out[k] = s }
        }
        return out
    }

    private static func shellWhich(_ cmd: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [cmd]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
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
            ("{imageNumber}", context.imageNumber),
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