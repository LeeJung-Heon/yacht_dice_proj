import SwiftUI
import YachtBot
import YachtCore

struct MenuScreen: View {
    let container: AppContainer

    @Environment(\.theme) private var theme
    @State private var localPlayerCount = 2
    @State private var localNames = ["플레이어 1", "플레이어 2", "플레이어 3", "플레이어 4"]
    @State private var showingBotPicker = false
    @State private var showingLocalSetup = false
    @State private var showingSettings = false
    @State private var showingOnline = false

    var body: some View {
        NavigationStack {
            ZStack {
                WoodBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        titleLockup.padding(.top, 8).padding(.bottom, 10)

                        if let saved = container.savedRecord, saved.isYacht {
                            resumeCard(saved)
                        }

                        ModeCard(icon: "person", title: "혼자 연습", subtitle: "12턴, 최고 점수에 도전",
                                 identifier: "menu.solo") {
                            container.startGame(mode: .solo)
                        }

                        ModeCard(icon: "cpu", title: "컴퓨터 대전", subtitle: "난이도 셋 중 하나를 고른다",
                                 identifier: "menu.bot", expanded: showingBotPicker) {
                            withAnimation(.easeOut(duration: 0.2)) { showingBotPicker.toggle() }
                        } accessory: {
                            // confirmationDialog는 버튼 식별자를 여러 요소에 복제해 UI 테스트가 하나를 고르지 못한다.
                            // 카드 안에 펼치는 편이 손가락으로도 한 번 덜 누른다.
                            if showingBotPicker {
                                HStack(spacing: 8) {
                                    ForEach(BotDifficulty.allCases, id: \.self) { difficulty in
                                        Button {
                                            container.startGame(mode: .versusBot(difficulty))
                                        } label: {
                                            Label(difficulty.displayName, systemImage: difficultyIcon(difficulty))
                                                .frame(maxWidth: .infinity)
                                                .brassButton(prominent: difficulty == .normal, compact: true)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("menu.bot.\(difficulty.rawValue)")
                                        .accessibilityLabel("컴퓨터 대전, \(difficulty.displayName)")
                                    }
                                }
                                .padding(.top, 12)
                            }
                        }

                        ModeCard(icon: "person.2", title: "로컬 2~4인", subtitle: "한 기기를 번갈아 잡고 겨룬다",
                                 identifier: "menu.local") {
                            showingLocalSetup = true
                        }

                        ModeCard(icon: "network", title: "온라인 대전", subtitle: "방 코드로 친구와 겨룬다",
                                 identifier: "menu.online") {
                            showingOnline = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(theme.ivory)
                    }
                    .accessibilityIdentifier("menu.settings")
                    .accessibilityLabel("설정")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingOnline) { OnlineMenu(container: container) }
            .sheet(isPresented: $showingLocalSetup) { localSetup }
            .sheet(isPresented: $showingSettings) { SettingsSheet() }
        }
    }

    private var titleLockup: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                DieFaceView(value: 5, size: 34).rotationEffect(.degrees(-10))
                DieFaceView(value: 2, size: 34).rotationEffect(.degrees(8))
            }
            Text("요트 다이스")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(theme.ivory)
            Text("YACHT DICE")
                .font(.caption.weight(.semibold))
                .tracking(4)
                .foregroundStyle(theme.brass)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("요트 다이스")
    }

    private func resumeCard(_ saved: MatchRecord) -> some View {
        let turn = saved.log.state.turnIndex
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("진행 중인 판", systemImage: "bookmark.fill").font(.caption).foregroundStyle(theme.brass)
                Spacer()
                Text("Turn \(turn)/\(YachtCore.turnCount)").font(.caption).foregroundStyle(theme.inkSecondary).monospacedDigit()
            }
            Text(saved.mode.title).font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
            ProgressView(value: Double(turn - 1), total: Double(YachtCore.turnCount)).tint(theme.brass)
            Button {
                container.resumeSavedGame()
            } label: {
                Label("이어하기", systemImage: "play.fill").frame(maxWidth: .infinity).brassButton(prominent: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.resume")
        }
        .paperCard(padding: 14)
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
