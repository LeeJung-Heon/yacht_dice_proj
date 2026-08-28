import Foundation
import YachtCore

/// 진행 중인 판을 파일 하나로 보관한다.
/// 이벤트 소싱이라 저장할 것이 로그뿐이고, 복원은 리플레이다.
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
    func save(_ log: MatchLog) throws {
        guard !log.isFinished else {
            try clear()
            return
        }
        try log.encoded().write(to: fileURL, options: .atomic)
    }

    /// 읽기 실패는 오류로 올리지 않는다. 저장 파일 하나 때문에 앱이 시작조차
    /// 못 하는 것보다, 새 판으로 시작하는 편이 낫다.
    func load() throws -> MatchLog? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL),
              let log = try? MatchLog.decoded(from: data),
              !log.isFinished
        else { return nil }
        return log
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
