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

/// 자리 표시자. 전적을 모으고 보여주는 일은 Task 7이 채운다.
struct RecordsCard: View {
    let container: AppContainer

    var body: some View {
        Text("전적은 곧 보인다")
            .font(.caption)
            .paperCard(padding: 14)
            .accessibilityIdentifier("hub.records")
    }
}
