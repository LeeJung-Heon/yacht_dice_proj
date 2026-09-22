import Foundation

extension CupPong {
    public static let stepsPerSecond = 240
    public static let frameEvery = 4
    public static let maxSteps = stepsPerSecond * 5
    public static let ballRadius = 35
    public static let cupHeight = 212
    public static let cupInnerRadius = 104
    public static let cupBaseRadius = 80
    public static let rimRadius = 8
    public static let liquidHeight = 75
    /// 속이 빈 공은 액체에 일부만 잠긴다. 화면도 같은 수면과 공 중심 높이를 쓴다.
    public static let settledBallHeight = 100

    /// 공 중심. 좌표와 높이 모두 테이블과 같은 단위이며 높이 0이 테이블 표면이다.
    public struct Frame: Equatable, Sendable {
        public let step: Int
        public let x: Int
        public let y: Int
        public let height: Int

        public init(step: Int, x: Int, y: Int, height: Int) {
            self.step = step; self.x = x; self.y = y; self.height = height
        }
    }

    public struct Event: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case tableBounce
            case rim(cup: Int)
            case cupWall(cup: Int)
            case sunk(cup: Int)
            case leftTable
        }
        public let step: Int
        public let kind: Kind
    }

    public struct Simulation: Equatable, Sendable {
        public let frames: [Frame]
        public let events: [Event]
        public let landing: Landing
        public let steps: Int
    }

    /// 1/1000 테이블 단위의 정수 좌표·속도. 부동소수점/렌더링 프레임률에 판정이 좌우되지 않는다.
    private static let precision = 1000
    private static let gravity = 24_500

    private struct Ball {
        var x = 0, y = 0, z = 400_000
        var vx: Int, vy: Int, vz = 8_000_000

        func frame(_ step: Int) -> Frame {
            Frame(step: step, x: x / precision, y: y / precision, height: z / precision)
        }

        /// 표면 법선은 길이 1000. 반발 계수는 재질별로 적용한다.
        mutating func reflect(nx: Int, ny: Int, nz: Int, restitution: Int) -> Bool {
            let incoming = (vx * nx + vy * ny + vz * nz) / 1000
            guard incoming < 0 else { return false }
            let impulse = incoming * (1000 + restitution) / 1000
            vx -= impulse * nx / 1000
            vy -= impulse * ny / 1000
            vz -= impulse * nz / 1000
            return true
        }
    }

    public static func simulate(_ shot: Shot, against cups: [Bool]) -> Simulation {
        let power = min(1000, max(0, shot.power))
        let direction = min(1000, max(-1000, shot.dx))
        let forward = (1200 + power * 6) * precision
        var ball = Ball(vx: forward * direction / 1500, vy: forward)
        var frames = [ball.frame(0)]
        var events: [Event] = []
        var enteredCup: Int?
        var sunkAt = 0
        var leftTable = false
        var steps = 0

        for step in 1...maxSteps {
            steps = step
            let previousX = ball.x, previousY = ball.y, previousZ = ball.z
            ball.vz -= gravity * precision / stepsPerSecond
            // 가벼운 공의 공기 저항. 충돌과 별도로 운동 에너지를 조금씩 잃는다.
            ball.vx = ball.vx * 99_975 / 100_000
            ball.vy = ball.vy * 99_975 / 100_000
            ball.vz = ball.vz * 99_975 / 100_000
            ball.x += ball.vx / stepsPerSecond
            ball.y += ball.vy / stepsPerSecond
            ball.z += ball.vz / stepsPerSecond

            var finished = false
            if let cup = enteredCup {
                // 입구를 완전히 통과하면 컵 안 액체가 에너지를 흡수한다.
                let center = cupCenters[cup]
                ball.x += (center.x * precision - ball.x) / 6
                ball.y += (center.y * precision - ball.y) / 6
                ball.vx /= 2; ball.vy /= 2
                ball.z = max(settledBallHeight * precision, ball.z)
                if ball.z == settledBallHeight * precision { ball.vz = 0 }
                finished = step - sunkAt >= stepsPerSecond / 5
            } else {
                for cup in cupCenters.indices where cups.indices.contains(cup) && cups[cup] {
                    let center = cupCenters[cup]
                    let dx = ball.x - center.x * precision, dy = ball.y - center.y * precision
                    let distance = integerSquareRoot(dx * dx + dy * dy)
                    let rimZ = cupHeight * precision
                    let radialGap = distance - (cupRadius - rimRadius) * precision
                    let verticalGap = ball.z - rimZ
                    let rimDistance = integerSquareRoot(radialGap * radialGap + verticalGap * verticalGap)
                    let contact = (ballRadius + rimRadius) * precision
                    if rimDistance < contact && rimDistance > 0 && distance > 0 {
                        let radialNormal = radialGap * 1000 / rimDistance
                        let nx = dx * radialNormal / distance, ny = dy * radialNormal / distance
                        let nz = verticalGap * 1000 / rimDistance
                        let push = contact - rimDistance
                        ball.x += nx * push / 1000
                        ball.y += ny * push / 1000
                        ball.z += nz * push / 1000
                        if ball.reflect(nx: nx, ny: ny, nz: nz, restitution: 720) {
                            events.append(Event(step: step, kind: .rim(cup: cup)))
                        }
                    }

                    // 테이퍼진 컵의 양면. 림이 위치를 보정했으므로 거리를 다시 구한다.
                    let wallDX = ball.x - center.x * precision, wallDY = ball.y - center.y * precision
                    let wallDistance = integerSquareRoot(wallDX * wallDX + wallDY * wallDY)
                    if ball.z > 0 && ball.z < (cupHeight - rimRadius) * precision && wallDistance > 0 {
                        let wallRadius = cupBaseRadius * precision + (cupRadius - cupBaseRadius) * ball.z / cupHeight
                        let previousDX = previousX - center.x * precision, previousDY = previousY - center.y * precision
                        let previousDistance = integerSquareRoot(previousDX * previousDX + previousDY * previousDY)
                        let previousRadius = cupBaseRadius * precision + (cupRadius - cupBaseRadius) * min(cupHeight * precision, max(0, previousZ)) / cupHeight
                        // 이전 위치도 확인해 빠른 측면 타격이 벽 너머로 넘어가도 바깥쪽으로 밀어낸다.
                        let outside = wallDistance >= wallRadius || previousDistance >= previousRadius
                        let innerRadius = wallRadius - (cupRadius - cupInnerRadius) * precision
                        let gap = outside ? wallDistance - wallRadius : innerRadius - wallDistance
                        let wallNormalLength = integerSquareRoot(cupHeight * cupHeight + (cupRadius - cupBaseRadius) * (cupRadius - cupBaseRadius))
                        let normalDistance = gap * cupHeight / wallNormalLength
                        if normalDistance < ballRadius * precision {
                            let sign = outside ? 1 : -1
                            let nx = sign * wallDX * cupHeight * 1000 / (wallDistance * wallNormalLength)
                            let ny = sign * wallDY * cupHeight * 1000 / (wallDistance * wallNormalLength)
                            let nz = -sign * (cupRadius - cupBaseRadius) * 1000 / wallNormalLength
                            let push = ballRadius * precision - normalDistance
                            ball.x += nx * push / 1000
                            ball.y += ny * push / 1000
                            ball.z += nz * push / 1000
                            if ball.reflect(nx: nx, ny: ny, nz: nz, restitution: 620) {
                                events.append(Event(step: step, kind: .cupWall(cup: cup)))
                            }
                        }
                    }

                    let entryHeight = (cupHeight - ballRadius) * precision
                    if ball.z <= entryHeight && ball.vz < 0 {
                        let entryX = ball.x - center.x * precision, entryY = ball.y - center.y * precision
                        let clearance = (cupInnerRadius - ballRadius) * precision
                        if entryX * entryX + entryY * entryY < clearance * clearance {
                            enteredCup = cup
                            sunkAt = step
                            events.append(Event(step: step, kind: .sunk(cup: cup)))
                            break
                        }
                    }
                }

                let overTable = abs(ball.x) <= tableHalfWidth * precision && (0...(tableLength * precision)).contains(ball.y)
                if overTable && ball.z <= ballRadius * precision && enteredCup == nil {
                    ball.z = ballRadius * precision
                    if ball.vz < -180 * precision {
                        ball.vz = -ball.vz * 76 / 100
                        ball.vx = ball.vx * 88 / 100; ball.vy = ball.vy * 88 / 100
                        events.append(Event(step: step, kind: .tableBounce))
                    } else {
                        ball.vz = 0
                        ball.vx = ball.vx * 94 / 100; ball.vy = ball.vy * 94 / 100
                        finished = abs(ball.vx) + abs(ball.vy) < 15 * precision
                    }
                } else if !overTable && !leftTable {
                    leftTable = true
                    events.append(Event(step: step, kind: .leftTable))
                }
                if ball.z < -800 * precision { finished = true }
            }

            // 접촉 시점은 60fps 간격 사이에 있어도 남긴다. 그래야 보간이 충돌 꼭짓점을 지우지 않는다.
            if step % frameEvery == 0 || events.last?.step == step || finished { frames.append(ball.frame(step)) }
            if finished { break }
        }
        if frames.last?.step != steps { frames.append(ball.frame(steps)) }
        let landing = Landing(x: ball.x / precision, y: ball.y / precision, cup: enteredCup)
        return Simulation(frames: frames, events: events, landing: landing, steps: steps)
    }

    /// 뉴턴 정수 제곱근. 플랫폼 수학 라이브러리의 반올림 차이를 피한다.
    private static func integerSquareRoot(_ value: Int) -> Int {
        guard value > 0 else { return 0 }
        var result = value
        var next = (result + 1) / 2
        while next < result {
            result = next
            next = (result + value / result) / 2
        }
        return result
    }
}
