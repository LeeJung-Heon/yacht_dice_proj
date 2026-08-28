import Testing
import Foundation
import YachtCore
@testable import YachtDice

@Suite("진행 저장")
struct MatchStoreTests {

    private func makeTempStore() throws -> (MatchStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "yacht-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (MatchStore(directory: directory), directory)
    }

    @Test("저장한 로그를 그대로 읽는다")
    func 왕복() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var log = MatchLog(playerCount: 1)
        log.append(.rolled([6, 6, 6, 6, 6]))
        log.append(.committed(.yacht, 50))
        try store.save(log)

        let loaded = try #require(store.load())
        #expect(loaded == log)
        #expect(loaded.state.scorecards[0].entry(.yacht) == 50)
    }

    @Test("저장한 적이 없으면 nil이다")
    func 없음() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.load() == nil)
    }

    @Test("clear하면 사라진다")
    func 삭제() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var log = MatchLog(playerCount: 1)
        log.append(.rolled([1, 1, 1, 1, 1]))
        try store.save(log)
        try store.clear()
        #expect(store.load() == nil)
    }

    @Test("깨진 파일은 nil로 처리하고 앱을 막지 않는다")
    func 손상된_파일() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("이건 JSON이 아니다".utf8).write(to: directory.appending(path: "match.json"))
        #expect(store.load() == nil, "깨진 저장 파일 때문에 앱이 시작되지 못하면 안 된다")
    }

    @Test("끝난 게임은 저장하지 않는다")
    func 완결된_게임() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var log = MatchLog(playerCount: 1)
        for category in ScoreCategory.allCases {
            log.append(.rolled([1, 1, 1, 1, 1]))
            log.append(.committed(category, 0))
            log.append(.turnAdvanced)
        }
        log.append(.gameEnded)
        try store.save(log)
        #expect(store.load() == nil, "끝난 게임을 복원하면 결과 화면에 갇힌다")
    }
}
