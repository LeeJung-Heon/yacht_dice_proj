import SwiftUI

/// 전적 전체. 게임별 승·패·무·승률과 최근 열 판, 그리고 Game Center 리더보드로 가는 문.
struct RecordsScreen: View {
    let container: AppContainer
    @Environment(\.theme) private var theme

    private var records: [RecordRow] { container.records.records }
    private var recent: [RecentMatch] { container.records.recent }

    var body: some View {
        ZStack {
            WoodBackground()
            ScrollView {
                VStack(spacing: 14) {
                    if records.isEmpty {
                        Text("아직 전적이 없다")
                            .font(.callout).foregroundStyle(theme.inkSecondary)
                            .frame(maxWidth: .infinity).paperCard(padding: 20)
                    } else {
                        ForEach(records, id: \.game) { row in
                            gameCard(row)
                        }
                    }
                    recentCard
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .navigationTitle("전적")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("리더보드") { container.gameCenter.presentLeaderboards() }
                    .foregroundStyle(theme.ivory)
                    .disabled(container.gameCenter.playerID == nil)
                    .accessibilityIdentifier("records.leaderboard")
            }
        }
        .refreshable { await container.records.reload() }
    }

    private func gameCard(_ row: RecordRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GameID(rawValue: row.game)?.title ?? row.game)
                .font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
            HStack(spacing: 0) {
                tally("승", "\(row.wins)")
                tally("패", "\(row.losses)")
                tally("무", "\(row.draws)")
                tally("승률", percent(row))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 14)
    }

    private func tally(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.ink)
            Text(label).font(.caption).foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// 무승부까지 판 수에 넣는다. 한 판도 없으면 "—".
    private func percent(_ row: RecordRow) -> String {
        let played = row.wins + row.losses + row.draws
        guard played > 0 else { return "—" }
        return "\(Int((Double(row.wins) / Double(played) * 100).rounded()))%"
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 매치").font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
            if recent.isEmpty {
                Text("없음").foregroundStyle(theme.inkSecondary)
            }
            ForEach(recent.prefix(10), id: \.id) { match in
                RecentRow(match: match, showsDate: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 14)
    }
}
