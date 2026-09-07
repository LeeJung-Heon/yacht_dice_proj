import SwiftUI
import YachtCore

/// 12턴이 끝난 뒤의 액션 바. 순위를 보여주고 새 판 또는 메뉴로 간다.
/// 이게 없으면 끝난 화면에서는 모든 버튼이 비활성이라 앱을 강제 종료하는 것 말고는
/// 새 게임을 시작할 방법이 없었다.
struct GameOverBar: View {
    let session: GameSession
    var onReturnToMenu: () -> Void = {}

    private var ranking: [(index: Int, total: Int)] {
        session.visibleState.scorecards.enumerated()
            .map { (index: $0.offset, total: $0.element.total) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(spacing: 10) {
            if session.participants.count == 1 {
                Text("최종 점수 \(ranking[0].total)점")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .accessibilityIdentifier("result.total")
                    .accessibilityLabel("최종 점수 \(ranking[0].total)점")
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(ranking.enumerated()), id: \.offset) { place, entry in
                        HStack {
                            Text("\(place + 1)위").foregroundStyle(place == 0 ? .orange : .secondary)
                            Text(session.participants[entry.index].displayName)
                            Spacer()
                            Text("\(entry.total)점").monospacedDigit().fontWeight(place == 0 ? .bold : .regular)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("result.rank.\(place)")
                        .accessibilityLabel("\(place + 1)위 \(session.participants[entry.index].displayName) \(entry.total)점")
                    }
                }
                .font(.system(.subheadline, design: .rounded))
                .padding(.horizontal, 8)
            }

            HStack(spacing: 12) {
                Button {
                    onReturnToMenu()
                } label: {
                    Label("메뉴로", systemImage: "list.bullet")
                        .font(.headline).padding(.horizontal, 12).padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("result.menu")

                Button {
                    session.startNewGame()
                } label: {
                    Label("새 게임", systemImage: "arrow.clockwise")
                        .font(.headline).padding(.horizontal, 12).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isBusy)
                .accessibilityIdentifier("action.newGame")
                .accessibilityLabel("새 게임 시작")
            }
        }
        .padding(.horizontal, 16)
    }
}
