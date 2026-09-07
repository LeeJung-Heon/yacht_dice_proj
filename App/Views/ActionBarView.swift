import SwiftUI
import YachtCore

struct ActionBarView: View {
    let session: GameSession

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: GameState { session.visibleState }

    var body: some View {
        VStack(spacing: 12) {
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

    /// 각 주사위의 keep 상태를 누를 수 있는 주사위 면. 3D 주사위를 직접 만지는 것보다
    /// 정확하고, VoiceOver로도 조작할 수 있다.
    private var diceRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(0..<YachtCore.diceCount, id: \.self) { index in
                let value = state.dice[index]
                let isHeld = state.held.contains(index)
                Button {
                    Task { await session.send(.toggleHold(index)) }
                } label: {
                    VStack(spacing: 6) {
                        DieFaceView(value: value, isHeld: isHeld, size: 48)
                            .animation(reduceMotion ? nil : .spring(duration: 0.25), value: isHeld)
                        holdCaption(isHeld: isHeld, rolled: value != 0)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!state.allows(.toggleHold(index)) || session.isBusy || !session.isLocalTurn)
                .accessibilityIdentifier("action.die.\(index)")
                .accessibilityLabel(value == 0 ? "주사위 \(index + 1), 아직 안 굴림"
                                               : "주사위 \(index + 1), \(value)")
                .accessibilityValue(isHeld ? "고정됨" : "고정 안 됨")
                .accessibilityHint("두 번 탭하면 고정을 바꿉니다")
            }
        }
    }

    /// 칩 아래 "고정" 표시. 고정 안 된 칩도 같은 높이의 자리를 차지해 레이아웃이 튀지 않는다.
    @ViewBuilder
    private func holdCaption(isHeld: Bool, rolled: Bool) -> some View {
        Group {
            if isHeld {
                Label("고정", systemImage: "lock.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.brassInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.brass))
            } else {
                Text(rolled ? "탭하여 고정" : " ")
                    .font(.caption2)
                    .foregroundStyle(theme.ivory.opacity(rolled ? 0.45 : 0))
                    .padding(.vertical, 2)
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    private var assistToggle: some View {
        Button {
            session.assistEnabled.toggle()
        } label: {
            Text("Assist")
                .font(.footnote.weight(.semibold))
                .brassButton(prominent: session.assistEnabled)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("action.assist")
        .accessibilityLabel("예상 점수 표시")
        .accessibilityValue(session.assistEnabled ? "켜짐" : "꺼짐")
        .accessibilityAddTraits(session.assistEnabled ? [.isSelected] : [])
    }

    private var rollButton: some View {
        Button {
            Task { await session.send(.roll) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "dice.fill")
                Text("Roll")
                HStack(spacing: 3) {
                    ForEach(0..<YachtCore.maxRollsPerTurn, id: \.self) { index in
                        Circle()
                            .fill(index < state.rollsRemaining ? theme.brassInk : theme.brassInk.opacity(0.25))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            .brassButton(prominent: true)
        }
        .buttonStyle(.plain)
        .disabled(!state.allows(.roll) || session.isBusy || !session.isLocalTurn)
        .accessibilityIdentifier("action.roll")
        .accessibilityLabel("주사위 굴리기, \(state.rollsRemaining)회 남음")
    }
}
