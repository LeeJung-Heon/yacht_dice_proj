import SwiftUI

/// 패스앤플레이에서 다음 사람에게 기기를 넘기는 동안 점수판을 가린다.
struct HandoffOverlay: View {
    @Environment(\.theme) private var theme
    let playerName: String
    let onStart: () -> Void

    var body: some View {
        ZStack {
            WoodBackground().opacity(0.96)
            VStack(spacing: 16) {
                Image(systemName: "arrow.left.arrow.right").font(.largeTitle).foregroundStyle(theme.brass)
                Text("다음 차례").font(.headline).foregroundStyle(theme.ivory.opacity(0.7))
                Text(playerName)
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(theme.ivory)
                Button(action: onStart) {
                    Text("시작").brassButton(prominent: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("handoff.start")
            }
            .padding(32)
        }
        .accessibilityAddTraits(.isModal)
    }
}
