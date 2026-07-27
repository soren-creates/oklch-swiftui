import SwiftUI

@main
struct DeviceHarnessApp: App {
    var body: some Scene {
        WindowGroup {
            HarnessView()
        }
    }
}

struct HarnessView: View {
    @State private var status = "starting"

    var body: some View {
        VStack(spacing: 12) {
            Text("OKLCH device harness").font(.headline)
            Text(status).font(.caption).monospaced()
        }
        .task {
            // Marker proving the app installed, signed, launched and executed.
            print("DEVICE-EVIDENCE {\"probe\":\"C2-smoke\",\"ok\":true}")
            status = Measurement.runAll()
        }
    }
}
