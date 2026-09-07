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

                    Button { withAnimation { showingBotPicker.toggle() } } label: {
                        HStack {
                            Label("컴퓨터 대전", systemImage: "cpu")
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showingBotPicker ? 180 : 0))
                        }
                    }
                    .accessibilityIdentifier("menu.bot")
                    .accessibilityValue(showingBotPicker ? "난이도 펼침" : "난이도 접힘")

                    // confirmationDialog는 버튼 식별자를 여러 요소에 복제해 UI 테스트가 하나를 고르지 못한다.
                    // 목록 안에 펼치는 편이 손가락으로도 한 번 덜 누른다.
                    if showingBotPicker {
                        ForEach(BotDifficulty.allCases, id: \.self) { difficulty in
                            Button { container.startGame(mode: .versusBot(difficulty)) } label: {
                                Label(difficulty.displayName, systemImage: difficultyIcon(difficulty))
                                    .padding(.leading, 28)
                            }
                            .accessibilityIdentifier("menu.bot.\(difficulty.rawValue)")
                            .accessibilityLabel("컴퓨터 대전, \(difficulty.displayName)")
                        }
                    }

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
            .sheet(isPresented: $showingLocalSetup) { localSetup }
        }
    }

    private func difficultyIcon(_ difficulty: BotDifficulty) -> String {
        switch difficulty {
        case .easy: "tortoise"
        case .normal: "hare"
        case .hard: "brain"
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
