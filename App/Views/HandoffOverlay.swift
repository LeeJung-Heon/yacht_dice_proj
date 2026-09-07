import SwiftUI

/// 패스앤플레이에서 다음 사람에게 기기를 넘기는 동안 점수판을 가린다.
struct HandoffOverlay: View {
    let playerName: String
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right").font(.largeTitle)
            Text("다음 차례").font(.headline).foregroundStyle(.secondary)
            Text(playerName).font(.system(.title, design: .rounded).weight(.bold))
            Button("시작", action: onStart)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("handoff.start")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityAddTraits(.isModal)
    }
}
