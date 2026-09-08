import Foundation
import GameKit
import YachtCore

/// `GKTurnBasedMatch` 하나를 `TurnTransport`로 감싼다. 매치 데이터는 `MatchLog` JSON이다.
final class GameCenterTurnTransport: TurnTransport, @unchecked Sendable {
    private let match: GKTurnBasedMatch
    let incomingLogs: AsyncStream<MatchLog>

    @MainActor
    init(match: GKTurnBasedMatch, service: GameCenterService) {
        self.match = match
        incomingLogs = service.stream(for: match.matchID)
    }

    /// 차례를 넘기지 않고 매치 데이터만 갱신한다. 상대가 열어 두었으면 턴 이벤트로 받는다.
    func publishProgress(log: MatchLog) async throws {
        try await match.saveCurrentTurn(withMatch: try log.encoded())
    }

    func endTurn(log: MatchLog) async throws {
        let data = try log.encoded()
        // GKTurnTimeoutDefault(1주)와 같은 값. 전역 var라 strict concurrency에서 직접 못 읽는다.
        let oneWeek: TimeInterval = 60 * 60 * 24 * 7
        try await match.endTurn(withNextParticipants: nextParticipants(),
                                turnTimeout: oneWeek, match: data)
    }

    func endMatch(log: MatchLog, totals: [Int]) async throws {
        let data = try log.encoded()
        let best = totals.max() ?? 0
        let winners = totals.filter { $0 == best }.count
        for (index, participant) in match.participants.enumerated() where index < totals.count {
            participant.matchOutcome = totals[index] < best ? .lost : (winners > 1 ? .tied : .won)
        }
        try await match.endMatchInTurn(withMatch: data)
    }

    /// 나 다음 좌석부터 한 바퀴. Game Center는 이 순서로 다음 차례를 준다.
    private func nextParticipants() -> [GKTurnBasedParticipant] {
        let participants = match.participants
        let localID = GKLocalPlayer.local.gamePlayerID
        guard let me = participants.firstIndex(where: { $0.player?.gamePlayerID == localID }) else {
            return participants
        }
        return Array(participants[(me + 1)...]) + Array(participants[..<me])
    }
}
