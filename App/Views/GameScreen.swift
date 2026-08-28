import SwiftUI
import YachtCore
import DiceTrajectory

struct GameScreen: View {
    let session: GameSession
    let stage: DiceStage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                DiceStageView(stage: stage)
                    .frame(height: geometry.size.height * 0.42)
                    .contentShape(Rectangle())
                    .gesture(throwGesture)
                ActionBarView(session: session)
                    .padding(.vertical, 10)
                Divider()
                ScrollView {
                    ScoreboardView(session: session)
                }
            }
        }
        .onChange(of: reduceMotion, initial: true) { _, newValue in
            session.reduceMotion = newValue
        }
    }

    private var header: some View {
        HStack {
            Text("Turn \(session.visibleState.turnIndex)/\(YachtCore.turnCount)")
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
            Spacer()
            if session.visibleState.phase == .finished {
                Text("게임 종료").font(.headline).foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityIdentifier("header.turn")
        .accessibilityElement(children: .combine)
    }

    /// 위로 쓸어올리면 던진다. 좌우 성분으로 궤적 그룹을 고른다.
    private var throwGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                // 아래로 쓸어내린 것은 던지기가 아니다
                guard value.translation.height < -20 else { return }
                let horizontal = value.translation.width
                session.nextThrowDirection = if horizontal < -40 {
                    .left
                } else if horizontal > 40 {
                    .right
                } else {
                    .center
                }
                Task { await session.send(.roll) }
            }
    }
}
