import Testing
import simd
@testable import DiceTrajectory

@Suite("주사위 면과 회전 대칭군")
struct OctahedralGroupTests {

    @Test("마주 보는 면의 합이 7이다")
    func 반대면_합() {
        for (value, normal) in DieFace.faces {
            let opposite = DieFace.faces.first { simd_length($0.normal + normal) < 1e-5 }
            #expect(opposite != nil, "눈 \(value)의 반대면이 없다")
            #expect(value + opposite!.value == 7, "눈 \(value)의 반대면이 \(opposite!.value)다")
        }
    }

    @Test("서양식 오른손 주사위다 — 1,2,3이 한 꼭짓점을 반시계로 돈다")
    func 오른손_주사위() {
        // +X=3, +Y=1, +Z=2. 이 셋이 만나는 꼭짓점 (1,1,1)에서 바라볼 때
        // 1 -> 2 -> 3 이 반시계 방향이면 오른손 주사위다.
        // 판정: n1 x n2 가 n3 쪽을 향하면 반시계.
        let n1 = DieFace.normal(of: 1)
        let n2 = DieFace.normal(of: 2)
        let n3 = DieFace.normal(of: 3)
        #expect(simd_dot(simd_cross(n1, n2), n3) > 0.9, "왼손 주사위가 되었다")
    }

    @Test("항등 자세에서는 1이 위를 향한다")
    func 항등_자세() {
        #expect(DieFace.upValue(for: simd_quatf(angle: 0, axis: [0, 1, 0])) == 1)
    }

    @Test("X축으로 90도 돌리면 위 면이 바뀐다")
    func 회전_후_윗면() {
        // +Y(1)를 X축 기준 +90도 돌리면 +Z(2)로 간다 -> 위에는 -Z(5)에 있던 면이 온다
        let q = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        #expect(DieFace.upValue(for: q) == 5)
    }

    @Test("대칭군의 원소가 정확히 24개다")
    func 원소_개수() {
        #expect(OctahedralGroup.elements.count == 24, "정육면체 회전 대칭군은 24개다")
    }

    @Test("24개 원소가 서로 다르다")
    func 원소_유일성() {
        let elements = OctahedralGroup.elements
        for i in 0..<elements.count {
            for j in (i + 1)..<elements.count {
                #expect(!OctahedralGroup.isSameRotation(elements[i], elements[j]),
                        "원소 \(i)와 \(j)가 같은 회전이다")
            }
        }
    }

    @Test("각 눈이 위를 향하는 축정렬 자세가 정확히 4개씩이다", arguments: 1...6)
    func 눈별_자세_개수(value: Int) {
        let matching = OctahedralGroup.elements.filter { DieFace.upValue(for: $0) == value }
        #expect(matching.count == 4, "눈 \(value)가 위인 축정렬 자세는 Y축 자전 4가지여야 한다")
    }

    @Test("모든 원소가 정육면체를 자기 자신으로 보낸다")
    func 대칭성() {
        for (index, q) in OctahedralGroup.elements.enumerated() {
            #expect(OctahedralGroup.preservesCube(q, tolerance: 1e-4),
                    "원소 \(index)가 정육면체를 보존하지 않는다")
        }
    }

    @Test("군이 곱셈에 대해 닫혀 있다")
    func 폐포() {
        let elements = OctahedralGroup.elements
        for a in elements {
            for b in elements {
                let product = simd_normalize(simd_mul(a, b))
                #expect(elements.contains { OctahedralGroup.isSameRotation($0, product) },
                        "곱이 군 밖으로 나갔다")
            }
        }
    }

    @Test("어떤 눈에서 어떤 눈으로 보내는 원소가 정확히 4개씩이다")
    func 면_대응_원소_개수() {
        for source in 1...6 {
            for destination in 1...6 {
                let mapped = OctahedralGroup.elements(mapping: source, to: destination)
                #expect(mapped.count == 4, "\(source)→\(destination) 원소가 \(mapped.count)개다")
                for element in mapped {
                    let moved = element.act(DieFace.normal(of: source))
                    #expect(simd_length(moved - DieFace.normal(of: destination)) < 1e-4,
                            "\(source)→\(destination) 원소가 법선을 엉뚱한 곳으로 보낸다")
                }
            }
        }
    }

    @Test("윗면 기울기는 yaw에 영향받지 않는다")
    func 윗면_기울기는_yaw와_무관() {
        // 스펙 §7.3: 바닥에 누운 주사위는 yaw가 자유롭다.
        // 24개 최근접 거리로 재면 최대 45도가 나오지만 윗면 기울기는 0이어야 한다.
        for yawDegrees in stride(from: Float(0), to: 360, by: 7) {
            let yaw = simd_quatf(angle: yawDegrees * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
            for base in OctahedralGroup.elements {
                let resting = simd_normalize(simd_mul(yaw, base))
                let tilt = DieFace.upFaceTiltRadians(for: resting) * 180 / .pi
                #expect(tilt < 0.1, "yaw \(yawDegrees)도에서 윗면 기울기가 \(tilt)도로 나왔다")
            }
        }
    }

    @Test("실제로 기울어진 자세는 윗면 기울기로 잡힌다")
    func 기울기_감지() {
        let tiltAngle: Float = 5
        let tilted = simd_normalize(simd_mul(
            simd_quatf(angle: tiltAngle * .pi / 180, axis: SIMD3<Float>(1, 0, 0)),
            OctahedralGroup.elements[0]))
        let measured = DieFace.upFaceTiltRadians(for: tilted) * 180 / .pi
        #expect(abs(measured - tiltAngle) < 0.2, "5도 기울였는데 \(measured)도로 측정됐다")
    }
}
