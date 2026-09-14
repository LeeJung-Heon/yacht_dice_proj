import SwiftUI

struct CupPongMenu: View {
    let container: AppContainer
    @Environment(\.theme) private var theme
    @State private var names = ["나", "상대"]
    @State private var showingLocalSetup = false
    @State private var showingOnline = false
    @State private var showingCustomization = false

    var body: some View {
        NavigationStack {
            ZStack {
                WoodBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 6) {
                            Text("컵퐁").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
                            Text("컵 열 개 · 넣으면 한 번 더").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(theme.brass)
                        }.padding(.top, 8).padding(.bottom, 10)
                        ModeCard(icon: "photo.on.rectangle.angled", title: "나만의 컵", subtitle: "컵마다 사진을 넣고 친구와 공유한다", identifier: "menu.cuppong.customize") {
                            showingCustomization = true
                        }
                        if let saved = container.savedRecord, saved.game == "cuppong" {
                            ModeCard(icon: "bookmark.fill", title: "이어하기", subtitle: saved.mode.title, identifier: "menu.resume") {
                                container.resumeSavedGame()
                            }
                        }
                        ModeCard(icon: "person.2", title: "로컬 2인", subtitle: "한 기기에서 번갈아 던진다", identifier: "menu.cuppong.local") {
                            showingLocalSetup = true
                        }
                        ModeCard(icon: "network", title: "온라인 대전", subtitle: "방 코드로 친구와 겨룬다", identifier: "menu.cuppong.online") {
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
            .navigationDestination(isPresented: $showingOnline) { OnlineMenu(container: container, game: .cuppong) }
            .sheet(isPresented: $showingCustomization) { CupPongCustomizationView(service: container.supabase) }
            .sheet(isPresented: $showingLocalSetup) {
                NavigationStack {
                    Form {
                        TextField("나", text: $names[0]).accessibilityIdentifier("menu.cuppong.name.0")
                        TextField("상대", text: $names[1]).accessibilityIdentifier("menu.cuppong.name.1")
                    }
                    .navigationTitle("로컬 2인")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("시작") {
                                showingLocalSetup = false
                                container.startCupPongLocal(names: names.map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? "플레이어" : $0 })
                            }.accessibilityIdentifier("menu.cuppong.local.start")
                        }
                        ToolbarItem(placement: .cancellationAction) { Button("취소") { showingLocalSetup = false } }
                    }
                }
            }
        }
    }
}
