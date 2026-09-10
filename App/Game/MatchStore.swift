import Foundation
import YachtCore

/// 진행 중인 판을 파일 하나로 보관한다.
/// 이벤트 소싱이라 저장할 것이 로그와 "누구와 어떤 모드로"뿐이고, 복원은 리플레이다.
struct MatchStore: Sendable {
    private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appending(path: "match.json")
    }

    static var `default`: MatchStore {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return MatchStore(directory: directory)
    }

    /// 끝난 게임은 저장하지 않는다. 복원했을 때 결과 화면에 갇히기 때문이다.
    func save(_ record: MatchRecord) throws {
        guard !record.isFinished else {
            try clear()
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: fileURL, options: .atomic)
    }

    /// 읽기 실패는 오류로 올리지 않는다. 저장 파일 하나 때문에 앱이 시작조차
    /// 못 하는 것보다, 새 판으로 시작하는 편이 낫다. 그래서 throws가 아니다.
    ///
    /// v1 파일(`MatchLog`만 있던 형식)은 혼자 연습으로 읽는다.
    func load() -> MatchRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return nil }

        if let record = try? JSONDecoder().decode(MatchRecord.self, from: data) {
            guard (2...MatchRecord.formatVersion).contains(record.formatVersion) else { return nil }
            if !record.isYacht {
                return record.moveLog == nil ? nil : record
            }
            guard record.participants.count == record.log.playerCount,
                  // 로그는 신뢰 경계다. 디코더가 아니라 canApply로 끝까지 재생해 본다.
                  let encoded = try? record.log.encoded(),
                  let log = try? MatchLog.decoded(from: encoded),
                  !log.isFinished
            else { return nil }
            return MatchRecord(mode: record.mode, participants: record.participants, log: log)
        }

        guard let log = try? MatchLog.decoded(from: data), !log.isFinished, log.playerCount == 1 else { return nil }
        return MatchRecord(mode: .solo, participants: GameMode.solo.participants, log: log)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
