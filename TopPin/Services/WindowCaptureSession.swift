import AppKit
import ScreenCaptureKit
import CoreMedia
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "WindowCaptureSession")

enum CaptureError: LocalizedError {
    case windowNotFound
    var errorDescription: String? { "Could not find the target window in screen content" }
}

/// Wraps a single `SCStream` that captures one window's content.
/// All callbacks are delivered on the main actor.
@MainActor
final class WindowCaptureSession: NSObject {

    /// Called with each new video frame.
    var onFrame: ((CMSampleBuffer) -> Void)?
    /// Called when the stream stops (window closed / app quit).
    var onWindowGone: (() -> Void)?

    private var stream: SCStream?

    // MARK: - Start

    /// Finds the target window in `SCShareableContent` by PID + title and starts streaming.
    func start(matching windowRef: WindowRef) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )

        // Match by PID; prefer exact title match, fall back to any window of that process
        let scWindow: SCWindow? = {
            let byPID = content.windows.filter {
                $0.owningApplication?.processID == Int32(windowRef.pid)
            }
            return byPID.first(where: { $0.title == windowRef.title }) ?? byPID.first
        }()

        guard let scWindow else { throw CaptureError.windowNotFound }
        logger.info("Starting SCStream for '\(scWindow.title ?? "?")'")
        try await startStream(scWindow: scWindow)
    }

    private func startStream(scWindow: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)

        let scale  = NSScreen.main?.backingScaleFactor ?? 2.0
        let config = SCStreamConfiguration()
        config.width         = max(1, Int(scWindow.frame.width  * scale))
        config.height        = max(1, Int(scWindow.frame.height * scale))
        // 30 fps is plenty for a music mini-player
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth    = 3
        config.showsCursor   = false

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await s.startCapture()
        stream = s
    }

    // MARK: - Stop

    func stop() async {
        guard let s = stream else { return }
        try? await s.stopCapture()
        stream = nil
    }
}

// MARK: - SCStreamOutput

extension WindowCaptureSession: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        Task { @MainActor in self.onFrame?(sampleBuffer) }
    }
}

// MARK: - SCStreamDelegate

extension WindowCaptureSession: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.warning("SCStream stopped: \(error.localizedDescription)")
        Task { @MainActor in self.onWindowGone?() }
    }
}
