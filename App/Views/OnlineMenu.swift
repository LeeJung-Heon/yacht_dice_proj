import SwiftUI
import GameKit

/// 온라인 대전 화면. 로그인 상태, 새 매치 찾기, 진행 중인 매치.
struct OnlineMenu: View {
    let container: AppContainer

    @Environment(\.theme) private var theme
    @State private var showingMatchmaker = false

    private var service: GameCenterService { container.gameCenter }

    var body: some View {
        ZStack {
            WoodBackground()
            ScrollView {
                VStack(spacing: 14) {
                    statusRow.paperCard(padding: 14)

                    if case .authenticated = service.authState {
                        Button {
                            showingMatchmaker = true
                        } label: {
                            Label("새 매치 찾기", systemImage: "person.badge.plus")
                                .frame(maxWidth: .infinity)
                                .brassButton(prominent: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("online.newMatch")

                        VStack(alignment: .leading, spacing: 10) {
                            Text("진행 중인 매치").font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
                            if service.activeMatches.isEmpty {
                                Text("없음").foregroundStyle(theme.inkSecondary)
                            }
                            ForEach(service.activeMatches, id: \.matchID) { match in
                                Button {
                                    container.startOnlineMatch(match)
                                } label: {
                                    HStack {
                                        Text(opponentName(of: match)).foregroundStyle(theme.ink)
                                        Spacer()
                                        Text(isMyTurn(match) ? "내 차례" : "상대 차례")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(isMyTurn(match) ? theme.brassInk : theme.inkSecondary)
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(Capsule().fill(isMyTurn(match) ? theme.brass : theme.paperLine))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .paperCard(padding: 14)
                    }

                    if let error = container.onlineError {
                        Text(error).foregroundStyle(.red).paperCard(padding: 12)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("온라인 대전")
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { service.authenticate() }
        .refreshable { await service.reloadMatches() }
        .sheet(isPresented: $showingMatchmaker) { MatchmakerView().ignoresSafeArea() }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch service.authState {
        case .unknown:
            Label("Game Center에 연결하는 중…", systemImage: "hourglass")
                .foregroundStyle(theme.inkSecondary)
                .accessibilityIdentifier("online.status")
        case .authenticated(let name):
            Label("\(name)으로 로그인됨", systemImage: "checkmark.circle")
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("online.status")
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 4) {
                Label("Game Center를 쓸 수 없습니다", systemImage: "exclamationmark.triangle").foregroundStyle(theme.ink)
                Text(reason).font(.caption).foregroundStyle(theme.inkSecondary)
            }
            .accessibilityIdentifier("online.status")
        }
    }

    private func opponentName(of match: GKTurnBasedMatch) -> String {
        let others = match.participants.filter { $0.player?.gamePlayerID != service.localPlayerID }
        let names = others.map { $0.player?.displayName ?? "상대 찾는 중" }
        return names.isEmpty ? "상대 찾는 중" : names.joined(separator: ", ")
    }

    private func isMyTurn(_ match: GKTurnBasedMatch) -> Bool {
        match.currentParticipant?.player?.gamePlayerID == service.localPlayerID
    }
}
