# macOS Native Conversion Analysis — Rapid Photo Downloader

**Source:** `/Volumes/BigData/GitHub/rapid-photo-downloader` (upstream `damonlynch/rapid-photo-downloader`, forked to `etrigan63/rapid-photo-downloader`)
**Date:** 2026-10-21
**Scope:** Convert the Linux desktop application to a native macOS application, including fixing HEIF/HEIC thumbnail rendering.

---

## 1. Executive summary

Rapid Photo Downloader (RPD) is a large, mature, **single-developer** Python/PyQt5 desktop application (~91 kLOC across 102 modules) that imports, renames, and backs up photos/videos from cameras, phones, memory cards, and folders. Its architecture is explicitly **multi-process**: a Qt GUI process orchestrates several worker processes (scanner, thumbnail extractors, copiers, metadata readers) that communicate over **ZeroMQ**.

A faithful "native macOS" conversion is therefore **not a port of a few platform calls** — it is effectively a **rewrite** of the platform and device layers, and a decision point on the UI and concurrency models. The recommended strategy is a **phased, vertical-slice port** that reuses proven macOS frameworks (ImageCaptureCore, DiskArbitration, IOKit, ImageIO/QuickLook, FSEvents) rather than emulating Linux subsystems (udev, GVFS, gphoto2, libimobiledevice, XDG).

**HEIF thumbnails** are a concrete, independently solvable problem: the Linux build depends on the optional `pillow-heif`/`libheif` stack and silently disables HEIF thumbnails when those are absent. On macOS, **ImageIO (`CGImageSource`) decodes HEIF/HEIC natively with no third-party dependency**, so the macOS version should generate thumbnails through ImageIO (with QuickLook as a fallback for formats ImageIO cannot decode). A working Swift proof-of-concept is included in `macos/HEIFThumbnail/`.

---

## 2. What the application does (functional inventory)

Core capabilities (from README + code):

- Detect and import from:
  - PTP/MTP cameras via **libgphoto2** (`raphodo/camera.py`)
  - iOS devices via **libimobiledevice** + `ifuse`/`fusermount` (`storage/storageidevice.py`)
  - Mounted volumes / SD cards / arbitrary folders (`storage/storage.py`, `devices.py`, `scan.py`)
  - WSL paths (`wsl/`)
- Organise by EXIF/metadata date, rename by user templates (`generatename.py`, `renameandmovefile.py`)
- Backup to a second location during import (`copyfiles.py`, `backupfile.py`)
- Thumbnail filmstrip + proximity grouping (`thumbnail*.py`, `proximity.py`, `folderspreview.py`)
- Device add/remove monitoring, auto-unmount, eject (`storage/storage.py`)
- Multi-core thumbnail extraction via worker processes (`thumbnailpara.py`, `thumbnailextractor.py`, `thumbnaildaemon.py`)
- SQLite thumbnail + metadata cache (`cache.py`, `rpdsql.py`)
- Notifications (libnotify, Unity launcher) (`problemnotification.py`, `rapid.py`)
- Dark/light theming, GNOME palette, Cinnamon/COSMIC platform tweaks (`ui/*`, `tools/*platform*.py`)
- Internationalisation via gettext (`po/`, `internationalisation/`)

Scale: **102 Python modules, ~91.5 kLOC**; tests in `raphodo/tests/`; Qt `.ui`-free (all widgets built in code).

---

## 3. Architecture

```
┌──────────────────────────────┐
│  Qt GUI process (rapid.py)    │  PyQt5, widgets, preferences, signals
│  ├── ZeroMQ PUB/SUB broker   │
│  └── Device monitor (GIO/udev)│
└──────┬──────────┬────────────┘
       │ ZMQ      │ fork/spawn
┌──────▼──┐  ┌────▼────────┐  ┌────────────┐
│ Scanner │  │ Thumbnail   │  │ Copier /   │
│ (scan)  │  │ Extractors  │  │ Renamer    │
└─────────┘  └─────────────┘  └────────────┘
       │              │               │
       └──── SQLite cache + filesystem ────┘
```

