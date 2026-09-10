import Testing
import Foundation
import GameCore
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

    private func makeContainer() throws -> (AppContainer, URL) {
        let (store, directory) = try makeStore()
        return (AppContainer(store: store, arguments: []), directory)
    }

    @Test("저장된 판이 없으면 허브에서 시작한다")
    func 허브_시작() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer(store: store, arguments: [])
        guard case .hub = container.status else { Issue.record("허브가 아니다: \(container.status)"); return }
        #expect(container.savedRecord == nil)
    }

    @Test("허브에서 게임을 고르면 그 게임의 메뉴가 열리고 뒤로 가면 허브다")
    func 허브_메뉴() throws {
        let (container, dir) = try makeContainer()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard case .hub = container.status else { Issue.record("허브가 아니다"); return }
        container.showMenu(.omok)
        guard case .menu(.omok) = container.status else { Issue.record("오목 메뉴가 아니다"); return }
        container.returnToHub()
        guard case .hub = container.status else { Issue.record("허브로 돌아오지 않았다"); return }
    }

    @Test("오목 로컬 2인을 시작하면 OnlineMatch가 만들어지고 수를 두면 저장된다")
    func 오목_로컬() async throws {
        let (container, dir) = try makeContainer()
        defer { try? FileManager.default.removeItem(at: dir) }
        container.startOmokLocal(names: ["갑", "을"])
        guard case .playingOmok(let match) = container.status else { Issue.record("오목이 아니다"); return }
        let played = await match.play(Omok.Move(x: 7, y: 7))
        #expect(played)
        let saved = try #require(MatchStore(directory: dir).load())
        #expect(saved.game == "omok" && saved.mode == .passAndPlay(names: ["갑", "을"]))
        container.returnToMenu()
        guard case .menu(.omok) = container.status else { Issue.record("오목 메뉴가 아니다"); return }
        container.resumeSavedGame()
        guard case .playingOmok(let resumed) = container.status else { Issue.record("이어하기 실패"); return }
        #expect(resumed.state.stone(x: 7, y: 7) == 1)
    }

    @Test("이어할 수 없는 오목 저장은 지우고 허브로 돌아간다")
    func 못_이어하는_오목() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 같은 자리에 두 번 둔 로그라 재적용에서 거부된다
        let 깨진_로그 = Data(#"{"moves":[{"x":7,"y":7},{"x":7,"y":7}]}"#.utf8)
        try store.save(MatchRecord(game: Omok.id, mode: .passAndPlay(names: ["갑", "을"]),
                                   participants: [.human(name: "갑"), .human(name: "을")], moveLog: 깨진_로그))
        let container = AppContainer(store: store, arguments: [])
        #expect(container.savedRecord != nil, "저장은 읽혀야 한다")
        container.resumeSavedGame()
        guard case .hub = container.status else { Issue.record("허브가 아니다: \(container.status)"); return }
        #expect(container.savedRecord == nil)
        #expect(MatchStore(directory: directory).load() == nil, "죽은 저장이 남아 이어하기 버튼이 계속 뜬다")
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
        guard case .menu(.yacht) = container.status else { Issue.record("요트 메뉴가 아니다"); return }
        #expect(container.savedRecord?.log.events.count == 1)
    }

    @Test("컵퐁 로컬 2인을 시작하면 OnlineMatch<CupPong>가 만들어지고 던진 뒤 이어하기가 된다")
    func 컵퐁_로컬() async throws {
        let (container, dir) = try makeContainer()
        defer { try? FileManager.default.removeItem(at: dir) }
        container.startCupPongLocal(names: ["갑", "을"])
        guard case .playingCupPong(let match) = container.status else { Issue.record("컵퐁이 아니다"); return }
        let ok = await match.play(CupPong.Shot(dx: 0, power: 350)); #expect(ok)
        let saved = try #require(MatchStore(directory: dir).load())
        #expect(saved.game == "cuppong")
        container.returnToMenu()
        guard case .menu(.cuppong) = container.status else { Issue.record("컵퐁 메뉴가 아니다"); return }
        container.resumeSavedGame()
        guard case .playingCupPong(let resumed) = container.status else { Issue.record("이어하기 실패"); return }
        #expect(resumed.state.remaining(seat: 1) == 9)
    }
}
