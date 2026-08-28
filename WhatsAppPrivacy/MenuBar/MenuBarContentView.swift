import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Text("Waiting for WhatsApp…")
        Divider()
        Button("Quit WhatsApp Privacy") {
            NSApplication.shared.terminate(nil)
        }
    }
}
