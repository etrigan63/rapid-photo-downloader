import Cocoa
import UniformTypeIdentifiers
import Foundation

// MARK: - Supported extensions

let photoExts: Set<String> = ["jpg","jpeg","jpe","tif","tiff","png","gif","bmp",
    "heic","heif","hif","nef","cr2","cr3","arw","dng","orf","rw2","raf","pef","raw"]
let videoExts: Set<String> = ["mp4","mov","m4v","avi","mts","m2ts","3gp"]

func isMediaFile(_ url: URL) -> Bool {
    photoExts.contains(url.pathExtension.lowercased()) ||
    videoExts.contains(url.pathExtension.lowercased())
}

// MARK: - Model

struct MediaItem {
    let url: URL
    let captureDate: Date
    var status: Status = .pending
    enum Status { case pending, copied, skipped, failed }
}

// MARK: - App delegate / main window

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var controller: MainController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MainController()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Rapid Photo Downloader — macOS native (Phase 2)"
        window.center()
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Main controller (view controller)

final class MainController: NSViewController {
    // State
    var sourceURL: URL?
    var destURL: URL?
    var items: [MediaItem] = []
    var isRunning = false

    // UI
    let sourceLabel = NSTextField(labelWithString: "No source selected")
    let destLabel = NSTextField(labelWithString: "No destination selected")
    let countLabel = NSTextField(labelWithString: "Files: 0")
    let progress = NSProgressIndicator()
    let progressLabel = NSTextField(labelWithString: "")
    let importButton = NSButton(title: "Import", target: nil, action: nil)
    let logView = NSTextView()
    let collectionView = NSCollectionView()
    let scrollView = NSScrollView()

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])

        // Title
        let title = NSTextField(labelWithString: "Rapid Photo Downloader — macOS native (Phase 2)")
        title.font = NSFont.boldSystemFont(ofSize: 16)
        stack.addArrangedSubview(title)

        // Source row
        let srcRow = NSStackView()
        srcRow.orientation = .horizontal
        srcRow.spacing = 8
        let srcBtn = NSButton(title: "Choose Source…", target: self, action: #selector(chooseSource))
        srcRow.addArrangedSubview(srcBtn)
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        srcRow.addArrangedSubview(sourceLabel)
        stack.addArrangedSubview(srcRow)
        srcRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Dest row
        let dstRow = NSStackView()
        dstRow.orientation = .horizontal
        dstRow.spacing = 8
        let dstBtn = NSButton(title: "Choose Destination…", target: self, action: #selector(chooseDest))
        dstRow.addArrangedSubview(dstBtn)
        destLabel.lineBreakMode = .byTruncatingMiddle
        destLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dstRow.addArrangedSubview(destLabel)
        stack.addArrangedSubview(dstRow)
        dstRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Import row
        let impRow = NSStackView()
        impRow.orientation = .horizontal
        impRow.spacing = 8
        importButton.target = self
        importButton.action = #selector(startImport)
        impRow.addArrangedSubview(importButton)
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0
        progress.widthAnchor.constraint(equalToConstant: 200).isActive = true
        impRow.addArrangedSubview(progress)
        impRow.addArrangedSubview(progressLabel)
        stack.addArrangedSubview(impRow)

        stack.addArrangedSubview(countLabel)

        // Collection view (thumbnails)
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 108, height: 128)
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.register(ThumbItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("ThumbItem"))
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        stack.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Log view
        logView.isEditable = false
        logView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let logScroll = NSScrollView()
        logScroll.documentView = logView
        logScroll.hasVerticalScroller = true
        logScroll.autohidesScrollers = true
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.heightAnchor.constraint(equalToConstant: 130).isActive = true
        stack.addArrangedSubview(logScroll)
        logScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        self.view = root
    }

    // MARK: - Actions

    @objc func chooseSource() {
        if let url = openPanel(title: "Choose source folder", dirs: true) {
            sourceURL = url
            sourceLabel.stringValue = url.path
            scan()
        }
    }

    @objc func chooseDest() {
        if let url = openPanel(title: "Choose destination folder", dirs: true) {
            destURL = url
            destLabel.stringValue = url.path
        }
    }

    func scan() {
        guard let src = sourceURL else { return }
        items.removeAll()
        let fm = FileManager.default
        if let en = fm.enumerator(at: src, includingPropertiesForKeys: [.isRegularFileKey],
                                  options: [.skipsHiddenFiles]) {
            for case let u as URL in en {
                if isMediaFile(u) {
                    items.append(MediaItem(url: u, captureDate: HEIFThumbnail.captureDate(url: u)))
                }
            }
        }
        items.sort { $0.captureDate < $1.captureDate }
        countLabel.stringValue = "Files: \(items.count)"
        log("Scanned \(items.count) media files.")
        collectionView.reloadData()
    }

    @objc func startImport() {
        guard let dest = destURL, !items.isEmpty, !isRunning else { return }
        isRunning = true
        importButton.isEnabled = false
        progress.doubleValue = 0
        progressLabel.stringValue = ""

        let workItems = items
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var updated = workItems
            let total = Double(workItems.count)
            for i in updated.indices {
                let item = updated[i]
                let df = DateFormatter()
                df.dateFormat = "yyyy"
                let year = df.string(from: item.captureDate)
                df.dateFormat = "yyyy-MM-dd"
                let day = df.string(from: item.captureDate)
                let targetDir = dest.appendingPathComponent(year).appendingPathComponent(day)
                do {
                    try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
                    let target = targetDir.appendingPathComponent(item.url.lastPathComponent)
                    if fm.fileExists(atPath: target.path) {
                        updated[i].status = .skipped
                        self?.log("Skip (exists): \(item.url.lastPathComponent)")
                    } else {
                        try fm.copyItem(at: item.url, to: target)
                        updated[i].status = .copied
                        self?.log("Copied: \(item.url.lastPathComponent) → \(year)/\(day)/")
                    }
                } catch {
                    updated[i].status = .failed
                    self?.log("FAILED \(item.url.lastPathComponent): \(error.localizedDescription)")
                }
                let done = Double(i + 1)
                DispatchQueue.main.async {
                    self?.items = updated
                    self?.progress.doubleValue = done / total
                    self?.progressLabel.stringValue = "\(Int(done))/\(Int(total))"
                    self?.collectionView.reloadData()
                }
            }
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.importButton.isEnabled = true
                let copied = updated.filter { $0.status == .copied }.count
                self?.log("Done. \(copied) copied.")
            }
        }
    }

    func log(_ msg: String) {
        DispatchQueue.main.async { [weak self] in
            self?.logView.textStorage?.append(NSAttributedString(string: msg + "\n"))
            self?.logView.scrollToEndOfDocument(nil)
        }
    }

    func openPanel(title: String, dirs: Bool) -> URL? {
        let p = NSOpenPanel()
        p.title = title
        p.canChooseFiles = !dirs
        p.canChooseDirectories = dirs
        p.allowsMultipleSelection = false
        return p.runModal() == .OK ? p.url : nil
    }
}

