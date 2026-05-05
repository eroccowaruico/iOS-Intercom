#if os(macOS)
import AppKit
#endif
import SwiftUI

@main
struct RideIntercomApp: App {
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(RideIntercomApplicationDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        let _ = configureOpenWindowBridge()

        return WindowGroup(id: SingleWindowPolicy.mainWindowID) {
            ContentView()
                .onAppear {
                    SingleWindowPolicy.enforce()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                EmptyView()
            }
        }
        #else
        return WindowGroup {
            ContentView()
        }
        #endif
    }

    #if os(macOS)
    private func configureOpenWindowBridge() {
        appDelegate.openMainWindow = {
            openWindow(id: SingleWindowPolicy.mainWindowID)
        }
    }
    #endif
}
