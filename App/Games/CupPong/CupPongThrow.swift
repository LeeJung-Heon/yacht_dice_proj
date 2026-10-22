/// 던지기의 두 갈래, 수를 올리는 일과 공의 연출을 잇는다. 순서만 다루는 함수라 테스트한다.
enum CupPongThrow {
    /// 수는 화면 Task에 매이지 않은 Task로 올려, 화면을 떠나 연출이 끊겨도 이미 채널로 나간 수가 DB에도 닿게 한다.
    /// 화면은 공이 닿는 즉시 풀어 느린 망의 재시도가 착지 뒤의 화면을 붙잡지 않게 하고, 규칙이 거절했으면 그 뒤에 알린다.
    @MainActor
    static func run(play: @escaping @MainActor () async -> Bool, animate: @MainActor () async -> Void,
                    landed: @MainActor () -> Void, rejected: @MainActor () -> Void) async {
        let playing = Task { @MainActor in await play() }
        await animate()
        guard !Task.isCancelled else { return }
        landed()
        if await playing.value == false { rejected() }
    }
}
