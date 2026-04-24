import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

@main
struct RideIntercomApp: App {
    #if canImport(AppKit)
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(RideIntercomApplicationDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if canImport(AppKit)
        let _ = {
            appDelegate.openMainWindow = {
                openWindow(id: SingleWindowPolicy.mainWindowID)
            }
        }()
        #endif

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
    }
}
