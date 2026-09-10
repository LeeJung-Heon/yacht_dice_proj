import Testing
import Foundation
import YachtCore
import YachtBot
import GameCore
@testable import YachtDice

@Suite("진행 저장")
struct MatchStoreTests {

    private func makeTempStore() throws -> (MatchStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "yacht-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (MatchStore(directory: directory), directory)
    }

    /// 12턴을 전부 채운 로그.
    private func finishedRecord() -> MatchRecord {
        var record = MatchRecord(mode: .solo)
        for category in ScoreCategory.allCases {
            record.log.append(.rolled([1, 1, 1, 1, 1]))
            let points = category.score([1, 1, 1, 1, 1])
            record.log.append(.committed(category, points))
            record.log.append(record.log.state.isAllScored ? .gameEnded : .turnAdvanced)
        }
        return record
    }

    @Test("저장한 기록을 그대로 읽는다 — 모드와 참가자까지")
    func 왕복() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var record = MatchRecord(mode: .versusBot(.hard))
        record.log.append(.rolled([6, 6, 6, 6, 6]))
        record.log.append(.committed(.yacht, 50))
        try store.save(record)

        let loaded = try #require(store.load())
        #expect(loaded == record)
        #expect(loaded.participants == [.human(name: "나"), .bot(.hard)])
        #expect(loaded.log.state.scorecards[0].entry(.yacht) == 50)
    }

    @Test("v1 파일(로그만)은 혼자 연습으로 읽는다")
    func v1_호환() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var log = MatchLog(playerCount: 1)
        log.append(.rolled([1, 2, 3, 4, 5]))
        try log.encoded().write(to: directory.appending(path: "match.json"))

        let loaded = try #require(store.load())
        #expect(loaded.mode == .solo)
        #expect(loaded.participants == [.human(name: "나")])
        #expect(loaded.log == log)
    }

    @Test("참가자 수와 로그의 플레이어 수가 다르면 버린다")
    func 불일치_거부() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let record = MatchRecord(mode: .passAndPlay(names: ["A", "B"]),
                                 participants: [.human(name: "A")],
                                 log: MatchLog(playerCount: 2))
        let data = try JSONEncoder().encode(record)
        try data.write(to: directory.appending(path: "match.json"))
        #expect(store.load() == nil)
    }

    @Test("손상된 로그가 든 v2 파일은 버린다")
    func 손상_로그_거부() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var log = MatchLog(playerCount: 1)
        log.append(.committed(.yacht, 999))   // 굴리기 전에 기록 — canApply가 거부
        let record = MatchRecord(mode: .solo, participants: GameMode.solo.participants, log: log)
        try JSONEncoder().encode(record).write(to: directory.appending(path: "match.json"))
        #expect(store.load() == nil)
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
        try store.save(MatchRecord(mode: .solo))
        try store.clear()
        #expect(store.load() == nil)
    }

    @Test("끝난 게임은 저장하지 않고 기존 파일도 지운다")
    func 끝난_게임() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(MatchRecord(mode: .solo))

        let record = finishedRecord()
        #expect(record.isFinished)
        try store.save(record)
        #expect(store.load() == nil)
    }

    @Test("패스앤플레이 참가자는 이름 순서대로다")
    func 패스앤플레이_참가자() {
        let record = MatchRecord(mode: .passAndPlay(names: ["철수", "영희", "민수"]))
        #expect(record.participants == [.human(name: "철수"), .human(name: "영희"), .human(name: "민수")])
        #expect(record.log.playerCount == 3)
    }

    @Test("오목 기록은 moveLog로 저장되고 그대로 돌아온다")
    func 오목_왕복() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var log = MoveLog<Omok>()
        _ = log.append(Omok.Move(x: 7, y: 7))
        let record = MatchRecord(game: Omok.id, mode: .passAndPlay(names: ["갑", "을"]),
                                 participants: [.human(name: "갑"), .human(name: "을")], moveLog: try log.encoded())
        try store.save(record)
        let loaded = try #require(store.load())
        #expect(loaded.game == "omok" && loaded.moveLog == record.moveLog && loaded.log.events.isEmpty)
    }

    @Test("v2 파일은 game이 yacht로 읽힌다")
    func v2_호환() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let v2 = """
        {"formatVersion":2,"mode":{"solo":{}},"participants":[{"human":{"name":"나"}}],"log":{"formatVersion":1,"playerCount":1,"events":[]}}
        """
        try Data(v2.utf8).write(to: dir.appending(path: "match.json"))
        let loaded = try #require(store.load())
        #expect(loaded.game == "yacht" && loaded.mode == .solo)
    }
}