// MARK: - Collection view data source

extension MainController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("ThumbItem"), for: indexPath)
        let media = items[indexPath.item]
        if let thumbItem = item as? ThumbItem {
            thumbItem.configure(url: media.url, status: media.status)
        }
        return item
    }
}

final class ThumbItem: NSCollectionViewItem {
    let thumbImageView = NSImageView()
    let captionLabel = NSTextField(labelWithString: "")
    let badge = NSTextField(labelWithString: "")

    override func loadView() {
        let v = NSView()
        thumbImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbImageView.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.font = NSFont.systemFont(ofSize: 9)
        captionLabel.lineBreakMode = .byTruncatingMiddle
        captionLabel.alignment = .center
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        badge.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        badge.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(thumbImageView)
        v.addSubview(captionLabel)
        v.addSubview(badge)
        NSLayoutConstraint.activate([
            thumbImageView.topAnchor.constraint(equalTo: v.topAnchor, constant: 4),
            thumbImageView.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            thumbImageView.widthAnchor.constraint(equalToConstant: 96),
            thumbImageView.heightAnchor.constraint(equalToConstant: 96),
            captionLabel.topAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: 2),
            captionLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 2),
            captionLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -2),
            badge.topAnchor.constraint(equalTo: v.topAnchor, constant: 4),
            badge.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
        ])
        self.view = v
    }

    func configure(url: URL, status: MediaItem.Status) {
        captionLabel.stringValue = url.lastPathComponent
        thumbImageView.image = HEIFThumbnail.thumbnail(url: url, maxPixel: 192)
        switch status {
        case .pending: badge.stringValue = ""
        case .copied: badge.stringValue = "✓"; badge.textColor = .systemGreen
        case .skipped: badge.stringValue = "→"; badge.textColor = .systemOrange
        case .failed: badge.stringValue = "✗"; badge.textColor = .systemRed
        }
    }
}

// MARK: - Main

@main
struct RapidPhotoDownloaderMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}