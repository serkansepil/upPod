import AppKit
import SwiftUI

/// A single window for the active exercise session. Window management in an `.accessory`/LSUIElement app:
/// since the transient popover closes on blur, a separate, persistent window is needed for the session.
final class ExerciseWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let engine: ExerciseEngine
    private let windowSize = NSSize(width: 600, height: 800)

    init(engine: ExerciseEngine) {
        self.engine = engine
        super.init()
    }

    func present() {
        engine.reset()   // fresh start screen
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: windowSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "UpPod — Exercises"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false       // prevents close-then-reopen crash in an accessory app
            w.contentViewController = NSHostingController(rootView: ExerciseSessionView(engine: engine))
            w.contentMinSize = windowSize
            w.setContentSize(windowSize)   // override the hosting controller shrinking it
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)  // accessory app doesn't activate automatically; also closes the popover
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        engine.stop()   // clears onMotion, exerciseActive=false, writes the record
    }
}
