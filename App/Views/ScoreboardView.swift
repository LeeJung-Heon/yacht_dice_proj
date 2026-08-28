import SwiftUI
import YachtCore

struct ScoreboardView: View {
    let session: GameSession

    private var state: GameState { session.visibleState }
    private var card: ScoreCard { state.scorecards[state.currentPlayer] }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ScoreCategory.upperCases, id: \.self) { row($0) }
            subtotalRow
            Divider()
            ForEach(lowerCategories, id: \.self) { row($0) }
            Divider()
            totalRow
        }
        .font(.system(.subheadline, design: .rounded))
        .padding(.horizontal, 12)
    }

    private var lowerCategories: [ScoreCategory] {
        ScoreCategory.allCases.filter { !$0.isUpper }
    }

    private func row(_ category: ScoreCategory) -> some View {
        let recorded = card.entry(category)
        let preview = session.previewScore(category)

        return Button {
            Task { await session.send(.commit(category)) }
        } label: {
            HStack {
                Text(category.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Group {
                    if let recorded {
                        Text("\(recorded)").fontWeight(.bold).foregroundStyle(.primary)
                    } else if let preview {
                        Text("\(preview)").foregroundStyle(.orange)
                    } else {
                        Text("").frame(width: 1)
                    }
                }
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .disabled(recorded != nil || !state.allows(.commit(category)) || session.isBusy)
        .accessibilityIdentifier("scoreboard.row.\(category.rawValue)")
        .accessibilityLabel(accessibilityLabel(for: category, recorded: recorded, preview: preview))
        .accessibilityHint(recorded == nil ? category.accessibilityDescription : "")
    }

    private func accessibilityLabel(for category: ScoreCategory, recorded: Int?, preview: Int?) -> String {
        if let recorded { return "\(category.displayName), \(recorded)점 기록됨" }
        if let preview { return "\(category.displayName), 지금 기록하면 \(preview)점" }
        return "\(category.displayName), 비어 있음"
    }

    private var subtotalRow: some View {
        HStack {
            Text("보너스까지")
            Spacer()
            Text("\(card.upperSubtotal)/\(ScoreCard.upperBonusThreshold)")
                .monospacedDigit()
                .foregroundStyle(card.upperBonus > 0 ? .green : .secondary)
            if card.upperBonus > 0 {
                Text("+\(card.upperBonus)").foregroundStyle(.green).monospacedDigit()
            }
        }
        .font(.caption)
        .padding(.vertical, 4)
        // .accessibilityElement(children: .combine)이 먼저 와야 한다. 뒤에 두면 식별자가
        // 자식들에게 먼저 붙고, 합쳐진 요소의 식별자는 "scoreboard.subtotal-scoreboard.subtotal"이
        // 된다 — VoiceOver로 이 행을 지목할 수 없다.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scoreboard.subtotal")
        .accessibilityLabel(card.upperBonus > 0
            ? "상단 소계 \(card.upperSubtotal)점, 보너스 35점 획득"
            : "상단 소계 \(card.upperSubtotal)점, 보너스까지 \(ScoreCard.upperBonusThreshold - card.upperSubtotal)점 남음")
    }

    private var totalRow: some View {
        HStack {
            Text("Total").fontWeight(.semibold)
            Spacer()
            Text("\(card.total)").fontWeight(.bold).monospacedDigit()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scoreboard.total")
        .accessibilityLabel("총점 \(card.total)점")
    }
}
