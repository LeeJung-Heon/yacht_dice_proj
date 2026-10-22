import SwiftUI
import GameCore

/// 컵퐁 한 판. 아래에서 위로 끌어 공을 던지고, 넣으면 컵이 사라지며 한 번 더 던진다 —
/// 로컬 2인은 한 기기에서 좌석이 번갈아 넘어간다.
struct CupPongScreen: View {
    let match: OnlineMatch<CupPong>
    let service: SupabaseService
    @State private var opponentDesign = CupPongCustomizationStore()
    @State private var photoSyncMessage: String?
    var onReturn: () -> Void = {}
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    /// 직전에 받은 끌기 표본. 속도는 이 표본과 새 표본 사이에서만 재므로 손을 멈춘 채 끌면 세기가 붙지 않는다.
    @State private var lastSample: (location: CGPoint, time: Date)?
    /// 마지막 구간에서 잰 초당 이동 거리. 놓을 때 던지는 힘에 반영한다.
    @State private var lastSpeed: CGFloat = 0
    @State private var ball: (x: Int, y: Int, height: CGFloat)?
    @State private var vanishing: Int?
    @State private var isThrowing = false
    @State private var throwTask: Task<Void, Never>?
    /// 컵퐁의 순간 상태. 손가락이 공에 닿아 있는 동안만 참이다.
    struct Live: Codable, Equatable { let aiming: Bool }
    /// 던지기 직전의 시점·컵·남은 컵 수. 수는 놓는 순간 판에 들어가지만, 공이 닿기 전에 컵이 사라지거나
    /// 차례가 넘어가 시점이 뒤집히면 안 되므로 연출이 끝날 때까지 화면은 이 값을 그린다.
    struct ThrowFreeze {
        let shooter: Int
        let cups: [Bool]
        let remaining: [Int]
    }
    @State private var frozen: ThrowFreeze?
    @State private var turnBanner: String?
    @State private var toast: String?
    /// 채널이 3초 넘게 끊겨 있을 때만 띠를 보인다. 짧은 재접속은 조용히 지나간다.
    @State private var showDisconnected = false
    @State private var disconnectTask: Task<Void, Never>?

    private var seatNames: [String] { match.participants.map(\.displayName) }
    /// 던지는 사람의 시점: 먼 쪽 컵은 지금 노리는 컵이다.
    /// 판이 끝나면 차례가 없으므로 이긴 좌석을 시점으로 삼아 결과 카드 위에 비워진 삼각형이 남게 한다.
    private var shooter: Int {
        if let frozen { return frozen.shooter }
        if let seat = CupPong.currentSeat(match.state) { return seat }
        if case .win(let seat)? = match.outcome { return seat }
        return match.localSeat ?? 0
    }
    private var targetCups: [Bool] { frozen?.cups ?? match.state.cups[1 - shooter] }
    /// 화면에 보일 남은 컵 수. 공이 나는 동안에는 던지기 직전의 수다.
    private func remaining(_ seat: Int) -> Int { frozen?.remaining[seat] ?? match.state.remaining(seat: seat) }
    /// 화면에 보일 차례. 공이 나는 동안에는 던진 좌석이다.
    private var displayedTurn: Int? { frozen?.shooter ?? CupPong.currentSeat(match.state) }
    /// 상대가 지금 공을 잡고 조준하는가.
    private var remoteAiming: Bool {
        match.mode.isOnline && !match.isLocalTurn && frozen == nil && match.remoteLive(as: Live.self)?.aiming == true
    }
    private var mySeat: Int { match.mode.isOnline ? (match.localSeat ?? 0) : shooter }
    /// 먼 쪽 삼각형의 주인. 온라인에서 상대가 던지는 동안에는 저 컵이 내 것이다.
    private var targetOwner: String { 1 - shooter == mySeat ? "내 컵" : "상대 컵" }
    /// 날아가는 공이 없고 내 차례면 던지는 자리에 공을 얹어 둔다 — 끌라고 한 그 공이 보여야 한다.
    /// 상대가 조준하는 동안에도 상대가 보고 있는 그 자리에 공을 얹는다.
    private var displayedBall: (x: Int, y: Int, height: CGFloat)? {
        ball ?? ((match.isLocalTurn && !isThrowing) || remoteAiming ? (x: 0, y: 0, height: 400) : nil)
    }

