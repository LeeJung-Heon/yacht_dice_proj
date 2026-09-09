import SwiftUI
import YachtCore

/// 좌석별 명패. 현재 차례는 황동 배경. 2인 이상일 때만 보인다.
struct PlayerStrip: View {
    let session: GameSession
    /// 점수판에 보이는 좌석. nil이면 현재 차례.
    var viewedSeat: Int? = nil
    var onSelect: (Int) -> Void = { _ in }

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(session.participants.indices, id: \.self) { index in
                let participant = session.participants[index]
                let total = session.visibleState.scorecards[index].total
                let isCurrent = session.visibleState.currentPlayer == index
                    && session.visibleState.phase != .finished
                let isViewed = (viewedSeat ?? session.visibleState.currentPlayer) == index
                Button {
                    onSelect(index)
                } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        if case .bot = participant { Image(systemName: "cpu").font(.caption2) }
                        if case .remote = participant {
                            // 같은 채널에 있으면 초록, 없으면 회색
                            Circle()
                                .fill(session.opponentPresent ? Color.green : theme.inkSecondary.opacity(0.5))
                                .frame(width: 7, height: 7)
                                .accessibilityIdentifier("players.presence.\(index)")
                                .accessibilityLabel(session.opponentPresent ? "접속 중" : "자리 비움")
                        }
                        Text(participant.displayName).font(.caption).lineLimit(1)
                    }
                    Text("\(total)")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(isCurrent ? theme.brassInk : theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(isCurrent ? theme.brass : theme.paper))
                // 점수판에 펼쳐 놓은 좌석은 테두리를 두껍게
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isViewed ? theme.ink : theme.brass, lineWidth: isViewed ? 2.5 : 1.5))
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("players.seat.\(index)")
                .accessibilityLabel("\(participant.displayName), 총점 \(total)점\(isCurrent ? ", 현재 차례" : "")\(presenceLabel(for: participant))")
                .accessibilityHint("탭하면 이 사람의 점수판을 본다")
            }
        }
        .padding(.horizontal, 16)
    }

    private func presenceLabel(for participant: Participant) -> String {
        guard case .remote = participant else { return "" }
        return session.opponentPresent ? ", 접속 중" : ", 자리 비움"
    }
}
