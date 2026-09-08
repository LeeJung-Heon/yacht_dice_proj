import SwiftUI
import YachtCore

/// 종이 점수표. 이름 … 점선 리더 … 점수.
struct ScoreboardView: View {
    let session: GameSession
    /// 보여줄 좌석. nil이면 현재 차례의 좌석이다. 상대 차례에 내 점수판을 보는 데 쓴다.
    var seat: Int? = nil

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bonusFlash = 0.0

    private var state: GameState { session.visibleState }
    private var shownSeat: Int { seat ?? state.currentPlayer }
    /// 현재 차례의 점수판을 보고 있을 때만 기록할 수 있고 미리보기가 뜬다.
    private var isCurrentSeat: Bool { shownSeat == state.currentPlayer }
    private var card: ScoreCard { state.scorecards[shownSeat] }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ScoreCategory.upperCases, id: \.self) { row($0) }
            subtotalRow
            rule(weight: 1)
            ForEach(lowerCategories, id: \.self) { row($0) }
            rule(weight: 2)
            totalRow
        }
        .font(.system(.subheadline, design: .rounded))
        .paperCard(padding: 12)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: card.upperBonus) { before, after in
            guard before == 0, after > 0, !reduceMotion else { return }
            bonusFlash = 1
            withAnimation(.easeOut(duration: 0.6)) { bonusFlash = 0 }
        }
    }

    private var lowerCategories: [ScoreCategory] {
        ScoreCategory.allCases.filter { !$0.isUpper }
    }

    private func rule(weight: CGFloat) -> some View {
        Rectangle().fill(theme.ink.opacity(weight > 1 ? 0.7 : 0.25)).frame(height: weight)
            .padding(.vertical, 4)
    }

    private func row(_ category: ScoreCategory) -> some View {
        let recorded = card.entry(category)
        let preview = isCurrentSeat ? session.previewScore(category) : nil

        return Button {
            Task { await session.send(.commit(category)) }
        } label: {
            HStack(spacing: 8) {
                Text(category.displayName)
                    .foregroundStyle(theme.ink)
                DottedLeader().stroke(theme.paperLine, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .offset(y: 4)
                Group {
                    if let recorded {
                        Text("\(recorded)")
                            .fontWeight(.bold)
                            .foregroundStyle(theme.ink)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: recorded)
                    } else if let preview {
                        Text("\(preview)")
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.brassInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(theme.brass))
                    } else {
                        Text("–").foregroundStyle(theme.inkSecondary)
                    }
                }
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .disabled(!isCurrentSeat || recorded != nil || !state.allows(.commit(category)) || session.isBusy || !session.isLocalTurn)
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
        let reached = card.upperBonus > 0
        let progress = min(1, Double(card.upperSubtotal) / Double(ScoreCard.upperBonusThreshold))
        return HStack(spacing: 10) {
            Text("보너스까지").foregroundStyle(theme.inkSecondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.paperLine)
                    Capsule().fill(reached ? theme.success : theme.brass)
                        .frame(width: geo.size.width * progress)
                    Capsule().fill(theme.brass).opacity(bonusFlash)
                }
            }
            .frame(height: 6)
            if reached {
                Text("+\(card.upperBonus)").foregroundStyle(theme.success).fontWeight(.bold).monospacedDigit()
            } else {
                Text("\(card.upperSubtotal)/\(ScoreCard.upperBonusThreshold)")
                    .foregroundStyle(theme.inkSecondary).monospacedDigit()
            }
        }
        .font(.caption)
        .padding(.vertical, 6)
        // .accessibilityElement(children: .combine)이 먼저 와야 한다. 뒤에 두면 식별자가
        // 자식들에게 먼저 붙고, 합쳐진 요소의 식별자는 "scoreboard.subtotal-scoreboard.subtotal"이
        // 된다 — VoiceOver로 이 행을 지목할 수 없다.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scoreboard.subtotal")
        .accessibilityLabel(reached
            ? "상단 소계 \(card.upperSubtotal)점, 보너스 35점 획득"
            : "상단 소계 \(card.upperSubtotal)점, 보너스까지 \(ScoreCard.upperBonusThreshold - card.upperSubtotal)점 남음")
    }

    private var totalRow: some View {
        HStack {
            Text("Total").font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
            Spacer()
            Text("\(card.total)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(theme.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: card.total)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scoreboard.total")
        .accessibilityLabel("총점 \(card.total)점")
    }
}

/// 이름과 점수 사이의 점선.
private struct DottedLeader: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
