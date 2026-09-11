import SwiftUI

struct AlkkagiMenu: View {
    let container: AppContainer
    @Environment(\.theme) private var theme
    @State private var names = ["흑", "백"]
    @State private var showingLocalSetup = false
    @State private var showingOnline = false

    var body: some View {
        NavigationStack {
            ZStack {
                WoodBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 6) {
                            Text("알까기").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
                            Text("돌을 튕겨 밀어낸다").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(theme.brass)
                        }.padding(.top, 8).padding(.bottom, 10)
                        if let saved = container.savedRecord, saved.game == "alkkagi" {
                            ModeCard(icon: "bookmark.fill", title: "이어하기", subtitle: saved.mode.title, identifier: "menu.resume") {
                                container.resumeSavedGame()
                            }
                        }
                        ModeCard(icon: "person.2", title: "로컬 2인", subtitle: "한 기기에서 번갈아 튕긴다", identifier: "menu.alkkagi.local") {
                            showingLocalSetup = true
                        }
                        ModeCard(icon: "network", title: "온라인 대전", subtitle: "방 코드로 친구와 겨룬다", identifier: "menu.alkkagi.online") {
                            showingOnline = true
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { container.returnToHub() } label: { Image(systemName: "chevron.left").foregroundStyle(theme.ivory) }
                        .accessibilityIdentifier("menu.back").accessibilityLabel("허브로")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingOnline) { OnlineMenu(container: container, game: .alkkagi) }
            .sheet(isPresented: $showingLocalSetup) {
                NavigationStack {
                    Form {
                        TextField("흑", text: $names[0]).accessibilityIdentifier("menu.alkkagi.name.0")
                        TextField("백", text: $names[1]).accessibilityIdentifier("menu.alkkagi.name.1")
                    }
                    .navigationTitle("로컬 2인")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("시작") {
                                showingLocalSetup = false
                                container.startAlkkagiLocal(names: names.map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? "플레이어" : $0 })
                            }.accessibilityIdentifier("menu.alkkagi.local.start")
                        }
                        ToolbarItem(placement: .cancellationAction) { Button("취소") { showingLocalSetup = false } }
                    }
                }
            }
        }
    }
}
