import Foundation
import Observation

/// 게임 중 이모지 반응의 판정·빈도·표시 상태. 요트의 `GameSession`과 나머지 게임의 `OnlineMatch`가 온라인일 때만 하나씩 들고,
/// 화면은 떠오르는 반응과 명패 배지를 여기서 읽는다. 반응은 저장하지 않으며 놓쳐도 판에 영향이 없다.
@MainActor
@Observable
final class ReactionBoard {
    struct Burst: Identifiable, Equatable {
        let id: UUID
        let emoji: String
        let seat: Int
    }

    /// 명패에 남는 배지. 보낸 순간의 수를 들어, 그 수 뒤에 차례가 바뀌면 사라진다.
    struct Badge: Equatable {
        let emoji: String
        let eventCount: Int
    }

    /// 이보다 긴 글자는 이모지 하나로 보지 않는다. 가장 긴 가족 조합도 이 안에 든다.
    static let maxBytes = 64

    let localSeat: Int
    let remoteSeat: Int
    /// 상대의 표시 이름. VoiceOver 알림에 쓴다.
    let remoteName: String
    /// 지금 떠오르는 반응. 정한 시간이 지나면 빠진다.
    private(set) var bursts: [Burst] = []
    /// 좌석별 배지.
    private(set) var badges: [Int: Badge] = [:]
    /// 마지막으로 보낸 뒤 간격이 지났는가. 화면은 거짓이면 단추를 잠근다.
    private(set) var canSend = true

    private let transport: any TurnTransport
    private let cooldown: Duration
    private let burstDuration: Duration
    private var listenTask: Task<Void, Never>?
    /// 같은 사람이 간격 안에 보낸 둘째를 거르려고 좌석별로 마지막으로 받은 때를 든다.
    private var lastReceived: [Int: ContinuousClock.Instant] = [:]
    private var hasNotedTurn = false
    private var currentTurn: Int?
    /// 마지막으로 차례가 바뀐 수. 이보다 앞선 수에서 보낸 배지는 이미 지난 차례의 것이다.
    private var turnChangedAt = Int.min

    init(localSeat: Int, remoteSeat: Int, remoteName: String, transport: any TurnTransport,
         cooldown: Duration = .seconds(1), burstDuration: Duration = .seconds(2)) {
        self.localSeat = localSeat
        self.remoteSeat = remoteSeat
        self.remoteName = remoteName
        self.transport = transport
        self.cooldown = cooldown
        self.burstDuration = burstDuration
    }

    /// 이모지 하나만 참이다. 보내는 쪽과 받는 쪽이 같은 판정을 써서 이 통로로 글자가 오가지 않는다.
    /// 첫 스칼라가 이모지로 그려지는 것이어야 하고(글자 뒤에 피부색이나 결합 부호를 붙인 것은 거짓), 나머지 스칼라도 이모지·연결자·
    /// 이모지 표시 선택자·키캡·태그뿐이어야 한다. 국기는 지역 표시 문자 둘, 키캡은 숫자·#·*로 시작해 키캡으로 끝나야 한다.
    /// 길이는 바이트를 먼저 보아, 크게 꾸민 문자열이 글자 수 세기에 시간을 쓰게 하지 않는다.
    static func isSingleEmoji(_ text: String) -> Bool {
        guard text.utf8.count <= maxBytes, text.count == 1, let character = text.first else { return false }
        let scalars = Array(character.unicodeScalars)
        let first = scalars[0], second = scalars.count > 1 ? scalars[1] : nil
        func isRegional(_ scalar: Unicode.Scalar) -> Bool { (0x1F1E6...0x1F1FF).contains(scalar.value) }
        if isRegional(first) { return scalars.count == 2 && isRegional(scalars[1]) }
        if "0123456789#*".unicodeScalars.contains(first) { return scalars.last == "\u{20E3}" }
        let properties = first.properties
        guard properties.isEmojiPresentation
                || (properties.isEmoji && second == "\u{FE0F}")
                || (properties.isEmojiModifierBase && second?.properties.isEmojiModifier == true) else { return false }
        return scalars.allSatisfy {
            $0.properties.isEmoji || $0 == "\u{200D}" || $0 == "\u{FE0F}" || $0 == "\u{20E3}" || (0xE0020...0xE007F).contains($0.value)
        }
    }

    /// 명패에 그릴 배지. 그 좌석의 반응이 아직 떠오르는 중이면 숨겨, 떠오름이 끝난 뒤에 배지가 남는 순서를 지킨다.
    func badge(for seat: Int) -> Badge? {
        bursts.contains { $0.seat == seat } ? nil : badges[seat]
    }

    /// 판정과 간격을 통과하면 상대에게 보내고 내 좌석으로 띄운다.
    @discardableResult
    func send(_ text: String, eventCount: Int) -> Bool {
        guard canSend, Self.isSingleEmoji(text) else { return false }
        canSend = false
        let cooldown = cooldown
        Task { [weak self] in
            try? await Task.sleep(for: cooldown)
            self?.canSend = true
        }
        show(text, seat: localSeat, eventCount: eventCount)
        let transport = transport, reaction = Reaction(emoji: text, eventCount: eventCount)
        Task { await transport.sendReaction(reaction) }
        return true
    }

    /// 받기 루프를 연다. 세션의 `startListening()`이 부른다.
    func start() {
        guard listenTask == nil else { return }
        let reactions = transport.reactions
        listenTask = Task { [weak self] in
            for await reaction in reactions {
                if Task.isCancelled { return }
                self?.receive(reaction)
            }
        }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
    }

    /// 세션이 로그나 보이는 상태를 바꿀 때마다 지금 차례와 수를 알린다. 차례가 바뀌면 그 수 전에 보낸 배지를 지운다.
    /// 끝난 판은 차례가 nil이라 더 바뀌지 않으므로, 끝난 뒤의 배지는 다음 이모지로만 바뀐다.
    func noteTurn(_ seat: Int?, eventCount: Int) {
        defer { hasNotedTurn = true; currentTurn = seat }
        guard hasNotedTurn else {
            turnChangedAt = eventCount
            return
        }
        guard seat != currentTurn else { return }
        turnChangedAt = eventCount
        badges = badges.filter { $0.value.eventCount >= eventCount }
    }

    private func receive(_ reaction: Reaction) {
        guard Self.isSingleEmoji(reaction.emoji) else { return }
        let now = ContinuousClock.now
        if let last = lastReceived[remoteSeat], now - last < cooldown { return }
        lastReceived[remoteSeat] = now
        show(reaction.emoji, seat: remoteSeat, eventCount: reaction.eventCount)
    }

    private func show(_ emoji: String, seat: Int, eventCount: Int) {
        let burst = Burst(id: UUID(), emoji: emoji, seat: seat)
        bursts.append(burst)
        // 이미 지난 차례에 보낸 것이면 떠오르기만 하고 배지는 남기지 않는다.
        if eventCount >= turnChangedAt { badges[seat] = Badge(emoji: emoji, eventCount: eventCount) }
        let duration = burstDuration
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            self?.bursts.removeAll { $0.id == burst.id }
        }
    }
}
