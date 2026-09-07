import SwiftUI
import GameKit

/// 온라인 대전 화면. 로그인 상태, 새 매치 찾기, 진행 중인 매치.
struct OnlineMenu: View {
    let container: AppContainer

    @State private var showingMatchmaker = false

    private var service: GameCenterService { container.gameCenter }

    var body: some View {
        List {
            Section {
                statusRow
            }
            if case .authenticated = service.authState {
                Section {
                    Button {
                        showingMatchmaker = true
                    } label: {
                        Label("새 매치 찾기", systemImage: "person.badge.plus")
                    }
                    .accessibilityIdentifier("online.newMatch")
                }
                Section("진행 중인 매치") {
                    if service.activeMatches.isEmpty {
                        Text("없음").foregroundStyle(.secondary)
                    }
                    ForEach(service.activeMatches, id: \.matchID) { match in
                        Button {
                            container.startOnlineMatch(match)
                        } label: {
                            HStack {
                                Text(opponentName(of: match))
                                Spacer()
                                Text(isMyTurn(match) ? "내 차례" : "상대 차례")
                                    .font(.caption)
                                    .foregroundStyle(isMyTurn(match) ? Color.accentColor : .secondary)
                            }
                        }
                    }
                }
            }
            if let error = container.onlineError {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("온라인 대전")
        .onAppear { service.authenticate() }
        .refreshable { await service.reloadMatches() }
        .sheet(isPresented: $showingMatchmaker) { MatchmakerView().ignoresSafeArea() }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch service.authState {
        case .unknown:
            Label("Game Center에 연결하는 중…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("online.status")
        case .authenticated(let name):
            Label("\(name)으로 로그인됨", systemImage: "checkmark.circle")
                .accessibilityIdentifier("online.status")
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 4) {
                Label("Game Center를 쓸 수 없습니다", systemImage: "exclamationmark.triangle")
                Text(reason).font(.caption).foregroundStyle(.secondary)
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
