import AppKit
import SwiftUI

/// Single source of truth for posture-state colors. The in-app (SwiftUI) palette and the menu-bar
/// (AppKit) variant are intentionally different — the glyph is brighter/more saturated so it stays
/// legible at ~18pt against the menu bar.
enum Theme {
    static let good     = Color(red: 0.18, green: 0.69, blue: 0.31)
    static let slight   = Color(red: 0.96, green: 0.63, blue: 0.20)
    static let poor     = Color(red: 0.94, green: 0.30, blue: 0.28)
    static let goodSoft = Color(red: 0.42, green: 0.74, blue: 0.35)

    /// In-app state color (popover, exercise UI).
    static func color(_ state: PostureState) -> Color {
        switch state {
        case .good:   return good
        case .slight: return slight
        case .poor:   return poor
        case .paused: return .secondary
        }
    }

    /// Menu-bar glyph variant (brighter for small-size legibility).
    static func menuBar(_ state: PostureState) -> NSColor {
        switch state {
        case .good:   return NSColor(srgbRed: 0.20, green: 0.82, blue: 0.36, alpha: 1)
        case .slight: return NSColor(srgbRed: 1.00, green: 0.62, blue: 0.16, alpha: 1)
        case .poor:   return NSColor(srgbRed: 1.00, green: 0.28, blue: 0.25, alpha: 1)
        case .paused: return .secondaryLabelColor
        }
    }
}

/// Loads a bundled PNG by name. Release `.app` builds use `Bundle.main`; debug SwiftPM runs can
/// fall back to `Bundle.module`.
enum AppImage {
    static func png(_ name: String) -> NSImage? {
        if let image = png(name, in: Bundle.main) {
            return image
        }
        #if DEBUG
        if let image = png(name, in: Bundle.module) {
            return image
        }
        #endif
        return nil
    }

    private static func png(_ name: String, in bundle: Bundle) -> NSImage? {
        guard let url = bundle.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
