import SwiftUI

struct SettingsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FeedbackSettings.soundKey) private var soundEnabled = true
    @AppStorage(FeedbackSettings.hapticsKey) private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            ZStack {
                WoodBackground()
                VStack(spacing: 12) {
                    Toggle(isOn: $soundEnabled) {
                        Label("사운드", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("settings.sound")
                    Toggle(isOn: $hapticsEnabled) {
                        Label("햅틱", systemImage: "hand.tap")
                    }
                    .accessibilityIdentifier("settings.haptics")
                }
                .tint(theme.brass)
                .foregroundStyle(theme.ink)
                .paperCard()
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
