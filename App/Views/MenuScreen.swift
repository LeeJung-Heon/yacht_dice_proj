import SwiftUI
import YachtBot

struct MenuScreen: View {
    let container: AppContainer

    @State private var localPlayerCount = 2
    @State private var localNames = ["플레이어 1", "플레이어 2", "플레이어 3", "플레이어 4"]
    @State private var showingBotPicker = false
    @State private var showingLocalSetup = false

    var body: some View {
        NavigationStack {
            List {
                if let saved = container.savedRecord {
                    Section {
                        Button {
                            container.resumeSavedGame()
                        } label: {
                            Label("이어하기 · \(saved.mode.title) · Turn \(saved.log.state.turnIndex)/12",
                                  systemImage: "play.fill")
                        }
                        .accessibilityIdentifier("menu.resume")
                    }
                }

                Section("새 게임") {
                    Button { container.startGame(mode: .solo) } label: {
                        Label("혼자 연습", systemImage: "person")
                    }
                    .accessibilityIdentifier("menu.solo")

                    Button { showingBotPicker = true } label: {
                        Label("컴퓨터 대전", systemImage: "cpu")
                    }
                    .accessibilityIdentifier("menu.bot")

                    Button { showingLocalSetup = true } label: {
                        Label("로컬 2~4인", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("menu.local")

                    Button {} label: {
                        Label("온라인 대전 (준비 중)", systemImage: "network")
                    }
                    .disabled(true)
                    .accessibilityIdentifier("menu.online")
                }
            }
            .navigationTitle("요트 다이스")
            .confirmationDialog("난이도", isPresented: $showingBotPicker, titleVisibility: .visible) {
                ForEach(BotDifficulty.allCases, id: \.self) { difficulty in
                    Button(difficulty.displayName) { container.startGame(mode: .versusBot(difficulty)) }
                        .accessibilityIdentifier("menu.bot.\(difficulty.rawValue)")
                }
            }
            .sheet(isPresented: $showingLocalSetup) { localSetup }
        }
    }

    private var localSetup: some View {
        NavigationStack {
            Form {
                Picker("인원", selection: $localPlayerCount) {
                    ForEach(2...4, id: \.self) { count in
                        Text("\(count)명").tag(count).accessibilityIdentifier("menu.local.count.\(count)")
                    }
                }
                .pickerStyle(.segmented)
                ForEach(0..<localPlayerCount, id: \.self) { index in
                    TextField("플레이어 \(index + 1)", text: $localNames[index])
                        .accessibilityIdentifier("menu.local.name.\(index)")
                }
            }
            .navigationTitle("로컬 대전")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("시작") {
                        showingLocalSetup = false
                        let names = localNames.prefix(localPlayerCount).map {
                            $0.trimmingCharacters(in: .whitespaces).isEmpty ? "플레이어" : $0
                        }
                        container.startGame(mode: .passAndPlay(names: Array(names)))
                    }
                    .accessibilityIdentifier("menu.local.start")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { showingLocalSetup = false }
                }
            }
        }
    }
}
