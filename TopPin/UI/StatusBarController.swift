import AppKit
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "StatusBar")

/// Manages the NSStatusItem (menu-bar icon + menu).
@MainActor
final class StatusBarController {

    // MARK: - Callbacks
    var onSelectWindow: (() -> Void)?
    var onPreferences:  (() -> Void)?

    // MARK: - Private
    private let statusItem: NSStatusItem
    private var pinnedController: PinnedWindowController
    private var preferences: PreferencesStore

    private var pinMenuItem: NSMenuItem!
    private var windowNameMenuItem: NSMenuItem!

    // MARK: - Init

    init(pinnedController: PinnedWindowController, preferences: PreferencesStore) {
        self.pinnedController = pinnedController
        self.preferences      = preferences

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "TopPin")
            button.image?.isTemplate = true
        }

        buildMenu()
        updateMenu()

        pinnedController.addStateObserver { [weak self] _ in self?.updateMenu() }
    }

    // MARK: - Menu construction

    private func buildMenu() {
        let menu = NSMenu()

        windowNameMenuItem = NSMenuItem(title: "No window selected", action: nil, keyEquivalent: "")
        windowNameMenuItem.isEnabled = false
        menu.addItem(windowNameMenuItem)

        menu.addItem(.separator())

        let selectItem = NSMenuItem(title: "Select Window…",
                                    action: #selector(selectWindow),
                                    keyEquivalent: "s")
        selectItem.target = self
        menu.addItem(selectItem)

        pinMenuItem = NSMenuItem(title: "Pin",
                                 action: #selector(togglePin),
                                 keyEquivalent: "p")
        pinMenuItem.keyEquivalentModifierMask = [.option, .command]
        pinMenuItem.target = self
        menu.addItem(pinMenuItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Preferences…",
                                   action: #selector(openPreferences),
                                   keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit TopPin",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateMenu() {
        switch pinnedController.state {
        case .idle:
            statusItem.button?.image = NSImage(systemSymbolName: "pin",
                                               accessibilityDescription: "TopPin – idle")
            statusItem.button?.image?.isTemplate = true
            pinMenuItem.title    = "Pin  ⌥⌘P"
            pinMenuItem.isEnabled = pinnedController.pinnedWindow != nil ||
                                    preferences.lastWindowIdentity != nil
            windowNameMenuItem.title = "No window selected"

        case .pinning(let ref):
            statusItem.button?.image = NSImage(systemSymbolName: "pin.fill",
                                               accessibilityDescription: "TopPin – active")
            statusItem.button?.image?.isTemplate = true
            pinMenuItem.title   = "Unpin  ⌥⌘P"
            pinMenuItem.isEnabled = true
            windowNameMenuItem.title = "📌 \(ref.appName): \(ref.displayTitle)"

        case .error(let msg):
            statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle",
                                               accessibilityDescription: "TopPin – error")
            statusItem.button?.image?.isTemplate = true
            pinMenuItem.title   = "Retry Pin"
            pinMenuItem.isEnabled = true
            windowNameMenuItem.title = "⚠ \(msg)"
        }
    }

    // MARK: - Actions

    @objc private func selectWindow() {
        onSelectWindow?()
    }

    @objc private func togglePin() {
        pinnedController.togglePin()
    }

    @objc private func openPreferences() {
        onPreferences?()
    }
}
