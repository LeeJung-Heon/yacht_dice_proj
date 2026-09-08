import SwiftUI

/// 상대가 기록한 칸과 점수를 알리는 작은 종이 쪽지.
struct ScoreToast: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.and.list.clipboard").foregroundStyle(theme.brass)
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(theme.ink).monospacedDigit()
        }
        .paperCard(padding: 12)
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
        .accessibilityIdentifier("score.toast")
        .accessibilityLabel(text)
    }
}
