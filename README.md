# TopPin

A macOS menu-bar utility that keeps any chosen window always on top of other windows — no focus stealing, no flashing.

---

## How it works

macOS provides no public API to force a third-party window into a permanent always-on-top layer. TopPin works around this with two modes, chosen automatically:

### Overlay mode (preferred)
Requires **Screen Recording** permission.

TopPin captures a live video stream of the target window via ScreenCaptureKit and renders it inside its own borderless `NSWindow` set to the `.floating` window level. Because TopPin owns this overlay window, it can freely place it above all normal app windows — permanently, without timers, without flashing.

- Hovering over the overlay activates the original app so you can interact with it normally (play/pause, click buttons, scroll, etc.). Moving the mouse away restores the previously active app.
- The overlay follows the original window when it is moved or resized.
- If the original window closes, the overlay closes and TopPin returns to idle.

### AX fallback mode
Used when Screen Recording is not granted.

TopPin calls `kAXRaiseAction` on the target window on a configurable timer (default: 400 ms), repeatedly raising it above whatever came forward. This is a best-effort approach — there is a brief window (one timer interval) where another window may cover the target.

---

## Permissions

### Accessibility (required)
Needed to enumerate windows, read window titles/bounds, and perform raise actions.

1. Launch TopPin — the onboarding window appears automatically.
2. Click **Open System Settings** (this also registers TopPin in the Accessibility list).
3. In **System Settings → Privacy & Security → Accessibility**, toggle **TopPin** on.
4. Click **Re-check Permission**.

> **macOS 15 note:** After a fresh build the TCC database can take 1–2 seconds to update. Use the **Re-check Permission** button — it polls several times automatically.

### Screen Recording (optional, enables overlay mode)
Needed for the ScreenCaptureKit overlay (the preferred always-on-top method).

TopPin requests this permission the first time you pin a window. If you decline, the app falls back to AX mode automatically. You can grant it later in **System Settings → Privacy & Security → Screen Recording**.

---

## Building

**Requirements:** macOS 13 Ventura or later · Xcode 15 or later

```bash
# Open in Xcode
open TopPin.xcodeproj

# Or build from the command line (ad-hoc signing for local use)
xcodebuild -project TopPin.xcodeproj \
           -scheme TopPin \
           -configuration Release \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_ALLOWED=NO
```

The built app is at `~/Library/Developer/Xcode/DerivedData/TopPin-.../Build/Products/Release/TopPin.app`.

> For distribution, sign with a Developer ID certificate and notarize via `xcrun notarytool`.

---

## Usage

| Action | How |
|---|---|
| Select a window | Menu bar → **Select Window…** |
| Pin selected window | Window list → **Pin Selected** or double-click a row |
| Pin frontmost window | **⌥⌘F** from any app |
| Click-to-pick | Window list → **⊕ Click to Pick**, then click any window |
| Toggle pin / unpin | **⌥⌘P** or menu bar → **Pin / Unpin** |
| Preferences | Menu bar → **Preferences…** |

---

## Preferences

| Setting | Default | Description |
|---|---|---|
| Raise interval | 400 ms | How often the window is raised in AX fallback mode |
| Allow focus steal | Off | In AX mode: also activates the owning app, not just raises the window. More reliable for stubborn apps, but briefly steals keyboard focus. |

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| Only TopPin appears in the window list | Accessibility permission is not granted. Complete the onboarding flow and use **Open System Settings** button (not manual navigation). |
| Overlay appears black | Screen Recording was just granted — quit and relaunch TopPin. |
| "Target window no longer exists" | The target app was closed. Select a new window. |
| Warning triangle in menu bar | AX raise action is failing. Enable **Allow focus steal** in Preferences, or switch to a different window. |
| Window not listed | Some apps do not expose windows via Accessibility. Use **⊕ Click to Pick** or **⌥⌘F**. |
| Hotkeys don't fire | Verify Accessibility permission is granted. Carbon hotkeys rely on Accessibility. |
| Overlay shifts after moving the original window | AX position notifications can lag ~100 ms. The overlay corrects itself on the next notification. |

---

## Limitations

- Full-screen spaces, Mission Control, and system overlays (e.g., Notification Center) can cover the overlay.
- In AX fallback mode there is a brief flash (one timer interval) where another window may appear on top.
- TopPin must remain running for the pin to stay active.
- Some apps block Accessibility actions entirely (`AXError`). TopPin detects this and shows a warning.

---

## Architecture

```
AppDelegate
├── AccessibilityPermissionManager   – AXIsProcessTrusted(), opens Settings deep-link
├── ScreenCapturePermissionManager   – CGPreflightScreenCaptureAccess(), CGRequestScreenCaptureAccess()
├── WindowEnumerator                 – AXUIElement window discovery
├── WindowPicker                     – frontmost pick + click-to-pick overlay
├── WindowCaptureSession             – SCStream wrapper, one window, 30 fps
├── PinnedWindowController           – @MainActor state machine, chooses overlay vs AX mode
├── PreferencesStore                 – UserDefaults thin wrapper
├── HotkeyManager                    – Carbon RegisterEventHotKey (no Input Monitoring entitlement)
└── UI
    ├── FloatingOverlayWindowController – .floating NSWindow + SCStream rendering + hover-to-focus
    ├── StatusBarController             – NSStatusItem + menu
    ├── WindowListWindowController      – main window, NSTableView
    ├── PermissionWindowController      – Accessibility onboarding
    └── PreferencesWindowController     – interval slider, toggles
```

---

## License

MIT — see LICENSE file.
