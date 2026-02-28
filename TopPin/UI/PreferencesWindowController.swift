import AppKit

/// Preferences panel. Settings here apply only when Screen Recording is not granted
/// and TopPin falls back to AX raise mode.
final class PreferencesWindowController: NSWindowController {

    private let preferences: PreferencesStore

    private var intervalSlider: NSSlider!
    private var intervalLabel:  NSTextField!
    private var focusStealCheckbox: NSButton!

    // MARK: - Init

    init(preferences: PreferencesStore) {
        self.preferences = preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
            styleMask:   [.titled, .closable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        window.title = "TopPin – Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        let pad: CGFloat = 24
        var y: CGFloat = 155

        cv.addSubview(sectionLabel("AX Fallback Mode", y: y))
        y -= 18

        let note = NSTextField(wrappingLabelWithString:
            "These settings apply only when Screen Recording is not granted and TopPin uses the Accessibility raise loop instead of the overlay.")
        note.font      = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.frame     = NSRect(x: pad, y: y - 22, width: 370, height: 36)
        cv.addSubview(note)
        y -= 52

        // Interval slider
        cv.addSubview(rowLabel("Raise interval:", y: y))

        intervalSlider = NSSlider(value: preferences.interval,
                                  minValue: 0.2, maxValue: 1.5,
                                  target: self,
                                  action: #selector(intervalChanged(_:)))
        intervalSlider.frame = NSRect(x: 160, y: y - 2, width: 180, height: 20)
        intervalSlider.isContinuous = true
        cv.addSubview(intervalSlider)

        intervalLabel = NSTextField(labelWithString: intervalString(preferences.interval))
        intervalLabel.frame = NSRect(x: 348, y: y, width: 56, height: 18)
        intervalLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        cv.addSubview(intervalLabel)
        y -= 36

        // Focus steal
        focusStealCheckbox = NSButton(checkboxWithTitle:
            "Allow focus steal — activates the owning app, not just raises the window",
            target: self, action: #selector(focusStealChanged(_:)))
        focusStealCheckbox.state = preferences.allowFocusSteal ? .on : .off
        focusStealCheckbox.frame = NSRect(x: pad, y: y, width: 370, height: 20)
        cv.addSubview(focusStealCheckbox)

        // Footer
        let footer = NSTextField(labelWithString: "Changes take effect immediately.")
        footer.font      = NSFont.systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.frame     = NSRect(x: pad, y: 16, width: 370, height: 16)
        cv.addSubview(footer)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String, y: CGFloat) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font   = NSFont.systemFont(ofSize: 13, weight: .semibold)
        lbl.frame  = NSRect(x: 24, y: y, width: 370, height: 18)
        return lbl
    }

    private func rowLabel(_ text: String, y: CGFloat) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font      = NSFont.systemFont(ofSize: 13)
        lbl.alignment = .right
        lbl.frame     = NSRect(x: 24, y: y, width: 132, height: 18)
        return lbl
    }

    private func intervalString(_ v: Double) -> String { String(format: "%.2f s", v) }

    // MARK: - Actions

    @objc private func intervalChanged(_ sender: NSSlider) {
        preferences.interval = sender.doubleValue
        intervalLabel.stringValue = intervalString(sender.doubleValue)
    }

    @objc private func focusStealChanged(_ sender: NSButton) {
        preferences.allowFocusSteal = sender.state == .on
    }
}
