import SwiftUI
import GameCore

/// 컵퐁 한 판. 아래에서 위로 끌어 공을 던지고, 넣으면 컵이 사라지며 한 번 더 던진다 —
/// 로컬 2인은 한 기기에서 좌석이 번갈아 넘어간다.
struct CupPongScreen: View {
    let match: OnlineMatch<CupPong>
    var onReturn: () -> Void = {}
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    /// 끌기가 시작된 시각. 제스처가 준 시각을 그대로 쓰므로 조준선과 손을 뗄 때의 셈이 같다.
    @State private var dragStart: Date?
    @State private var aim: CupPong.Landing?
    @State private var ball: (x: Int, y: Int, height: CGFloat)?
    @State private var vanishing: Int?
    @State private var isThrowing = false
    @State private var turnBanner: String?
    @State private var toast: String?
    /// 채널이 3초 넘게 끊겨 있을 때만 띠를 보인다. 짧은 재접속은 조용히 지나간다.
    @State private var showDisconnected = false
    @State private var disconnectTask: Task<Void, Never>?

    private var seatNames: [String] { match.participants.map(\.displayName) }
    /// 던지는 사람의 시점: 먼 쪽 컵은 상대의 컵이다.
    private var shooter: Int { CupPong.currentSeat(match.state) ?? (match.localSeat ?? 0) }
    private var targetCups: [Bool] { match.state.cups[1 - shooter] }
    private var mySeat: Int { match.mode.isOnline ? (match.localSeat ?? 0) : shooter }
    /// 날아가는 공이 없고 내 차례면 던지는 자리에 공을 얹어 둔다 — 끌라고 한 그 공이 보여야 한다.
    private var displayedBall: (x: Int, y: Int, height: CGFloat)? {
        ball ?? (match.isLocalTurn && !isThrowing ? (x: 0, y: 0, height: 0) : nil)
    }

