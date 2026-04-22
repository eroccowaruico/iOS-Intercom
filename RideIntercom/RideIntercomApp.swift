import SwiftUI

@main
struct RideIntercomApp: App {
    var body: some Scene {
        WindowGroup {
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