    // 이모지 키보드가 열려도 판이 줄어들지 않는다 — 판 크기는 던지는 힘(컵퐁)과 터치 좌표가 기대는 값이다.
    var body: some View { layout.ignoresSafeArea(.keyboard) }

    private var layout: some View {
        // 세기는 화면 높이로 잰다(테이블 칸 높이가 아니다). 손을 멈춘 채 200~280pt쯤 끌면 컵 자리에 떨어진다.
        GeometryReader { screen in
            ZStack {
                theme.cupPongBackdrop.ignoresSafeArea()
                VStack(spacing: 10) {
                    header
                    seats
                    if match.mode.isOnline, !match.isLocalTurn, match.outcome == nil, frozen == nil {
                        // 상대 차례에는 먼 쪽 삼각형이 내 컵이라, 무엇을 보고 있는지 한 줄로 알린다.
                        Text("상대가 내 컵 \(remaining(mySeat))개를 노린다")
                            .font(.caption).foregroundStyle(theme.brass).accessibilityIdentifier("cuppong.owner")
                    }
                    CupPongTableView(cups: targetCups, owner: targetOwner, ball: displayedBall, vanishing: vanishing,
                                     customization: match.mode.isOnline && 1 - shooter != mySeat ? opponentDesign : .shared)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(dragGesture(height: screen.size.height))
                        .overlay { if let reactions = match.reactions { ReactionOverlay(board: reactions) } }
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .padding(.horizontal, 8)
                    if let photoSyncMessage {
                        Text(photoSyncMessage).font(.caption2).foregroundStyle(theme.ivory).padding(.horizontal, 16)
                    }
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
                    _ = await Self.animate(shot: shot, against: match.state.cups[1 - (CupPong.currentSeat(match.state) ?? 0)],
                                           ball: ball, vanishing: vanishing)
                    // 훅이 돌아오자마자 로그에 수가 붙어 컵이 지워지므로, 옅어진 컵은 여기서 거둔다.
                    vanishing.wrappedValue = nil
                }
            }
            .task { await syncPhotos() }
            .onDisappear {
                match.onRemoteMove = nil; match.publishLive(Live?.none)
                disconnectTask?.cancel(); throwTask?.cancel(); throwTask = nil
                ball = nil; vanishing = nil; frozen = nil; isThrowing = false
            }
            .onChange(of: match.log.moves.count, initial: true) { _, _ in
                // 내 던지기는 놓는 순간 판에 들어간다 — 배너는 공이 닿은 뒤에 던지기 Task가 띄운다.
                guard !isThrowing else { return }
                announceTurn()
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await match.resync() } }
                // 공을 잡은 채 앱을 떠나도 상대 화면에 "조준 중"이 남지 않게 거둔다.
                else { match.publishLive(Live?.none) }
            }
        }
    }

    /// 지금 차례를 배너로 알린다. 판이 끝났으면 알릴 차례가 없다.
    private func announceTurn() {
        guard match.outcome == nil, let seat = CupPong.currentSeat(match.state) else { return }
        if let last = match.state.lastShot, last.cup != nil {
            // 넣은 사람이 한 번 더 던진다. 온라인에서 상대가 넣었으면 내가 "한 번 더!"를 들을 일이 아니다.
            showBanner(!match.mode.isOnline || match.isLocalTurn ? "한 번 더!" : "\(seatNames[seat]) 한 번 더")
        } else {
            // 로컬 2인은 두 좌석 다 내 것이라 "내 차례"가 아무것도 알려주지 않는다. 이름을 부른다.
            showBanner(match.mode.isOnline && match.isLocalTurn ? "내 차례" : "\(seatNames[seat]) 차례")
        }
    }

    /// 상대의 사진 버전만 주기적으로 확인하고 바뀐 경우에만 이미지를 받는다.
    private func syncPhotos() async {
        guard case .online(let id) = match.mode, let matchID = UUID(uuidString: id) else { return }
        let photos = CupPongPhotoService(service: service)
        var lastRevision: UUID?
        var published = false
        while !Task.isCancelled {
            do {
                if !published { try await photos.publish(.shared); published = true }
                let row = try await service.fetchMatch(id: matchID)
                let owner = match.localSeat == 0 ? row.guestUid : row.hostUid
                if let owner {
                    let revision = try await photos.revision(owner: owner)
                    if revision != lastRevision {
                        if let design = try await photos.fetch(owner: owner) {
                            let loaded = try photos.load(design)
                            try Task.checkCancellation()
                            opponentDesign = loaded
                            lastRevision = design.revision
                        } else {
                            opponentDesign = CupPongCustomizationStore()
                            lastRevision = nil
                        }
                    }
                }
                photoSyncMessage = nil
            } catch is CancellationError { return }
            catch { photoSyncMessage = "컵 사진을 동기화하지 못했습니다. 다시 연결하는 중…" }
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onReturn) { Image(systemName: "chevron.left").foregroundStyle(theme.ivory) }
                .accessibilityIdentifier("header.menu").accessibilityLabel("메뉴로")
            Spacer()
            VStack(spacing: 2) {
                Text("컵퐁").font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
                Text("내 컵 \(remaining(mySeat)) · 상대 컵 \(remaining(1 - mySeat))")
                    .font(.caption).monospacedDigit().foregroundStyle(theme.brass).accessibilityIdentifier("header.status")
            }
            Spacer()
            Text(displayedTurn.map { "\(seatNames[$0]) 차례" } ?? "끝")
                .font(.caption).foregroundStyle(theme.ivory).lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityIdentifier("header.turn")
            if let reactions = match.reactions {
                ReactionButton(canSend: reactions.canSend) { match.sendReaction($0) }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    /// 명패 둘. 현재 차례는 황동, 원격 상대는 접속 점. 숫자는 그 좌석에 남은 컵이다.
    private var seats: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { seat in
                let current = displayedTurn == seat
                HStack(spacing: 6) {
                    if case .remote = match.participants[seat] {
                        Circle().fill(match.opponentPresent ? Color.green : theme.inkSecondary.opacity(0.5)).frame(width: 7, height: 7)
                            .accessibilityIdentifier("players.presence.\(seat)")
                    }
                    Text(seatNames[seat]).font(.caption).lineLimit(1)
                    Text("\(remaining(seat))").font(.caption.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(current ? theme.brassInk : theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(current ? theme.brass : theme.paper))
                .accessibilityIdentifier("players.seat.\(seat)")
                .accessibilityLabel("\(seatNames[seat]), 컵 \(remaining(seat))개\(current ? ", 현재 차례" : "")")
                .reactionBadge(match.reactions?.badge(for: seat)?.emoji, seat: seat)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var actionBar: some View {
        // 결과 카드는 마지막 공이 닿은 뒤에 올린다.
        if let outcome = match.outcome, frozen == nil {
            VStack(spacing: 10) {
                Text(resultText(outcome)).font(.system(.title2, design: .serif, weight: .semibold)).foregroundStyle(theme.ink)
                    .accessibilityIdentifier("cuppong.result")
                Button(action: onReturn) { Label("메뉴로", systemImage: "chevron.left").frame(maxWidth: .infinity).brassButton(prominent: true) }
                    .buttonStyle(.plain).accessibilityIdentifier("cuppong.back")
            }
            .paperCard(padding: 14).padding(.horizontal, 16)
        } else if remoteAiming {
            Text("상대가 조준 중").font(.caption).foregroundStyle(theme.ivory).padding(.bottom, 8)
                .accessibilityIdentifier("cuppong.remoteAiming")
        } else {
            Text(match.isLocalTurn || frozen != nil ? "공을 위로 끌어 던진다" : "\(seatNames[CupPong.currentSeat(match.state) ?? 0])의 차례를 기다린다")
                .font(.caption).foregroundStyle(theme.ivory).padding(.bottom, 8)
        }
    }

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard match.isLocalTurn, !isThrowing else { return }
                if lastSample == nil { match.publishLive(Live(aiming: true)) }
                if let previous = lastSample {
                    // 시간 간격은 1/120초에서 막는다. 같은 순간에 표본이 둘 오면 속도가 무한이 된다.
                    let dt = max(value.time.timeIntervalSince(previous.time), 1.0 / 120)
                    let mx = value.location.x - previous.location.x, my = value.location.y - previous.location.y
                    let moved = (mx * mx + my * my).squareRoot()
                    lastSpeed = moved / CGFloat(dt)
                }
                lastSample = (value.location, value.time)
            }
            .onEnded { value in
                // 마지막 입력 표본의 속도를 사용한다. 놓기 전에는 착지점을 계산하거나 표시하지 않는다.
                let speed = lastSpeed
                defer { lastSample = nil; lastSpeed = 0 }
                match.publishLive(Live?.none)
                guard match.isLocalTurn, !isThrowing else { return }
                let dx = value.location.x - value.startLocation.x, dy = value.startLocation.y - value.location.y
                guard let shot = CupPongGeometry.shot(dx: dx, dy: dy, speed: speed, screenHeight: height) else { return }
                // 잠금은 Task를 만들기 전에 건다. 그 사이에 두 번째 끌기가 들어오면 공이 둘이 된다.
                isThrowing = true
                let cups = targetCups
                // 수는 놓는 순간 올린다 — 상대 화면이 같은 공을 거의 함께 날리기 시작한다. 내 화면은 닿을 때까지 묶어 둔다.
                frozen = ThrowFreeze(shooter: shooter, cups: cups, remaining: [remaining(0), remaining(1)])
                throwTask = Task {
                    defer { isThrowing = false; throwTask = nil }
                    await CupPongThrow.run(
                        play: { await match.play(shot) },
                        animate: { _ = await Self.animate(shot: shot, against: cups, ball: $ball, vanishing: $vanishing) },
                        landed: {
                            // 옅어진 컵과 묶음을 함께 거둔다. 따로 거두면 한 프레임 동안 컵이 되살아난다.
                            vanishing = nil
                            frozen = nil
                            announceTurn()
                        },
                        rejected: { showToast("지금은 던질 수 없다") })
                }
            }
    }

    private func resultText(_ outcome: Outcome) -> String {
        guard case .win(let seat) = outcome else { return "무승부" }
        if match.mode.isOnline { return match.localSeat == seat ? "승리!" : "패배" }
        return "\(seatNames[seat]) 승리"
    }

    /// 판정과 같은 경로를 실제 시간으로 재생한다. 기기 프레임률이 달라도 충돌 순간과 종료 시각이 같다.
    @MainActor
    private static func animate(shot: CupPong.Shot, against cups: [Bool],
                                ball: Binding<(x: Int, y: Int, height: CGFloat)?>, vanishing: Binding<Int?>) async -> CupPong.Landing {
        let simulation = CupPong.simulate(shot, against: cups)
        let duration = Double(simulation.steps) / Double(CupPong.stepsPerSecond)
        let clock = ContinuousClock()
        let start = clock.now
        var eventIndex = 0
        var lastContactStep = -100
        defer { ball.wrappedValue = nil }
        while !Task.isCancelled {
            let elapsed = start.duration(to: clock.now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            ball.wrappedValue = CupPongGeometry.ballFrame(in: simulation.frames, at: seconds)
            let step = Int(seconds * Double(CupPong.stepsPerSecond))
            while eventIndex < simulation.events.count && simulation.events[eventIndex].step <= step {
                let event = simulation.events[eventIndex]
                switch event.kind {
                case .sunk:
                    SoundPlayer.shared.play(SoundSynth.pong(), key: "pong")
                    Haptics.shared.play(.success)
                case .tableBounce, .rim, .cupWall:
                    // 밀집 접촉에서도 한 번의 충돌이 소리 여러 개로 겹치지 않게 한다.
                    if event.step - lastContactStep >= 14 {
                        SoundPlayer.shared.play(event.kind == .tableBounce ? SoundSynth.tick() : SoundSynth.clack(), key: "cupContact")
                        Haptics.shared.play(.impactLight)
                        lastContactStep = event.step
                    }
                case .leftTable: break
                }
                eventIndex += 1
            }
            if seconds >= duration { break }
            do { try await Task.sleep(for: .milliseconds(8)) } catch { return simulation.landing }
        }
        guard !Task.isCancelled else { return simulation.landing }
        if let cup = simulation.landing.cup {
            vanishing.wrappedValue = cup
            try? await Task.sleep(for: .milliseconds(180))
        }
        return simulation.landing
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
