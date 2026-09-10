import SwiftUI

/// 시작 화면. 게임 타일 넷과 진행 중인 판·전적 카드.
struct HubScreen: View {
    let container: AppContainer
    @Environment(\.theme) private var theme
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                WoodBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 6) {
                            Text("게임 테이블").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
                            Text("GAME TABLE").font(.caption.weight(.semibold)).tracking(4).foregroundStyle(theme.brass)
                        }
                        .padding(.top, 8).padding(.bottom, 6)
                        .accessibilityElement(children: .combine)

                        if let saved = container.savedRecord, let game = GameID(rawValue: saved.game) {
                            ModeCard(icon: "bookmark.fill", title: "이어하기 · \(game.title)", subtitle: saved.mode.title,
                                     identifier: "hub.resume") { container.resumeSavedGame() }
                        }

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(GameID.allCases, id: \.self) { game in
                                Button { container.showMenu(game) } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: game.icon).font(.system(size: 30)).foregroundStyle(theme.brass)
                                        Text(game.title).font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
                                        Text(game.isAvailable ? game.subtitle : "준비 중").font(.caption).foregroundStyle(theme.inkSecondary)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                                    .paperCard(padding: 12)
                                    .opacity(game.isAvailable ? 1 : 0.55)
                                }
                                .buttonStyle(.plain)
                                .disabled(!game.isAvailable)
                                .accessibilityIdentifier("hub.\(game.rawValue)")
                                .accessibilityLabel("\(game.title)\(game.isAvailable ? "" : ", 준비 중")")
                            }
                        }

                        RecordsCard(container: container)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
            .task { await container.bootstrap() }
            .navigationDestination(for: RecordsRoute.self) { _ in RecordsScreen(container: container) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape").foregroundStyle(theme.ivory) }
                        .accessibilityIdentifier("menu.settings").accessibilityLabel("설정")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) { SettingsSheet() }
        }
    }
}

/// 허브의 "전체 보기"가 미는 목적지. 값 하나뿐이라 빈 구조체다.
struct RecordsRoute: Hashable {}

/// 게임별 승·패·무와 최근 세 판. 전체는 `RecordsScreen`이 보여준다.
struct RecordsCard: View {
    let container: AppContainer
    @Environment(\.theme) private var theme

    private var records: [RecordRow] { container.records.records }
    private var recent: [RecentMatch] { container.records.recent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("전적").font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
                Spacer()
                NavigationLink(value: RecordsRoute()) {
                    Text("전체 보기").font(.caption.weight(.semibold)).foregroundStyle(theme.brass)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hub.records.all")
            }

            if records.isEmpty {
                Text("아직 전적이 없다").font(.callout).foregroundStyle(theme.inkSecondary)
            } else {
                ForEach(records, id: \.game) { row in
                    HStack {
                        Text(GameID(rawValue: row.game)?.title ?? row.game).foregroundStyle(theme.ink)
                        Spacer()
                        Text("승 \(row.wins) · 패 \(row.losses) · 무 \(row.draws)")
                            .font(.callout.monospacedDigit()).foregroundStyle(theme.inkSecondary)
                    }
                }
            }

            if !recent.isEmpty {
                Divider().overlay(theme.paperLine)
                ForEach(recent.prefix(3), id: \.id) { match in
                    RecentRow(match: match)
                }
            }

            gameCenterLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 14)
        .accessibilityIdentifier("hub.records")
    }

    @ViewBuilder
    private var gameCenterLine: some View {
        switch container.gameCenter.authState {
        case .authenticated(_, let name):
            Label("Game Center · \(name)", systemImage: "person.crop.circle")
                .font(.caption).foregroundStyle(theme.inkSecondary)
        case .unavailable:
            Text("Game Center 미로그인 — 전적은 이 기기에만 남는다")
                .font(.caption).foregroundStyle(theme.inkSecondary)
        case .unknown:
            EmptyView()
        }
    }
}

/// 최근 매치 한 줄: 게임 · 상대 · 결과. 전적 화면은 끝난 날짜까지 보여준다.
struct RecentRow: View {
    let match: RecentMatch
    var showsDate = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(GameID(rawValue: match.game)?.title ?? match.game)
                .font(.caption).foregroundStyle(theme.inkSecondary)
            Text(match.opponent).foregroundStyle(theme.ink).lineLimit(1)
            if showsDate, let finishedAt = match.finishedAt {
                Text(finishedAt.formatted(.dateTime.month().day()))
                    .font(.caption2).foregroundStyle(theme.inkSecondary)
            }
            Spacer()
            Text(match.result)
                .font(.caption.weight(.semibold))
                .foregroundStyle(match.result == "승" ? theme.brassInk : theme.inkSecondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(match.result == "승" ? theme.brass : theme.paperLine))
        }
        .accessibilityElement(children: .combine)
    }
}
