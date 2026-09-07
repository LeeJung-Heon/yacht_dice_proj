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
    @FocusState private var focusedField: Field?

    private enum Field { case nickname, code }

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
        }
        .navigationTitle("온라인 대전")
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            nickname = service.nickname
            await service.signIn()
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
                .focused($focusedField, equals: .nickname)
                .submitLabel(.done)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.trailing)
                .onChange(of: nickname) { _, value in service.nickname = String(value.prefix(20)) }
                .accessibilityIdentifier("online.nickname")
        }
        .paperCard(padding: 14)
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("방 만들기").font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
            Text("코드를 상대에게 알려주면 상대가 들어온다.").font(.caption).foregroundStyle(theme.inkSecondary)
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
                    .focused($focusedField, equals: .code)
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
            Text("이 코드를 상대에게 알려준다.").font(.caption).foregroundStyle(theme.inkSecondary)
            ProgressView().tint(theme.brass)
            Button("취소") {
                waitTask?.cancel()
                waitingRoom = nil
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.brass)
            .accessibilityIdentifier("online.cancelWait")
        }
        .frame(maxWidth: .infinity)
        .paperCard(padding: 16)
    }

    private var matchesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("진행 중인 매치").font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
            if service.myMatches.isEmpty {
                Text("없음").foregroundStyle(theme.inkSecondary)
            }
            ForEach(service.myMatches, id: \.id) { row in
                Button {
                    open(row)
                } label: {
                    HStack {
                        Text(opponentName(of: row)).foregroundStyle(theme.ink)
                        Spacer()
                        Text(rowStatus(row))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isMyTurn(row) ? theme.brassInk : theme.inkSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(isMyTurn(row) ? theme.brass : theme.paperLine))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .paperCard(padding: 14)
    }

    // MARK: - 동작

    private func createRoom() async {
        focusedField = nil
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

    /// 게스트가 들어오면 행이 UPDATE되므로 그 순간까지 Realtime으로 기다린다.
    private func waitForGuest(_ room: MatchRow) {
        waitTask?.cancel()
        let client = service.client
        waitTask = Task {
            let idText = room.id.uuidString.lowercased()
            let channel = client.channel("wait-\(idText)")
            let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "matches",
                                                 filter: "id=eq.\(idText)")
            guard (try? await channel.subscribeWithError()) != nil else { return }
            for await update in updates {
                guard !Task.isCancelled else { break }
                if let updated = try? update.decodeRecord(as: MatchRow.self, decoder: JSONDecoder()),
                   updated.guestUid != nil {
                    await channel.unsubscribe()
                    waitingRoom = nil
                    open(updated)
                    return
                }
            }
            await channel.unsubscribe()
        }
    }

    private func joinRoom() async {
        focusedField = nil
        busy = true
        defer { busy = false }
        message = nil
        do {
            let row = try await service.joinRoom(code: codeInput, name: trimmedName)
            open(row)
        } catch {
            message = "들어가지 못했다: 코드를 확인하거나 방이 이미 찼는지 본다"
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

    private func rowStatus(_ row: MatchRow) -> String {
        if row.isWaiting { return "코드 \(row.code)" }
        return isMyTurn(row) ? "내 차례" : "상대 차례"
    }
}
