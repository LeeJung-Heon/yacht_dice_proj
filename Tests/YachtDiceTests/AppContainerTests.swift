import Testing
import Foundation
import YachtCore
import YachtBot
@testable import YachtDice

@Suite("앱 컨테이너")
@MainActor
struct AppContainerTests {

    private func makeStore() throws -> (MatchStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "yacht-container-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (MatchStore(directory: directory), directory)
    }

    @Test("저장된 판이 없으면 메뉴에서 시작한다")
    func 메뉴_시작() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer(store: store, arguments: [])
        guard case .menu = container.status else { Issue.record("메뉴가 아니다: \(container.status)"); return }
        #expect(container.savedRecord == nil)
    }

    @Test("모드를 고르면 그 모드의 세션이 만들어지고 저장된다")
    func 게임_시작() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer(store: store, arguments: [])
        container.startGame(mode: .versusBot(.easy))
        guard case .playing(let session) = container.status else { Issue.record("게임이 아니다"); return }
        #expect(session.participants == [.human(name: "나"), .bot(.easy)])
        session.reduceMotion = true
        await session.send(.roll)
        #expect(store.load()?.mode == .versusBot(.easy))
    }

    @Test("저장된 판이 있으면 메뉴에 이어하기가 뜨고, 이어하면 그 판이다")
    func 이어하기() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        var record = MatchRecord(mode: .passAndPlay(names: ["A", "B"]))
        record.log.append(.rolled([1, 2, 3, 4, 5]))
        try store.save(record)

        let container = AppContainer(store: store, arguments: [])
        #expect(container.savedRecord?.mode == .passAndPlay(names: ["A", "B"]))
        container.resumeSavedGame()
        guard case .playing(let session) = container.status else { Issue.record("게임이 아니다"); return }
        #expect(session.visibleState.dice == [1, 2, 3, 4, 5])
        #expect(session.participants.count == 2)
    }

    @Test("-resetMatch 인자는 저장을 지운다")
    func 리셋_인자() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(MatchRecord(mode: .solo))
        let container = AppContainer(store: store, arguments: ["-resetMatch"])
        #expect(container.savedRecord == nil)
    }

    @Test("메뉴로 돌아가면 진행 중인 판은 저장된 채 남는다")
    func 메뉴_복귀() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer(store: store, arguments: [])
        container.startGame(mode: .solo)
        guard case .playing(let session) = container.status else { Issue.record("게임이 아니다"); return }
        session.reduceMotion = true
        await session.send(.roll)
        container.returnToMenu()
        guard case .menu = container.status else { Issue.record("메뉴가 아니다"); return }
        #expect(container.savedRecord?.log.events.count == 1)
    }
}
