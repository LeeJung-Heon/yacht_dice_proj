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
                Group {
                    if session.visibleState.phase == .finished {
                        GameOverBar(session: session)
                    } else {
                        ActionBarView(session: session)
                    }
                }
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
            // combine을 이 Group에만 걸어서 header.turn의 label이 항상 턴
            // 텍스트가 되게 한다. 바깥 HStack 전체에 걸면 "게임 종료"까지
            // 합쳐져서 두 상태를 구분할 라벨도, 별도로 찾을 static text도
            // 없어진다.
            Group {
                Text("Turn \(session.visibleState.turnIndex)/\(YachtCore.turnCount)")
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("header.turn")
            .accessibilityRemoveTraits(.isStaticText)
            Spacer()
            if session.visibleState.phase == .finished {
                Text("게임 종료").font(.headline).foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
