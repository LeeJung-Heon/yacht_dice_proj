import SwiftUI

/// 12칸 턴 진행 표시. 지난 턴은 황동, 남은 턴은 흐린 상아색.
struct TurnProgress: View {
    @Environment(\.theme) private var theme
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < current ? theme.brass : theme.ivory.opacity(0.25))
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}
