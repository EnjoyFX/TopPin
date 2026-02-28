import AppKit
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "PermissionVC")

/// Onboarding window shown when Accessibility permission is not yet granted.
final class PermissionWindowController: NSWindowController {

    var onPermissionGranted: (() -> Void)?

    private let permissionManager: AccessibilityPermissionManager
    private var statusLabel: NSTextField!
    private var recheckButton: NSButton!
    private var timer: Timer?

    // MARK: - Init

    init(permissionManager: AccessibilityPermissionManager) {
        self.permissionManager = permissionManager
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
            styleMask:   [.titled, .closable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        window.title = "TopPin – Accessibility Permission Required"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    deinit { timer?.invalidate() }

    // MARK: - UI

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Icon
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
        icon.contentTintColor = .systemOrange
        icon.frame = NSRect(x: 210, y: 295, width: 80, height: 80)
        icon.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(icon)

        // Title
        let title = makeLabel("Accessibility Permission Required",
                              size: 18, weight: .bold, y: 255)
        contentView.addSubview(title)

        // Body
        let body = makeLabel(
            """
            TopPin uses macOS Accessibility APIs to keep a chosen \
            window on top of others.

            To enable this permission:
            1. Click "Open System Settings" below.
            2. Go to Privacy & Security → Accessibility.
            3. Toggle on "TopPin".
            4. Click "Re-check Permission" here.
            """,
            size: 13, weight: .regular, y: 120)
        body.maximumNumberOfLines = 10
        body.lineBreakMode = .byWordWrapping
        contentView.addSubview(body)

        // Status label
        statusLabel = makeLabel("Waiting for permission…", size: 12,
                                weight: .regular, y: 85)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        // Buttons
        let openBtn = NSButton(title: "Open System Settings",
                               target: self,
                               action: #selector(openSettings))
        openBtn.bezelStyle   = .rounded
        openBtn.keyEquivalent = "\r"
        openBtn.frame = NSRect(x: 30, y: 30, width: 200, height: 36)
        contentView.addSubview(openBtn)

        recheckButton = NSButton(title: "Re-check Permission",
                                 target: self,
                                 action: #selector(recheck))
        recheckButton.bezelStyle = .rounded
        recheckButton.frame = NSRect(x: 270, y: 30, width: 200, height: 36)
        contentView.addSubview(recheckButton)

        startPolling()
    }

    private func makeLabel(_ text: String, size: CGFloat,
                           weight: NSFont.Weight, y: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font     = NSFont.systemFont(ofSize: size, weight: weight)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.frame = NSRect(x: 30, y: y, width: 440, height: size * 5)
        label.sizeToFit()
        label.frame.origin.x = 30
        label.frame.origin.y = y
        return label
    }

    // MARK: - Actions

    @objc private func openSettings() {
        permissionManager.openSystemSettings()
    }

    @objc private func recheck() {
        recheckButton.isEnabled = false
        statusLabel.stringValue = "Checking…"
        permissionManager.recheckPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.statusLabel.stringValue = "✅ Permission granted!"
                self.stopPolling()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.onPermissionGranted?()
                }
            } else {
                self.statusLabel.stringValue = "⚠ Permission not yet granted."
                self.recheckButton.isEnabled = true
            }
        }
    }

    // MARK: - Auto-poll

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.autoPoll()
        }
    }

    private func stopPolling() { timer?.invalidate(); timer = nil }

    private func autoPoll() {
        if permissionManager.checkPermission() {
            stopPolling()
            statusLabel.stringValue = "✅ Permission granted!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.onPermissionGranted?()
            }
        }
    }
}
