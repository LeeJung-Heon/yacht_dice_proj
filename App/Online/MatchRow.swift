import Foundation
import YachtCore

/// `public.matches` 행. 서버 스키마와 1:1이다.
struct MatchRow: Codable, Equatable, Sendable {
    var id: UUID
    var code: String
    var hostUid: UUID
    var guestUid: UUID?
    var hostName: String
    var guestName: String?
    var log: MatchLog
    var eventCount: Int
    var status: String
    var totals: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, code, log, status, totals
        case hostUid = "host_uid", guestUid = "guest_uid"
        case hostName = "host_name", guestName = "guest_name"
        case eventCount = "event_count"
    }

    var isWaiting: Bool { status == "waiting" }
    var isFinished: Bool { status == "finished" }

    /// 좌석은 항상 [호스트, 게스트]. 내 uid가 어느 쪽인지로 human/remote를 정한다.
    func seats(localUid: UUID) -> [SeatPlayer] {
        [SeatPlayer(id: hostUid.uuidString, name: hostName),
         SeatPlayer(id: guestUid?.uuidString, name: guestName)]
    }

    /// 앱이 열 기록. 게스트가 없는 대기 방은 아직 열 수 없다.
    func record(localUid: UUID) -> MatchRecord? {
        guard guestUid != nil else { return nil }
        let participants = seatParticipants(localID: localUid.uuidString, players: seats(localUid: localUid))
        guard participants.contains(where: \.isHuman), log.playerCount == 2 else { return nil }
        return MatchRecord(mode: .online(matchID: id.uuidString), participants: participants, log: log)
    }

    /// 6자리 숫자 방 코드.
    static func makeCode(using generator: inout some RandomNumberGenerator) -> String {
        String(format: "%06d", Int.random(in: 0...999_999, using: &generator))
    }

    static func isValidCode(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy(\.isNumber)
    }
}