- Concurrency model = **OS processes** + ZeroMQ (chosen for Python GIL bypass).
- All platform integration lives in `storage/`, `tools/`, `camera.py`, `wsl/`.
- UI is entirely PyQt5 (`ui/`).

---

## 4. Linux-specific dependency inventory

| Dependency | Used in | Purpose | macOS replacement |
|---|---|---|---|
| PyQt5 | everywhere | GUI | SwiftUI / AppKit (or keep PyQt6, which runs on macOS) |
| PyGObject (`gi`) | storage, rapid, platformtools | GIO/GVFS/udev/UDisks/Notify/Unity | Remove; use native frameworks |
| `GUdev`, `UDisks` | storage/storage.py | device hotplug | IOKit + DiskArbitration + NSWorkspace |
| GVFS / `Gio` mounts | storage.py | camera/volume mounting | ImageCaptureCore (cameras), DiskArbitration (volumes) |
| libgphoto2 / `gphoto2` | camera.py | PTP camera access | ImageCaptureCore (`ICCameraDevice`) or keep gphoto2 via Homebrew |
| libimobiledevice + ifuse/fusermount | storageidevice.py | iOS access | ImageCaptureCore (iOS devices appear as cameras) or MobileDevice framework |
| exiftool (subprocess) | metadata/* | metadata read/write | ImageIO (`CGImageProperties`), AVFoundation, plus optional exiftool |
| `show-in-file-manager` | ui/*, renameandmovefile | reveal in FM | `NSWorkspace.shared.activateFileViewerSelecting` |
| `pyxdg` | tools, storage | XDG paths | `FileManager` / `NSSearchPathForDirectoriesInDomains` |
| `xsettings`, GNOME/Cinnamon/COSMIC | tools/*platform*.py | desktop theme | `NSAppearance` / system theme (no-op on macOS) |
| `Notify` (libnotify), Unity | rapid.py | notifications/launcher | `UserNotifications` framework |
| `psutil` | interprocess | process mgmt | Foundation/`ProcessInfo` (keep psutil; it works on macOS) |
| `zmq`/`tornado` | interprocess | IPC | XPC, `NSDistributedNotificationCenter`, or keep ZeroMQ (works on macOS) |
| Pillow + `pillow_heif` | heif.py, thumbnails | HEIF decode | **ImageIO (native, no dependency)** |
| `sortedcontainers`, `tenacity`, `arrow`, etc. | various | pure Python | keep or replace with Swift equivalents |

---

## 5. Component-by-component conversion plan

### 5.1 UI layer (`ui/`, `rapid.py`)
- **Option A (keep Python):** Migrate PyQt5 → PyQt6, adjust macOS-specific code paths. Fastest, but not "native" feel and packaging is awkward.
- **Option B (native):** Rewrite in **SwiftUI + AppKit**. Large but gives native look, menus, sheets, drag-and-drop, Quick Look. Given the user's existing `mac-photo-downloader` is Swift, Option B is consistent.
- **Recommendation:** Option B, but only after device + thumbnail vertical slices work. Keep UI shell minimal initially (single window + progress).

### 5.2 Concurrency / IPC (`interprocess.py`)
- The multi-process design exists to bypass the Python GIL. In Swift, use **GCD / Swift concurrency (actors, TaskGroups)** within a single process, or **XPC services** for isolation. Drop ZeroMQ entirely. Thumbnail extraction becomes a `TaskGroup` of actors.

### 5.3 Device detection (`storage/storage.py`, `camera.py`, `storageidevice.py`)
- Replace udev/GVFS/UDisks with:
  - **DiskArbitration framework** for volume mount/unmount/eject events.
  - **IOKit** for raw USB device arrival (optional).
  - **ImageCaptureCore** (`ICDeviceBrowser`) for cameras and iOS devices — this single framework covers most of what libgphoto2 + libimobiledevice did on Linux, and is the idiomatic macOS path.
  - **FSEvents** for folder watching.
- iOS: drop `ifuse`/`fusermount`; ImageCaptureCore exposes iOS media directly. If full filesystem access is needed, keep `libimobiledevice` via Homebrew as a fallback.

### 5.4 Metadata (`metadata/`)
- Replace exiftool subprocess calls with **ImageIO** (`CGImageSourceCopyPropertiesAtIndex`) for read, and `CGImageDestination` for write where supported.
- Keep exiftool as an optional backend for formats ImageIO cannot handle (some RAW, video). The existing `metadataexiftool.py` can remain as a fallback.

### 5.5 Thumbnails (incl. HEIF) — see §6
- Replace Pillow + pillow_heif with **CGImageSource thumbnail creation** + **QuickLook** fallback.
- Cache layer (`cache.py`, SQLite) can be reused via GRDB.swift or Core Data.

### 5.6 File operations (`copyfiles.py`, `renameandmovefile.py`)
- Pure Foundation/FileManager; straightforward port. Preserve atomic copy, progress reporting, and backup semantics.

### 5.7 Settings / paths
- XDG → `~/Library/Application Support/<bundle id>/`, `~/Library/Caches/`, `~/Library/Preferences/`. Use `UserDefaults` / `CFPreferences`.

### 5.8 Notifications
- libnotify/Unity → `UserNotifications` framework; dock badge via `NSApp.dockTile`.

### 5.9 Internationalisation
- gettext → Xcode String Catalogs (`.xcstrings`) or `.strings`/`.stringsdict`. Translation files in `po/` need conversion.

### 5.10 Packaging / distribution
- Replace hatch/pip with an Xcode project or Swift Package Manager + `xcodebuild`.
- Deliver as a signed, notarised `.app` bundle (see `mac-photo-downloader/build-app.sh` for a working precedent in this user's repo).
- No man page / desktop file; use `Info.plist`, app icon, Quick Actions (Automator) if desired.

---

## 6. HEIF thumbnail rendering (specific requirement)

### 6.1 Current Linux behaviour
`raphodo/heif.py` wraps `pillow_heif`:

```python
pillow_heif.register_heif_opener(thumbnails=False)
...
with Image.open(full_file_name) as pillow_image: ...
imageqt = ImageQt.ImageQt(pillow_image)
```

`raphodo/thumbnailpara.py` and `thumbnailextractor.py` only attempt HEIF loading when `have_heif_module` is True (i.e. `pillow_heif` importable **and** Pillow built against PyQt5). If either is missing, HEIF thumbnails are silently skipped — this is the reported "cannot render HEIF thumbnails" failure. Additionally, because `thumbnails=False`, the entire HEIF is decoded even when only a small preview is needed.

### 6.2 macOS native solution
macOS decodes HEIF/HEIC via **ImageIO** with no extra dependencies. Thumbnail generation:

```swift
import ImageIO, CoreGraphics

func heifThumbnail(url: URL, maxPixel: Int) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}
```

- Handles HEIF/HEIC/AVIF (where supported by OS), JPEG, PNG, TIFF, and most RAW via Core Image RAW.
- Respects EXIF orientation via `kCGImageSourceCreateThumbnailWithTransform`.
- Embedded-thumbnail fast path: set `kCGImageSourceCreateThumbnailFromImageAlways` to `false` to prefer an embedded preview when present (much faster for large RAW/HEIF); fall back to `true` if nil.
- For formats ImageIO cannot decode, fall back to **QuickLook** (`QLThumbnailGenerator` on macOS 10.15+), which covers Office docs, PDFs, and additional RAW/HEIF variants.

A runnable proof-of-concept is provided at `macos/HEIFThumbnail/` (build with `swiftc -O -o heifthumb heifthumb.swift`; tested against `/Library/User Pictures/Flowers/Lotus.heic` → 512×512 PNG).

### 6.3 Migration of HEIF handling
- Remove `raphodo/heif.py` dependency entirely in the macOS version.
- In thumbnail extraction, branch on file type: use ImageIO for all image types (including HEIF) instead of the current `is_heif()` special case.
- Cache decoded thumbnails as PNG/JPEG in the existing SQLite cache, keyed by file path + mtime + size.

---

## 7. Recommended phased roadmap

| Phase | Goal | Deliverable |
|---|---|---|
| 0 | Fork + baseline | Fork created (`etrigan63/rapid-photo-downloader`); this analysis committed. |
| 1 | HEIF thumbnail PoC | `macos/HEIFThumbnail/` (done) |
| 2 | Vertical slice: import one folder of JPEGs/HEIFs | Swift CLI that scans a folder, reads EXIF date via ImageIO, copies + renames, reports progress |
| 3 | Device slice: SD card detection | DiskArbitration-based volume watcher; reuse logic from `mac-photo-downloader` |
| 4 | Camera/iOS slice | ImageCaptureCore device browser |
| 5 | Thumbnail filmstrip UI | AppKit/SwiftUI filmstrip using ImageIO thumbnails + SQLite cache |
| 6 | Full feature parity | backups, rename templates, proximity grouping, preferences |
| 7 | Packaging | signed/notarised `.app`, Quick Action, Sparkle updates (optional) |

Estimated effort: **6–12 months of part-time work** for one developer, dominated by UI and device parity. The metadata/thumbnail/copy core is ~3–4 weeks.

---

## 8. Risks & open questions

- **libgphoto2 feature parity:** ImageCaptureCore covers most cameras but may lack vendor-specific features (bulb, tethering). Decision needed: keep gphoto2 via Homebrew as an optional backend or drop.
- **iOS filesystem access:** ImageCaptureCore gives media only; full filesystem (for non-media files) needs libimobiledevice. Scope decision.
- **RAW coverage:** ImageIO RAW support varies by camera; exiftool/Adobe DNG Converter may still be needed for previews.
- **Performance:** Python's multi-process model achieved high throughput; Swift's GCD must be benchmarked against `test_thumbnail.py`/`test_thumbnailpara.py` scenarios.
- **Licensing:** RPD is GPL-3.0+. A native rewrite can remain GPL or choose another license if all code is original. Decide before publishing.
- **Translations:** 30+ languages in `po/`; conversion to Xcode catalogs is mechanical but large.
- **Testing:** Existing tests are Python/pytest; need new Swift test targets (XCTest).

---

## 9. Suggested repository layout for the native work

```
rapid-photo-downloader/
├── raphodo/                  # original Linux app (unchanged, reference)
├── macos/
│   ├── HEIFThumbnail/        # proven HEIF thumbnail utility
│   ├── RapidPhotoDownloader/ # new Xcode project (Phase 2+)
│   └── Shared/               # cross-cutting Swift packages
├── docs/                     # design notes
└── MACOS_CONVERSION_ANALYSIS.md
```

---

## 10. Appendix — key source files to port first

| Linux module | Responsibility | macOS counterpart |
|---|---|---|
| `rapid.py` | app entry, main window | SwiftUI `App` + `WindowGroup` |
| `scan.py` | file discovery + grouping | `FileManager` enumerator + actor |
| `rpdfile.py` | file model | Swift struct + `Codable` |
| `metadata/metadataphoto.py` | EXIF read | ImageIO |
| `generatename.py` | rename templates | Swift string interpolation engine |
| `copyfiles.py` | copy + progress | `FileManager.copyItem` + progress |
| `cache.py` / `rpdsql.py` | SQLite cache | GRDB.swift |
| `thumbnailpara.py` / `thumbnailextractor.py` | thumbnail workers | ImageIO + TaskGroup |
| `storage/storage.py` | devices + hotplug | DiskArbitration + IOKit |
| `camera.py` | gphoto2 | ImageCaptureCore |
| `storageidevice.py` | iOS | ImageCaptureCore |
| `devices.py` | device collection | Observable store |
| `interprocess.py` | ZeroMQ IPC | remove (in-process) |

---

*End of analysis.*
