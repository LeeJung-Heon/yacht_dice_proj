import SwiftUI
import YachtCore

/// 12턴이 끝난 뒤의 액션 바. 최종 점수를 보여주고 새 판을 시작한다.
/// 이게 없으면 끝난 화면에서는 모든 버튼이 비활성이라 앱을 강제 종료하는 것 말고는
/// 새 게임을 시작할 방법이 없었다.
struct GameOverBar: View {
    let session: GameSession

    private var finalScore: Int {
        session.visibleState.scorecards.map(\.total).max() ?? 0
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("최종 점수 \(finalScore)점")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .accessibilityIdentifier("result.total")
                .accessibilityLabel("최종 점수 \(finalScore)점")

            Button {
                session.startNewGame()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("새 게임")
                }
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isBusy)
            .accessibilityIdentifier("action.newGame")
            .accessibilityLabel("새 게임 시작")
        }
        .padding(.horizontal, 16)
    }
}
