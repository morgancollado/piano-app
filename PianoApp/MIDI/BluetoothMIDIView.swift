import CoreAudioKit
import SwiftUI

/// Apple's screen for advertising this iPhone as a Bluetooth MIDI device. While it's open,
/// a Mac can connect in Audio MIDI Setup → MIDI Studio → Bluetooth. After that, the notes
/// you play go to the Mac like any other MIDI connection.
struct BluetoothMIDISheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BluetoothMIDIAdvertiser()
                .navigationTitle("Bluetooth MIDI")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    Text("Keep this screen open until your Mac shows this iPhone as connected: Audio MIDI Setup → Window → Show MIDI Studio → Bluetooth button → Connect.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { dismiss() }
                    }
                }
        }
    }
}

private struct BluetoothMIDIAdvertiser: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDILocalPeripheralViewController {
        CABTMIDILocalPeripheralViewController()
    }

    func updateUIViewController(_ controller: CABTMIDILocalPeripheralViewController, context: Context) {}
}
