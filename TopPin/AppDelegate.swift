import AppKit
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Services
    private var preferencesStore: PreferencesStore!
    private var pinnedWindowController: PinnedWindowController!
    private var permissionManager: AccessibilityPermissionManager!
    private var hotkeyManager: HotkeyManager!
    private var statusBarController: StatusBarController!

    // MARK: - Windows
    private var windowListWindowController: WindowListWindowController?
    private var permissionWindowController: PermissionWindowController?
    private var preferencesWindowController: PreferencesWindowController?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // No Dock icon

        // Core services
        preferencesStore = PreferencesStore()
        pinnedWindowController = PinnedWindowController(preferences: preferencesStore)
        permissionManager = AccessibilityPermissionManager()

        // Status bar
        statusBarController = StatusBarController(
            pinnedController: pinnedWindowController,
            preferences: preferencesStore
        )
        statusBarController.onSelectWindow = { [weak self] in self?.showWindowList() }
        statusBarController.onPreferences  = { [weak self] in self?.showPreferences() }

        // Permission check
        if permissionManager.checkPermission() {
            logger.info("Accessibility permission granted")
        } else {
            logger.warning("Accessibility permission not granted – showing onboarding")
            showPermissionWindow()
        }

        // Global hotkeys (Carbon – no extra permission needed)
        setupHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pinnedWindowController.unpin()
    }

    // MARK: - Window helpers

    func showWindowList() {
        if windowListWindowController == nil {
            windowListWindowController = WindowListWindowController(
                pinnedController: pinnedWindowController,
                preferences: preferencesStore
            )
        }
        windowListWindowController!.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showPermissionWindow() {
        if permissionWindowController == nil {
            permissionWindowController = PermissionWindowController(
                permissionManager: permissionManager
            )
            permissionWindowController!.onPermissionGranted = { [weak self] in
                self?.permissionWindowController?.close()
                self?.permissionWindowController = nil
            }
        }
        permissionWindowController!.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                preferences: preferencesStore
            )
        }
        preferencesWindowController!.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkeyManager = HotkeyManager()

        // ⌥⌘P – toggle pin/unpin
        // HotkeyManager already dispatches back to the main queue;
        // wrapping in Task @MainActor satisfies Swift 6 strict concurrency.
        hotkeyManager.register(id: 1,
                               keyCode: UInt32(kVK_ANSI_P),
                               modifiers: UInt32(optionKey | cmdKey)) { [weak self] in
            Task { @MainActor [weak self] in
                self?.pinnedWindowController.togglePin()
            }
        }

        // ⌥⌘F – pin frontmost window
        hotkeyManager.register(id: 2,
                               keyCode: UInt32(kVK_ANSI_F),
                               modifiers: UInt32(optionKey | cmdKey)) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let picker = WindowPicker()
                if let ref = picker.pickFrontmostWindow() {
                    self.pinnedWindowController.pin(ref)
                    self.showWindowList()
                }
            }
        }
    }
}
