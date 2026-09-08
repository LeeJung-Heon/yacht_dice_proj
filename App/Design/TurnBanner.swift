import SwiftUI

/// 턴이 바뀔 때 화면 가운데에 잠깐 뜨는 가죽 띠.
struct TurnBanner: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.title, design: .serif, weight: .bold))
            .foregroundStyle(theme.ivory)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .leatherPanel()
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.brass, lineWidth: 2))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .allowsHitTesting(false)
            .accessibilityIdentifier("turn.banner")
            .accessibilityLabel(text)
    }
}
