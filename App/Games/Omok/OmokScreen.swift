import SwiftUI
import GameCore

/// 오목 한 판. 교차점을 탭해 자리를 고르고 "놓기"로 확정한다 — 로컬 2인은 한 기기에서 좌석이 번갈아 넘어간다.
struct OmokScreen: View {
    let match: OnlineMatch<Omok>
    var onReturn: () -> Void = {}
    @Environment(\.theme) private var theme
    @State private var preview: Omok.Move?
    @State private var animating: Omok.Move?
    @State private var turnBanner: String?
    @State private var moveToast: String?
    /// 채널이 3초 넘게 끊겨 있을 때만 띠를 보인다. 짧은 재접속은 조용히 지나간다.
    @State private var showDisconnected = false
    @State private var disconnectTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    private var seatNames: [String] { match.participants.map(\.displayName) }

    var body: some View {
        ZStack {
            WoodBackground()
            VStack(spacing: 12) {
                header
                seats
                OmokBoardView(state: match.state, preview: preview, previewSeat: match.localSeat ?? 0, animating: animating) { move in
                    guard match.isLocalTurn, Omok.canApply(move, to: match.state) else { return }
                    preview = move
                    Haptics.shared.play(.selection)
                }
                .padding(.horizontal, 12)
                actionBar
                Spacer(minLength: 0)
            }
            .overlay(alignment: .top) {
                if showDisconnected {
                    Label("연결 끊김 — 재연결 중", systemImage: "wifi.slash").font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6).background(theme.ink.opacity(0.85), in: Capsule())
                        .foregroundStyle(theme.paper).padding(.top, 118).accessibilityIdentifier("online.connection")
                }
            }
            .overlay(alignment: .top) {
                if let error = match.lastTransportError {
                    Text(error).font(.caption).padding(8).background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white).padding(.top, 48).accessibilityIdentifier("online.error")
                }
            }
            .overlay { if let turnBanner { TurnBanner(text: turnBanner).transition(.scale(scale: 0.9).combined(with: .opacity)) } }
            .overlay(alignment: .top) {
                if let moveToast { ScoreToast(text: moveToast).padding(.top, 118).transition(.move(edge: .top).combined(with: .opacity)) }
            }
        }
        .task { match.onRemoteMove = { move, _ in await replayRemote(move) } }
        .onChange(of: match.log.moves.count, initial: true) { _, _ in
            preview = nil
            if match.outcome == nil, let seat = Omok.currentSeat(match.state) {
                showBanner(match.isLocalTurn ? "내 차례" : "\(seatNames[seat]) 차례")
            }
        }
        .onChange(of: match.lastRemoteMove?.id) { _, _ in
            guard let remote = match.lastRemoteMove else { return }
            showToast("\(seatNames[remote.seat]): \(remote.move.x + 1)열 \(remote.move.y + 1)행")
        }
        .onChange(of: match.isConnected, initial: true) { _, connected in
            disconnectTask?.cancel()
            if connected { withAnimation { showDisconnected = false } }
            else { disconnectTask = Task { try? await Task.sleep(for: .seconds(3)); guard !Task.isCancelled else { return }; withAnimation { showDisconnected = true } } }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await match.resync() } } }
    }

    private var header: some View {
        HStack {
            Button(action: onReturn) { Image(systemName: "chevron.left").foregroundStyle(theme.ivory) }
                .accessibilityIdentifier("header.menu").accessibilityLabel("메뉴로")
            Spacer()
            Text("오목").font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
            Spacer()
            Text("\(match.log.moves.count)수").font(.caption).monospacedDigit().foregroundStyle(theme.brass).accessibilityIdentifier("header.status")
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    /// 명패 둘. 현재 차례는 황동, 원격 상대는 접속 점.
    private var seats: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { seat in
                let current = Omok.currentSeat(match.state) == seat
                HStack(spacing: 6) {
                    Circle().fill(seat == 0 ? .black : .white).frame(width: 12, height: 12).overlay(Circle().stroke(.black.opacity(0.4)))
                    if case .remote = match.participants[seat] {
                        Circle().fill(match.opponentPresent ? Color.green : theme.inkSecondary.opacity(0.5)).frame(width: 7, height: 7)
                            .accessibilityIdentifier("players.presence.\(seat)")
                    }
                    Text(seatNames[seat]).font(.caption).lineLimit(1)
                }
                .foregroundStyle(current ? theme.brassInk : theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(current ? theme.brass : theme.paper))
                .accessibilityIdentifier("players.seat.\(seat)")
                .accessibilityLabel("\(seatNames[seat])\(current ? ", 현재 차례" : "")")
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var actionBar: some View {
        if let outcome = match.outcome {
            VStack(spacing: 10) {
                Text(resultText(outcome)).font(.system(.title2, design: .serif, weight: .semibold)).foregroundStyle(theme.ink)
                    .accessibilityIdentifier("omok.result")
                Button(action: onReturn) { Label("메뉴로", systemImage: "chevron.left").frame(maxWidth: .infinity).brassButton(prominent: true) }
                    .buttonStyle(.plain).accessibilityIdentifier("omok.back")
            }
            .paperCard(padding: 14).padding(.horizontal, 16)
        } else {
            Button {
                guard let move = preview else { return }
                Task {
                    if await match.play(move) {
                        SoundPlayer.shared.play(SoundSynth.stamp(), key: "stamp")
                        Haptics.shared.play(.impactRigid)
                    }
                }
            } label: {
                Text(preview == nil ? "교차점을 탭해 자리를 고른다" : "놓기").frame(maxWidth: .infinity)
                    .brassButton(prominent: preview != nil)
            }
            .buttonStyle(.plain)
            .disabled(preview == nil || !match.isLocalTurn)
            .accessibilityIdentifier("omok.place")
            .padding(.horizontal, 16)
        }
    }

    private func resultText(_ outcome: Outcome) -> String {
        switch outcome {
        case .draw: "무승부"
        case .win(let seat):
            if match.mode.isOnline { match.localSeat == seat ? "승리!" : "패배" } else { "\(seatNames[seat]) 승리" }
        }
    }

    /// 상대 수를 잠깐 크게 그렸다 돌려놓는다. 이 함수가 끝난 뒤에야 로그에 더해진다.
    private func replayRemote(_ move: Omok.Move) async {
        withAnimation(.easeOut(duration: 0.25)) { animating = move }
        SoundPlayer.shared.play(SoundSynth.stamp(), key: "stamp")
        try? await Task.sleep(for: .milliseconds(250))
        animating = nil
    }

    private func showBanner(_ text: String) {
        withAnimation(.spring(duration: 0.3)) { turnBanner = text }
        Task { try? await Task.sleep(for: .seconds(1.2)); withAnimation(.easeOut(duration: 0.3)) { if turnBanner == text { turnBanner = nil } } }
    }

    private func showToast(_ text: String) {
        withAnimation { moveToast = text }
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { if moveToast == text { moveToast = nil } } }
    }
}
