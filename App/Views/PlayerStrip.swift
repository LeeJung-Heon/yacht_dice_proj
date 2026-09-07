import SwiftUI
import YachtCore

/// 좌석별 이름과 총점. 현재 차례를 강조한다. 2인 이상일 때만 보인다.
struct PlayerStrip: View {
    let session: GameSession

    var body: some View {
        HStack(spacing: 8) {
            ForEach(session.participants.indices, id: \.self) { index in
                let participant = session.participants[index]
                let total = session.visibleState.scorecards[index].total
                let isCurrent = session.visibleState.currentPlayer == index
                    && session.visibleState.phase != .finished
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        if case .bot = participant { Image(systemName: "cpu").font(.caption2) }
                        Text(participant.displayName).font(.caption).lineLimit(1)
                    }
                    Text("\(total)").font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isCurrent ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("players.seat.\(index)")
                .accessibilityLabel("\(participant.displayName), 총점 \(total)점\(isCurrent ? ", 현재 차례" : "")")
            }
        }
        .padding(.horizontal, 16)
    }
}
