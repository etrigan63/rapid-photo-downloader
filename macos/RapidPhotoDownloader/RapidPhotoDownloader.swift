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
    var preferencesWindow: NSWindow?
    var preferencesController: PreferencesController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        controller = MainController()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Rapid Photo Downloader — macOS native (Phase 2)"
        window.center()
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
    }

    @objc func openPreferences(_ sender: Any?) {
        if preferencesController == nil {
            let pc = PreferencesController()
            preferencesController = pc
            preferencesWindow = pc.window
            pc.showWindow(nil)
            pc.window?.makeKeyAndOrderFront(nil)
        } else {
            preferencesWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Standard macOS menu bar

func buildMainMenu() -> NSMenu {
    let mainMenu = NSMenu()

    // Application menu
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenuItem.submenu = appMenu
    appMenu.addItem(withTitle: "About Rapid Photo Downloader", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(NSMenuItem.separator())
    let prefs = NSMenuItem(title: "Preferences…", action: #selector(AppDelegate.openPreferences(_:)), keyEquivalent: ",")
    prefs.target = NSApp.delegate
    appMenu.addItem(prefs)
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(withTitle: "Hide Rapid Photo Downloader", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(hideOthers)
    appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(withTitle: "Quit Rapid Photo Downloader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    // File menu
    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)
    let fileMenu = NSMenu(title: "File")
    fileMenuItem.submenu = fileMenu
    fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    // Edit menu
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenuItem.submenu = editMenu
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    // View menu
    let viewMenuItem = NSMenuItem()
    mainMenu.addItem(viewMenuItem)
    let viewMenu = NSMenu(title: "View")
    viewMenuItem.submenu = viewMenu

    // Window menu
    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: "Window")
    windowMenuItem.submenu = windowMenu
    NSApp.windowsMenu = windowMenu
    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
    windowMenu.addItem(NSMenuItem.separator())
    windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

    // Help menu
    let helpMenuItem = NSMenuItem()
    mainMenu.addItem(helpMenuItem)
    let helpMenu = NSMenu(title: "Help")
    helpMenuItem.submenu = helpMenu
    NSApp.helpMenu = helpMenu

    return mainMenu
}

// MARK: - Main controller (view controller)

final class MainController: NSViewController {
    // State
    var sourceURL: URL?
    var destURL: URL?
    var items: [MediaItem] = []
    var isRunning = false
    var config = RPDConfig.load()

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

    override func viewDidLoad() {
        super.viewDidLoad()
        if destURL == nil, let d = config.resolvedDestination {
            destURL = d
            destLabel.stringValue = d.path
        }
        if let s = sourceURL { sourceLabel.stringValue = s.path }
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
        let config = RPDConfig.load()
        var sessionCounter = 1

        let workItems = items
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var updated = workItems
            let total = Double(workItems.count)
            for i in updated.indices {
                let item = updated[i]
                let relative = config.formattedFolder(for: item.captureDate)
                let targetDir = relative.split(separator: "/").reduce(dest) { $0.appendingPathComponent(String($1)) }
                do {
                    try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
                    let (make, model) = RenameEngine.cameraInfo(url: item.url)
                    let ctx = RenameContext(url: item.url, date: item.captureDate,
                                           cameraMake: make, cameraModel: model,
                                           counter: sessionCounter, counterDigits: config.counterDigits)
                    let proposed = RenameEngine.apply(template: config.renameTemplate, context: ctx)
                    let finalName = RenameEngine.uniqueFilename(in: targetDir, proposed: proposed)
                    sessionCounter += 1
                    let target = targetDir.appendingPathComponent(finalName)
                    if fm.fileExists(atPath: target.path) {
                        updated[i].status = .skipped
                        self?.log("Skip (exists): \(finalName)")
                    } else {
                        try fm.copyItem(at: item.url, to: target)
                        updated[i].status = .copied
                        self?.log("Copied: \(item.url.lastPathComponent) → \(relative)/\(finalName)")
                    }
                    // Backup copy
                    if let backupRoot = config.resolvedBackup {
                        let backupDir = relative.split(separator: "/").reduce(backupRoot) { $0.appendingPathComponent(String($1)) }
                        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                        let backupTarget = backupDir.appendingPathComponent(finalName)
                        if !fm.fileExists(atPath: backupTarget.path) {
                            try? fm.copyItem(at: item.url, to: backupTarget)
                        }
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

// MARK: - Preferences window

final class PreferencesController: NSWindowController, NSWindowDelegate {
    let destField = NSTextField()
    let backupField = NSTextField()
    let backupCheck = NSButton(checkboxWithTitle: "Enable backup copy", target: nil, action: nil)
    let patternField = NSTextField()
    let renameField = NSTextField()
    let videosCheck = NSButton(checkboxWithTitle: "Include videos", target: nil, action: nil)
    let counterField = NSTextField()
    let thumbField = NSTextField()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Preferences"
        super.init(window: window)
        window.delegate = self
        window.contentViewController = buildContent()
        loadFields()
    }

    required init?(coder: NSCoder) { fatalError() }

    func buildContent() -> NSViewController {
        let vc = NSViewController()
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        vc.view = root
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16),
        ])

        let title = NSTextField(labelWithString: "Preferences")
        title.font = NSFont.boldSystemFont(ofSize: 14)
        stack.addArrangedSubview(title)

        func row(_ label: String, _ field: NSTextField, browse: Selector? = nil) -> NSStackView {
            let l = NSTextField(labelWithString: label)
            l.alignment = .right
            l.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            field.bezelStyle = .roundedBezel
            field.isBordered = true
            field.drawsBackground = true
            field.backgroundColor = .textBackgroundColor
            let r = NSStackView(views: [l, field])
            r.orientation = .horizontal
            r.spacing = 8
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            if let sel = browse {
                let btn = NSButton(title: "Browse…", target: self, action: sel)
                r.addArrangedSubview(btn)
            }
            return r
        }

        stack.addArrangedSubview(row("Destination root:", destField, browse: #selector(browseDest)))
        stack.addArrangedSubview(row("Backup root:", backupField, browse: #selector(browseBackup)))
        stack.addArrangedSubview(backupCheck)
        stack.addArrangedSubview(row("Folder pattern:", patternField))
        stack.addArrangedSubview(row("Rename template:", renameField))
        stack.addArrangedSubview(videosCheck)
        stack.addArrangedSubview(row("Counter digits:", counterField))
        stack.addArrangedSubview(row("Thumbnail size:", thumbField))

        let hint = NSTextField(labelWithString: "Folder pattern: %Y %m %d. Rename tokens: {original} {ext} {date} {datetime} {camera} {make} {counter} {counter:N} {imageNumber}")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save))
        let exportBtn = NSButton(title: "Export Config…", target: self, action: #selector(exportConfig))
        let importBtn = NSButton(title: "Import Config…", target: self, action: #selector(importConfig))
        btnRow.addArrangedSubview(saveBtn)
        btnRow.addArrangedSubview(exportBtn)
        btnRow.addArrangedSubview(importBtn)
        stack.addArrangedSubview(btnRow)

        return vc
    }

    func loadFields() {
        let c = RPDConfig.load()
        destField.stringValue = c.destinationRoot
        destField.placeholderString = "~/Pictures/Rapid"
        backupField.stringValue = c.backupRoot
        backupField.placeholderString = "~/Pictures/Rapid Backup"
        backupCheck.state = c.backupEnabled ? .on : .off
        patternField.stringValue = c.folderPattern
        renameField.stringValue = c.renameTemplate
        renameField.placeholderString = "{original}"
        videosCheck.state = c.includeVideos ? .on : .off
        counterField.stringValue = String(c.counterDigits)
        thumbField.stringValue = String(c.thumbnailSize)
    }

    func collectConfig() -> RPDConfig {
        var c = RPDConfig()
        c.destinationRoot = destField.stringValue
        c.backupRoot = backupField.stringValue
        c.backupEnabled = (backupCheck.state == .on)
        c.folderPattern = patternField.stringValue.isEmpty ? "%Y/%Y-%m-%d" : patternField.stringValue
        c.renameTemplate = renameField.stringValue.isEmpty ? "{original}" : renameField.stringValue
        c.includeVideos = (videosCheck.state == .on)
        c.counterDigits = Int(counterField.stringValue) ?? 4
        c.thumbnailSize = Int(thumbField.stringValue) ?? 200
        return c
    }

    @objc func browseDest() {
        if let url = openFolderPanel(title: "Choose destination folder") {
            destField.stringValue = url.path
        }
    }

    @objc func browseBackup() {
        if let url = openFolderPanel(title: "Choose backup folder") {
            backupField.stringValue = url.path
        }
    }

    private func openFolderPanel(title: String) -> URL? {
        let p = NSOpenPanel()
        p.title = title
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url : nil
    }

    @objc func save() {
        collectConfig().save()
        if let mc = (NSApp.delegate as? AppDelegate)?.controller {
            let c = RPDConfig.load()
            if mc.destURL == nil, let d = c.resolvedDestination {
                mc.destURL = d
                mc.destLabel.stringValue = d.path
            }
            mc.config = c
        }
    }

    @objc func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "rapid-photo-downloader-config.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try collectConfig().export(to: url)
            } catch {
                let a = NSAlert()
                a.messageText = "Export failed"
                a.informativeText = error.localizedDescription
                a.runModal()
            }
        }
    }

    @objc func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let c = try RPDConfig.load(from: url)
                c.save()
                loadFields()
            } catch {
                let a = NSAlert()
                a.messageText = "Import failed"
                a.informativeText = error.localizedDescription
                a.runModal()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.preferencesWindow = nil
        (NSApp.delegate as? AppDelegate)?.preferencesController = nil
    }
}

@main
struct RapidPhotoDownloaderMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}