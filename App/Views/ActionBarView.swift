import SwiftUI
import YachtCore

struct ActionBarView: View {
    let session: GameSession

    private var state: GameState { session.visibleState }

    var body: some View {
        VStack(spacing: 10) {
            diceRow
            // 큰 글씨(AX5)에서는 Assist와 Roll이 한 줄에 다 안 들어가고 Roll의
            // 텍스트가 뭉개진다. 안 들어가면 세로로 쌓는다.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    assistToggle
                    Spacer()
                    rollButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    assistToggle
                    rollButton
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// 각 주사위의 keep 상태를 누를 수 있는 칩. 3D 주사위를 직접 만지는 것보다
    /// 정확하고, VoiceOver로도 조작할 수 있다.
    private var diceRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<YachtCore.diceCount, id: \.self) { index in
                let value = state.dice[index]
                let isHeld = state.held.contains(index)
                Button {
                    Task { await session.send(.toggleHold(index)) }
                } label: {
                    Text(value == 0 ? "–" : "\(value)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 44, height: 44)
                        .background(isHeld ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(isHeld ? Color.orange : .clear, lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!state.allows(.toggleHold(index)) || session.isBusy)
                .accessibilityIdentifier("action.die.\(index)")
                .accessibilityLabel(value == 0 ? "주사위 \(index + 1), 아직 안 굴림"
                                               : "주사위 \(index + 1), \(value)")
                .accessibilityValue(isHeld ? "고정됨" : "고정 안 됨")
                .accessibilityHint("두 번 탭하면 고정을 바꿉니다")
            }
        }
    }

    private var assistToggle: some View {
        Toggle(isOn: Binding(get: { session.assistEnabled },
                             set: { session.assistEnabled = $0 })) {
            Text("Assist").font(.footnote)
        }
        .toggleStyle(.button)
        .accessibilityIdentifier("action.assist")
        .accessibilityLabel("예상 점수 표시")
    }

    private var rollButton: some View {
        Button {
            Task { await session.send(.roll) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dice.fill")
                Text(state.rollsRemaining > 0 ? "Roll (\(state.rollsRemaining))" : "Roll")
            }
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!state.allows(.roll) || session.isBusy)
        .accessibilityIdentifier("action.roll")
        .accessibilityLabel("주사위 굴리기, \(state.rollsRemaining)회 남음")
    }
}
