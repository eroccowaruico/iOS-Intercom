import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Intercom")
                .font(.largeTitle)
                .bold()
            Text("Local (MC) transport ready. Audio session + VAD scaffolded.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("Local", systemImage: "antenna.radiowaves.left.and.right")
                Label("Internet", systemImage: "globe")
            }
            .font(.subheadline)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
