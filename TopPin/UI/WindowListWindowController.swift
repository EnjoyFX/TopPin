import AppKit
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "WindowListVC")

// MARK: - Window controller

/// Main window: lists all accessible windows, lets the user pin/unpin or use click-to-pick.
final class WindowListWindowController: NSWindowController, NSWindowDelegate {

    private let pinnedController: PinnedWindowController
    private let preferences: PreferencesStore

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var pinButton: NSButton!
    private var unpinButton: NSButton!
    private var refreshButton: NSButton!
    private var pickButton: NSButton!
    private var statusLabel: NSTextField!
    private var windows: [WindowRef] = []
    private let enumerator = WindowEnumerator()
    private let picker     = WindowPicker()

    // MARK: - Init

    init(pinnedController: PinnedWindowController, preferences: PreferencesStore) {
        self.pinnedController = pinnedController
        self.preferences      = preferences

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask:   [.titled, .closable, .miniaturizable, .resizable],
            backing:     .buffered,
            defer:       false
        )
        window.title    = "TopPin – Select Window"
        window.minSize  = NSSize(width: 480, height: 380)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        refresh()
        observeState()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - UI construction

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // Table
        let col1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        col1.title = "Application"
        col1.width = 180

        let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        col2.title = "Window Title"
        col2.width = 280

        let col3 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pid"))
        col3.title = "PID"
        col3.width = 60

        let col4 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bounds"))
        col4.title = "Bounds"
        col4.width = 140

        tableView = NSTableView()
        tableView.addTableColumn(col1)
        tableView.addTableColumn(col2)
        tableView.addTableColumn(col3)
        tableView.addTableColumn(col4)
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.target = self
        tableView.doubleAction = #selector(pinSelected)

        scrollView = NSScrollView()
        scrollView.documentView      = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask  = [.width, .height]
        scrollView.frame = NSRect(x: 0, y: 120, width: 680, height: 440)
        cv.addSubview(scrollView)

        // Toolbar row
        let toolbarY: CGFloat = 80

        refreshButton = NSButton(title: "↻ Refresh",
                                  target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 12, y: toolbarY, width: 90, height: 28)
        cv.addSubview(refreshButton)

        pickButton = NSButton(title: "⊕ Click to Pick",
                               target: self, action: #selector(startClickPick))
        pickButton.bezelStyle = .rounded
        pickButton.frame = NSRect(x: 108, y: toolbarY, width: 128, height: 28)
        cv.addSubview(pickButton)

        pinButton = NSButton(title: "Pin Selected  ⌥⌘P",
                              target: self, action: #selector(pinSelected))
        pinButton.bezelStyle   = .rounded
        pinButton.keyEquivalent = "\r"
        pinButton.frame = NSRect(x: 330, y: toolbarY, width: 170, height: 28)
        cv.addSubview(pinButton)

        unpinButton = NSButton(title: "Unpin",
                                target: self, action: #selector(unpinAction))
        unpinButton.bezelStyle = .rounded
        unpinButton.frame = NSRect(x: 506, y: toolbarY, width: 80, height: 28)
        cv.addSubview(unpinButton)

        // Status / info strip
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font      = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame     = NSRect(x: 12, y: 50, width: 656, height: 22)
        cv.addSubview(statusLabel)

        updateButtons()
    }

    // MARK: - State observation

    private func observeState() {
        pinnedController.addStateObserver { [weak self] state in self?.handleStateChange(state) }
    }

    private func handleStateChange(_ state: PinState) {
        updateButtons()
        switch state {
        case .idle:
            statusLabel.stringValue = "Idle – no window pinned."
        case .pinning(let ref):
            statusLabel.stringValue = "📌 Pinning: \(ref.appName) – \(ref.displayTitle)"
        case .error(let msg):
            statusLabel.stringValue = "⚠ \(msg)"
        }
    }

    // MARK: - Actions

    @objc private func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let all = self.enumerator.enumerateWindows()
            DispatchQueue.main.async {
                self.windows = all
                self.tableView.reloadData()
                self.updateButtons()
                // Highlight previously pinned window
                if let pinned = self.pinnedController.pinnedWindow,
                   let idx = self.windows.firstIndex(of: pinned) {
                    self.tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                    self.tableView.scrollRowToVisible(idx)
                }
            }
        }
    }

    @objc private func pinSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < windows.count else { return }
        let ref = windows[row]
        pinnedController.pin(ref)
        statusLabel.stringValue = "📌 Pinning: \(ref.appName) – \(ref.displayTitle)"
        updateButtons()
    }

    @objc private func unpinAction() {
        pinnedController.unpin()
        updateButtons()
    }

    @objc private func startClickPick() {
        // Hide this window while picking
        window?.orderOut(nil)
        picker.startClickToPickMode { [weak self] ref in
            guard let self else { return }
            self.window?.makeKeyAndOrderFront(nil)
            if let ref {
                self.pinnedController.pin(ref)
                self.refresh()
                self.statusLabel.stringValue = "📌 Pinning: \(ref.appName) – \(ref.displayTitle)"
            } else {
                self.statusLabel.stringValue = "Click-to-pick cancelled."
            }
            self.updateButtons()
        }
    }

    // MARK: - Helpers

    private func updateButtons() {
        pinButton.isEnabled   = tableView.selectedRow >= 0
        unpinButton.isEnabled = pinnedController.isPinned
    }

    // NSWindowDelegate
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}

// MARK: - Table data source

extension WindowListWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { windows.count }
}

// MARK: - Table delegate

extension WindowListWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < windows.count else { return nil }
        let win = windows[row]

        let id = NSUserInterfaceItemIdentifier("cell")
        var cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView

        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.identifier = NSUserInterfaceItemIdentifier("textField")
            cell?.addSubview(tf)
            cell?.textField = tf
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                tf.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                tf.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4)
            ])
        }

        let isPinned = pinnedController.pinnedWindow == win

        switch tableColumn?.identifier.rawValue {
        case "app":
            cell?.textField?.stringValue = win.appName
            cell?.textField?.font = NSFont.systemFont(ofSize: 12,
                weight: isPinned ? .semibold : .regular)
        case "title":
            cell?.textField?.stringValue = (isPinned ? "📌 " : "") + win.displayTitle
            cell?.textField?.font = NSFont.systemFont(ofSize: 12,
                weight: isPinned ? .semibold : .regular)
        case "pid":
            cell?.textField?.stringValue = "\(win.pid)"
            cell?.textField?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        case "bounds":
            let b = win.bounds
            cell?.textField?.stringValue = String(format: "%d×%d",
                Int(b.width), Int(b.height))
            cell?.textField?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        default: break
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }
}
