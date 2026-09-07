import Testing
import RealityKit
@testable import YachtDice

/// IBL 배선 구조를 검증한다. `ImageBasedLightComponent`는 광원에, `ImageBasedLightReceiverComponent`는
/// 비출 대상의 조상에 붙어 광원 엔티티를 가리켜야 한다. 둘 다 같은 leaf 엔티티에 붙이면
/// 광원이 자기 자신만 비추고, 화면에 보이는 지오메트리(table/tray/dice)는 아무것도
/// 이 IBL을 받지 못한다 (코드 리뷰에서 지적된 결함).
@Suite("씬 구성 - IBL 배선")
struct DiceSceneBuilderTests {

    @Test("root가 IBL 수신 컴포넌트를 갖고, 그 컴포넌트는 IBL 소스를 가진 별도 엔티티를 가리킨다")
    @MainActor
    func iBL_수신_배선() throws {
        let root = DiceSceneBuilder.makeRoot()

        let receiver = try #require(
            root.components[ImageBasedLightReceiverComponent.self],
            "root에 ImageBasedLightReceiverComponent가 없다 — IBL 수신이 비출 대상의 조상에 배선되지 않았다")

        let source = receiver.imageBasedLight
        #expect(
            source.components[ImageBasedLightComponent.self] != nil,
            "수신 컴포넌트가 가리키는 엔티티에 ImageBasedLightComponent가 없다 — 광원 엔티티를 가리키지 않는다")
        #expect(
            source !== root,
            "광원 엔티티와 수신 엔티티(root)가 같으면 안 된다 — 그러면 광원이 자기 자신만 비추고 table/tray/dice는 아무것도 이 IBL을 받지 못한다")
    }
}

@Suite("씬 구성 - 비용")
struct DiceSceneBuildCostTests {
    /// 씬은 앱 시작 시 동기로 조립된다. 절차적 텍스처가 무거워지면 첫 화면이 늦게 뜬다.
    /// Debug 빌드(최적화 없음) 기준 상한이라 Release에서는 훨씬 빠르다.
    @Test("씬 조립이 2초 안에 끝난다 (Debug)")
    @MainActor
    func 조립_시간() {
        let start = ContinuousClock.now
        _ = DiceSceneBuilder.makeRoot()
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2), "씬 조립에 \(elapsed) 걸렸다")
    }
}
