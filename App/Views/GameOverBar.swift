import SwiftUI
import YachtCore

/// 12턴이 끝난 뒤의 결과 카드. 순위를 보여주고 새 판 또는 메뉴로 간다.
struct GameOverBar: View {
    let session: GameSession
    var onReturnToMenu: () -> Void = {}

    @Environment(\.theme) private var theme

    private var ranking: [(index: Int, total: Int)] {
        session.visibleState.scorecards.enumerated()
            .map { (index: $0.offset, total: $0.element.total) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(spacing: 12) {
            if session.participants.count == 1 {
                VStack(spacing: 2) {
                    Text("최종 점수").font(.caption).foregroundStyle(theme.inkSecondary)
                    Text("\(ranking[0].total)점")
                        .font(.system(.title, design: .serif).weight(.semibold))
                        .foregroundStyle(theme.ink)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("result.total")
                .accessibilityLabel("최종 점수 \(ranking[0].total)점")
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(ranking.enumerated()), id: \.offset) { place, entry in
                        HStack(spacing: 8) {
                            if place == 0 {
                                Image(systemName: "trophy.fill").foregroundStyle(theme.brass)
                            } else {
                                Text("\(place + 1)위").foregroundStyle(theme.inkSecondary)
                            }
                            Text(session.participants[entry.index].displayName).foregroundStyle(theme.ink)
                            Spacer()
                            Text("\(entry.total)점").monospacedDigit().foregroundStyle(theme.ink)
                                .fontWeight(place == 0 ? .bold : .regular)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("result.rank.\(place)")
                        .accessibilityLabel("\(place + 1)위 \(session.participants[entry.index].displayName) \(entry.total)점")
                    }
                }
                .font(.system(.subheadline, design: .rounded))
            }

            HStack(spacing: 12) {
                Button(action: onReturnToMenu) {
                    Label("메뉴로", systemImage: "list.bullet").brassButton(prominent: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("result.menu")

                Button {
                    session.startNewGame()
                } label: {
                    Label("새 게임", systemImage: "arrow.clockwise").brassButton(prominent: true)
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
                .accessibilityIdentifier("action.newGame")
                .accessibilityLabel("새 게임 시작")
            }
        }
        .paperCard(padding: 14)
        .padding(.horizontal, 16)
    }
}
