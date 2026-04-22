import Foundation

#if canImport(AppKit)
import AppKit

@MainActor
enum SingleWindowPolicy {
    static func enforce() {
        NSWindow.allowsAutomaticWindowTabbing = false
        DispatchQueue.main.async {
            closeDuplicateApplicationWindows()
        }
    }

    private static func closeDuplicateApplicationWindows() {
        let applicationWindows = NSApplication.shared.windows.filter { window in
            window.isVisible && window.styleMask.contains(.titled)
        }
        guard applicationWindows.count > 1 else { return }

        let keeper = NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? applicationWindows.first

        for window in applicationWindows where window !== keeper {
            window.close()
        }
    }
}
#else
@MainActor
enum SingleWindowPolicy {
    static func enforce() {}
}
#endif