    var body: some View {
        // 세기는 화면 높이로 잰다(테이블 칸 높이가 아니다). 200~280pt쯤 끌면 컵 자리에 떨어진다.
        GeometryReader { screen in
            ZStack {
                WoodBackground()
                VStack(spacing: 10) {
                    header
                    seats
                    GeometryReader { _ in
                        CupPongTableView(cups: targetCups, aim: aim, ball: displayedBall, vanishing: vanishing)
                            .gesture(dragGesture(height: screen.size.height))
                    }
                    .padding(.horizontal, 8)
                    actionBar
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
                    if let toast { ScoreToast(text: toast).padding(.top, 118).transition(.move(edge: .top).combined(with: .opacity)) }
                }
            }
            // 훅이 match를 강하게 담으면 match → onRemoteMove → match 고리가 되어, 판을 떠나도 세션이 살아남는다.
            .task { [weak match, ball = $ball, vanishing = $vanishing] in
                guard let match else { return }
                match.onRemoteMove = { [weak match] shot, _ in
                    guard let match else { return }
                    await Self.animate(shot: shot, against: match.state.cups[1 - (CupPong.currentSeat(match.state) ?? 0)],
                                       ball: ball, vanishing: vanishing)
                }
            }
            .onDisappear { match.onRemoteMove = nil }
            .onChange(of: match.log.moves.count, initial: true) { _, _ in
                guard match.outcome == nil, let seat = CupPong.currentSeat(match.state) else { return }
                if let last = match.state.lastShot, last.cup != nil {
                    // 넣은 사람이 한 번 더 던진다. 온라인에서 상대가 넣었으면 내가 "한 번 더!"를 들을 일이 아니다.
                    showBanner(!match.mode.isOnline || match.isLocalTurn ? "한 번 더!" : "\(seatNames[seat]) 한 번 더")
                } else {
                    // 로컬 2인은 두 좌석 다 내 것이라 "내 차례"가 아무것도 알려주지 않는다. 이름을 부른다.
                    showBanner(match.mode.isOnline && match.isLocalTurn ? "내 차례" : "\(seatNames[seat]) 차례")
                }
            }
            .onChange(of: match.lastRemoteMove?.id) { _, _ in
                guard let remote = match.lastRemoteMove, let last = match.state.lastShot else { return }
                showToast(last.cup == nil ? "\(seatNames[remote.seat]): 빗나감" : "\(seatNames[remote.seat]): 컵 하나!")
            }
            .onChange(of: match.isConnected, initial: true) { _, connected in
                disconnectTask?.cancel()
                if connected { withAnimation { showDisconnected = false } }
                else { disconnectTask = Task { try? await Task.sleep(for: .seconds(3)); guard !Task.isCancelled else { return }; withAnimation { showDisconnected = true } } }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await match.resync() } } }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onReturn) { Image(systemName: "chevron.left").foregroundStyle(theme.ivory) }
                .accessibilityIdentifier("header.menu").accessibilityLabel("메뉴로")
            Spacer()
            VStack(spacing: 2) {
                Text("컵퐁").font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
                Text("내 컵 \(match.state.remaining(seat: mySeat)) · 상대 컵 \(match.state.remaining(seat: 1 - mySeat))")
                    .font(.caption).monospacedDigit().foregroundStyle(theme.brass).accessibilityIdentifier("header.status")
            }
            Spacer()
            Text(CupPong.currentSeat(match.state).map { "\(seatNames[$0]) 차례" } ?? "끝")
                .font(.caption).foregroundStyle(theme.ivory).accessibilityIdentifier("header.turn")
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    /// 명패 둘. 현재 차례는 황동, 원격 상대는 접속 점. 숫자는 그 좌석에 남은 컵이다.
    private var seats: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { seat in
                let current = CupPong.currentSeat(match.state) == seat
                HStack(spacing: 6) {
                    if case .remote = match.participants[seat] {
                        Circle().fill(match.opponentPresent ? Color.green : theme.inkSecondary.opacity(0.5)).frame(width: 7, height: 7)
                            .accessibilityIdentifier("players.presence.\(seat)")
                    }
                    Text(seatNames[seat]).font(.caption).lineLimit(1)
                    Text("\(match.state.remaining(seat: seat))").font(.caption.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(current ? theme.brassInk : theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(current ? theme.brass : theme.paper))
                .accessibilityIdentifier("players.seat.\(seat)")
                .accessibilityLabel("\(seatNames[seat]), 컵 \(match.state.remaining(seat: seat))개\(current ? ", 현재 차례" : "")")
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var actionBar: some View {
        if let outcome = match.outcome {
            VStack(spacing: 10) {
                Text(resultText(outcome)).font(.system(.title2, design: .serif, weight: .semibold)).foregroundStyle(theme.ink)
                    .accessibilityIdentifier("cuppong.result")
                Button(action: onReturn) { Label("메뉴로", systemImage: "chevron.left").frame(maxWidth: .infinity).brassButton(prominent: true) }
                    .buttonStyle(.plain).accessibilityIdentifier("cuppong.back")
            }
            .paperCard(padding: 14).padding(.horizontal, 16)
        } else {
            Text(match.isLocalTurn ? "공을 위로 끌어 던진다" : "\(seatNames[CupPong.currentSeat(match.state) ?? 0])의 차례를 기다린다")
                .font(.caption).foregroundStyle(theme.ivory).padding(.bottom, 8)
        }
    }

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard match.isLocalTurn, !isThrowing else { return }
                let start = dragStart ?? value.time
                if dragStart == nil { dragStart = start }
                let dx = value.location.x - value.startLocation.x, dy = value.startLocation.y - value.location.y
                if let shot = CupPongGeometry.shot(dx: dx, dy: dy, duration: value.time.timeIntervalSince(start), screenHeight: height) {
                    aim = CupPong.landing(of: shot, against: targetCups)
                } else {
                    aim = nil
                }
            }
            .onEnded { value in
                defer { dragStart = nil; aim = nil }
                guard match.isLocalTurn, !isThrowing, let start = dragStart else { return }
                let dx = value.location.x - value.startLocation.x, dy = value.startLocation.y - value.location.y
                guard let shot = CupPongGeometry.shot(dx: dx, dy: dy, duration: value.time.timeIntervalSince(start), screenHeight: height) else { return }
                // 잠금은 Task를 만들기 전에 건다. 그 사이에 두 번째 끌기가 들어오면 공이 둘이 된다.
                isThrowing = true
                Task {
                    await Self.animate(shot: shot, against: targetCups, ball: $ball, vanishing: $vanishing)
                    let played = await match.play(shot)
                    if !played { showToast("지금은 던질 수 없다") }
                    isThrowing = false
                }
            }
    }

    private func resultText(_ outcome: Outcome) -> String {
        guard case .win(let seat) = outcome else { return "무승부" }
        if match.mode.isOnline { return match.localSeat == seat ? "승리!" : "패배" }
        return "\(seatNames[seat]) 승리"
    }

    /// 공을 0.9초 날리고, 맞혔으면 컵이 옅어지며 사라진다. 내 던지기와 상대 재생이 같은 길을 쓴다.
    ///
    /// 화면 상태 바인딩만 받는 정적 함수다. 훅이 뷰 값을 담으면 그 안의 `match`까지 함께 잡힌다.
    @MainActor
    private static func animate(shot: CupPong.Shot, against cups: [Bool],
                                ball: Binding<(x: Int, y: Int, height: CGFloat)?>, vanishing: Binding<Int?>) async {
        let landing = CupPong.landing(of: shot, against: cups)
        let frames = 27
        for f in 0...frames {
            ball.wrappedValue = CupPongGeometry.ballPath(to: landing, progress: CGFloat(f) / CGFloat(frames))
            try? await Task.sleep(for: .milliseconds(33))
        }
        ball.wrappedValue = nil
        if let cup = landing.cup {
            SoundPlayer.shared.play(SoundSynth.pong(), key: "pong")
            Haptics.shared.play(.success)
            vanishing.wrappedValue = cup
            try? await Task.sleep(for: .milliseconds(350))
            vanishing.wrappedValue = nil
        } else {
            Haptics.shared.play(.impactLight)
        }
    }

    private func showBanner(_ text: String) {
        withAnimation(.spring(duration: 0.3)) { turnBanner = text }
        Task { try? await Task.sleep(for: .seconds(1.2)); withAnimation(.easeOut(duration: 0.3)) { if turnBanner == text { turnBanner = nil } } }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { if toast == text { toast = nil } } }
    }
}
