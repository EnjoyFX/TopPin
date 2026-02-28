import Carbon.HIToolbox
import Foundation
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "HotkeyManager")

/// Registers global hotkeys via the Carbon Event Manager.
/// No Input Monitoring permission required – Carbon hot-key APIs work with Accessibility alone.
final class HotkeyManager {

    private var registeredHotkeys: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?

    init() {
        installCarbonHandler()
    }

    deinit {
        registeredHotkeys.values.forEach { UnregisterEventHotKey($0) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }

    // MARK: - Public

    /// Register a global hotkey.
    /// - Parameters:
    ///   - id: Unique UInt32 identifier (used internally).
    ///   - keyCode: Carbon virtual key code (e.g. kVK_ANSI_P = 35).
    ///   - modifiers: Carbon modifier mask (e.g. optionKey | cmdKey).
    ///   - handler: Closure called on the main thread when the hotkey fires.
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = 0x54504E48 // 'TPNH'
        hotKeyID.id = id

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            registeredHotkeys[id] = ref
            handlers[id] = handler
            logger.info("Registered hotkey id=\(id) keyCode=\(keyCode) mods=\(modifiers)")
        } else {
            logger.error("Failed to register hotkey id=\(id): \(status)")
        }
    }

    // MARK: - Private

    private func installCarbonHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return noErr }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                mgr.handleEvent(event)
                return noErr
            },
            1, &eventSpec,
            selfPtr,
            &eventHandlerRef
        )

        if status != noErr {
            logger.error("InstallEventHandler failed: \(status)")
        }
    }

    private func handleEvent(_ event: EventRef) {
        var hkID = EventHotKeyID()
        GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hkID
        )

        if let handler = handlers[hkID.id] {
            DispatchQueue.main.async { handler() }
        }
    }
}
