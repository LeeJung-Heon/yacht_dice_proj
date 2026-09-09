import SwiftUI
import Supabase

/// 온라인 대전 화면. 닉네임, 방 만들기(코드 표시·대기), 코드 입력, 진행 중인 매치.
/// Supabase 방 코드 방식이다. Game Center 코드는 유료 계정을 만든 뒤 쓰도록 남겨 두었다.
struct OnlineMenu: View {
    let container: AppContainer

    @Environment(\.theme) private var theme
    @State private var nickname = ""
    @State private var codeInput = ""
    @State private var waitingRoom: MatchRow?
    @State private var busy = false
    @State private var message: String?
    @State private var waitTask: Task<Void, Never>?
    /// 입장 진행 팝업의 문구. nil이면 팝업이 없다.
    @State private var entryStatus: String?

    private var service: SupabaseService { container.supabase }
    private var trimmedName: String { nickname.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            WoodBackground()
            ScrollView {
                VStack(spacing: 14) {
                    statusRow.paperCard(padding: 14)

                    if case .signedIn = service.authState {
                        nicknameCard
                        if let room = waitingRoom {
                            waitingCard(room)
                        } else {
                            createCard
                            joinCard
                        }
                        matchesCard
                    }

                    if let message = message ?? container.onlineError {
                        Text(message).foregroundStyle(.red).font(.footnote).paperCard(padding: 12)
                            .accessibilityIdentifier("online.message")
                    }
                }
                .padding(16)
            }
            if let entryStatus {
                entryOverlay(entryStatus)
            }
        }
        .navigationTitle("온라인 대전")
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            nickname = service.nickname
            await service.signIn()
            resumeWaitingRoomIfAny()
            // 상대가 턴을 끝내면 앱이 닫혀 있어도 알림이 오도록 이 기기를 등록한다
            if service.uid != nil, !ProcessInfo.processInfo.arguments.contains("-noPush") {
                await PushRegistration.shared.requestAndRegister(service: service)
            }
        }
        .refreshable { await service.reloadMatches() }
        .onDisappear { waitTask?.cancel() }
    }

    // MARK: - 카드

    @ViewBuilder
    private var statusRow: some View {
        switch service.authState {
        case .unknown:
            Label("서버에 연결하는 중…", systemImage: "hourglass")
                .foregroundStyle(theme.inkSecondary)
                .accessibilityIdentifier("online.status")
        case .signedIn:
            Label("연결됨", systemImage: "checkmark.circle")
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("online.status")
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 4) {
                Label("서버에 연결할 수 없다", systemImage: "exclamationmark.triangle").foregroundStyle(theme.ink)
                Text(reason).font(.caption).foregroundStyle(theme.inkSecondary)
            }
            .accessibilityIdentifier("online.status")
        }
    }

    private var nicknameCard: some View {
        HStack {
            Text("닉네임").foregroundStyle(theme.inkSecondary)
            TextField("이름", text: $nickname)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.trailing)
                .submitLabel(.done)
                .onChange(of: nickname) { _, value in service.nickname = String(value.prefix(20)) }
                .accessibilityIdentifier("online.nickname")
        }
        .paperCard(padding: 14)
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("방 만들기").font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
            Text("코드를 상대에게 알려주면 상대가 들어오는 순간 게임이 시작된다.").font(.caption).foregroundStyle(theme.inkSecondary)
            Button {
                Task { await createRoom() }
            } label: {
                Label("새 방", systemImage: "plus.circle").frame(maxWidth: .infinity).brassButton(prominent: true)
            }
            .buttonStyle(.plain)
            .disabled(busy || trimmedName.isEmpty)
            .accessibilityIdentifier("online.create")
        }
        .paperCard(padding: 14)
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("코드로 들어가기").font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
            HStack(spacing: 10) {
                TextField("6자리 코드", text: $codeInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .onChange(of: codeInput) { _, value in codeInput = String(value.filter(\.isNumber).prefix(6)) }
                    .accessibilityIdentifier("online.code")
                Button {
                    Task { await joinRoom() }
                } label: {
                    Text("들어가기").brassButton(prominent: false, compact: true)
                }
                .buttonStyle(.plain)
                .disabled(busy || trimmedName.isEmpty || !MatchRow.isValidCode(codeInput))
                .accessibilityIdentifier("online.join")
            }
        }
        .paperCard(padding: 14)
    }

    private func waitingCard(_ room: MatchRow) -> some View {
        VStack(spacing: 10) {
            Text("상대를 기다리는 중").font(.caption).foregroundStyle(theme.inkSecondary)
            Text(room.code)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .tracking(8)
                .monospacedDigit()
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("online.roomCode")
                .accessibilityLabel("방 코드 \(room.code.map(String.init).joined(separator: " "))")
            Text("이 코드를 상대에게 알려준다. 상대가 들어오면 바로 시작된다.").font(.caption).foregroundStyle(theme.inkSecondary)
            ProgressView().tint(theme.brass)
            Button("방 닫기") {
                Task { await cancelRoom(room) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.brass)
            .accessibilityIdentifier("online.cancelWait")
        }
        .frame(maxWidth: .infinity)
        .paperCard(padding: 16)
    }

    private var matchesCard: some View {
        // 대기 방은 위 카드가 보여주므로 목록에는 진행 중인 판만 둔다
        let playing = service.myMatches.filter { !$0.isWaiting }
        return VStack(alignment: .leading, spacing: 10) {
            Text("진행 중인 매치").font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
            if playing.isEmpty {
                Text("없음").foregroundStyle(theme.inkSecondary)
            }
            ForEach(playing, id: \.id) { row in
                HStack(spacing: 8) {
                    Button {
                        open(row)
                    } label: {
                        HStack {
                            Text(opponentName(of: row)).foregroundStyle(theme.ink)
                            Spacer()
                            Text(row.isAbandoned ? "상대가 떠남" : isMyTurn(row) ? "내 차례" : "상대 차례")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(!row.isAbandoned && isMyTurn(row) ? theme.brassInk : theme.inkSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(!row.isAbandoned && isMyTurn(row) ? theme.brass : theme.paperLine))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { try? await service.deleteMatch(id: row.id) }
                    } label: {
                        Image(systemName: "trash").foregroundStyle(theme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("이 매치 삭제")
                }
            }
        }
        .paperCard(padding: 14)
    }

    private func entryOverlay(_ text: String) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(theme.brass).scaleEffect(1.3)
                Text(text)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
            }
            .paperCard(padding: 24)
            .padding(40)
        }
        .accessibilityIdentifier("online.entry")
        .accessibilityLabel(text)
    }

    // MARK: - 동작

    private func createRoom() async {
        busy = true
        defer { busy = false }
        message = nil
        do {
            let room = try await service.createRoom(name: trimmedName)
            waitingRoom = room
            waitForGuest(room)
        } catch {
            message = "방을 만들지 못했다: \(error.localizedDescription)"
        }
    }

    /// 앱을 나갔다 와도 내 대기 방이 있으면 다시 코드를 보여주고 기다린다.
    private func resumeWaitingRoomIfAny() {
        guard waitingRoom == nil, let uid = service.uid,
              let room = service.myMatches.first(where: { $0.isWaiting && $0.hostUid == uid }) else { return }
        waitingRoom = room
        waitForGuest(room)
    }

    /// 게스트가 들어오면 행이 UPDATE된다. Realtime으로 받되, 연결이 늦거나 끊겼을 때를 대비해 2초마다 한 번씩 직접 읽는다.
    private func waitForGuest(_ room: MatchRow) {
        waitTask?.cancel()
        let client = service.client
        waitTask = Task {
            let idText = room.id.uuidString.lowercased()
            let channel = client.channel("wait-\(idText)")
            let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "matches",
                                                 filter: "id=eq.\(idText)")
            let subscribed = (try? await channel.subscribeWithError()) != nil
            defer { Task { await channel.unsubscribe() } }

            await withTaskGroup(of: MatchRow?.self) { group in
                if subscribed {
                    group.addTask {
                        for await update in updates {
                            if Task.isCancelled { return nil }
                            if let updated = try? update.decodeRecord(as: MatchRow.self, decoder: JSONDecoder()),
                               updated.guestUid != nil { return updated }
                        }
                        return nil
                    }
                }
                group.addTask {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        if let fresh = try? await service.fetchMatch(id: room.id), fresh.guestUid != nil { return fresh }
                    }
                    return nil
                }
                for await result in group {
                    if let joined = result {
                        group.cancelAll()
                        await enterGame(joined, announcing: "\(joined.guestName ?? "상대") 입장 — 게임을 시작한다")
                        return
                    }
                }
            }
        }
    }

    private func cancelRoom(_ room: MatchRow) async {
        waitTask?.cancel()
        waitingRoom = nil
        try? await service.deleteMatch(id: room.id)
        await service.reloadMatches()
    }

    private func joinRoom() async {
        busy = true
        defer { busy = false }
        message = nil
        entryStatus = "입장 중…"
        do {
            let row = try await service.joinRoom(code: codeInput, name: trimmedName)
            await enterGame(row, announcing: "\(row.hostName)의 방에 들어왔다 — 게임을 시작한다")
        } catch {
            entryStatus = nil
            message = "들어가지 못했다: 코드를 확인하거나 방이 이미 찼는지 본다"
        }
    }

    /// 입장 팝업을 잠깐 보여준 뒤 게임을 연다. 화면이 갑자기 바뀌지 않게 한 박자 둔다.
    private func enterGame(_ row: MatchRow, announcing text: String) async {
        entryStatus = text
        try? await Task.sleep(for: .milliseconds(1100))
        waitingRoom = nil
        entryStatus = nil
        if !container.openSupabaseMatch(row) {
            message = container.onlineError
        }
    }

    private func open(_ row: MatchRow) {
        if row.isWaiting {
            waitingRoom = row
            waitForGuest(row)
            return
        }
        if !container.openSupabaseMatch(row) {
            message = container.onlineError
        }
    }

    private func opponentName(of row: MatchRow) -> String {
        guard let uid = service.uid else { return "상대" }
        if row.hostUid == uid { return row.guestName ?? "상대 기다리는 중" }
        return row.hostName
    }

    private func isMyTurn(_ row: MatchRow) -> Bool {
        guard let uid = service.uid, row.guestUid != nil else { return false }
        let mySeat = row.hostUid == uid ? 0 : 1
        return row.log.state.currentPlayer == mySeat
    }
}
