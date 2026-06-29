import Foundation

enum RuntimeFlags {
    #if DEBUG
    private static let internalFlagsEnabled = true
    #else
    private static let internalFlagsEnabled = false
    #endif

    static func enabled(_ name: String) -> Bool {
        internalFlagsEnabled && ProcessInfo.processInfo.environment[name] == "1"
    }

    static func value(_ name: String) -> String? {
        internalFlagsEnabled ? ProcessInfo.processInfo.environment[name] : nil
    }
}
