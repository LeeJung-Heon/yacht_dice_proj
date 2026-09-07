import SwiftUI
import RealityKit
import AppKit
import DiceTrajectory

@main
struct BakerApp: App {
    // Task 2 스파이크가 셸에서 직접 실행할 때 검증한 트릭. 없으면 창 서버 연결이 없는
    // 헤드리스 실행에서 RealityView 콘텐츠 클로저가 아예 호출되지 않아 CPU를 전혀
    // 쓰지 않고 멈춰 있는 상태로 관찰됐다 (실측: 44초 경과, CPU 0.06초).
    init() {
        setvbuf(stdout, nil, _IOLBF, 0)
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some SwiftUI.Scene {
        WindowGroup("Trajectory Baker") {
            BakerView().frame(minWidth: 720, minHeight: 520)
        }
    }
}

struct BakerView: View {
    @State private var model = BakerModel()
    @State private var frameTick = 0

    var body: some View {
        VStack(spacing: 12) {
            RealityView { content in
                content.add(model.makeScene())
                let camera = Entity()
                camera.components.set(PerspectiveCameraComponent())
                camera.look(at: .zero, from: [0, 0.4, 0.35], relativeTo: nil)
                content.add(camera)
            }
            .frame(height: 320)

            Text(model.progress).font(.system(.body, design: .monospaced))
            ScrollView { Text(model.result.summary).font(.system(.caption, design: .monospaced)) }
                .frame(height: 100)

            Button(model.isRunning ? "굽는 중..." : "굽기 시작") {
                Task { await bake() }
            }
            .disabled(model.isRunning)
        }
        .padding()
        // 셸에서 nohup으로 띄우면 버튼을 누를 사람이 없다. 뷰가 뜨자마자 자동으로 굽기
        // 시작한다 — 버튼은 Xcode GUI로 직접 열었을 때를 위해 남겨둔다.
        .task { await bake() }
    }

    /// RealityKit 물리는 렌더 루프에 물려 있으므로 한 프레임씩 실제 시간으로 흘려보낸다.
    /// 600개 x 약 2.5초 = 25분쯤 걸린다. 일회성 작업이므로 감수한다.
    private func advanceFrame() async {
        try? await Task.sleep(for: .milliseconds(1000 / BakePlan.frameRate))
    }

    private func bake() async {
        model.isRunning = true
        model.result = BakeResult()
        var nextID: UInt16 = 0
        if let source = BakePlan.mergeSource {
            do {
                let existing = try TrajectoryArchive.decode(try Data(contentsOf: source))
                model.result.accepted = existing
                nextID = UInt16(existing.count)
                print("병합: \(source.path)에서 \(existing.count)개를 먼저 읽었다")
            } catch {
                print("병합 실패: \(error)")
                exit(1)
            }
        }

        for combination in BakePlan.combinations {
            // 25분짜리 헤드리스 실행을 셸에서 폴링해야 하므로 조합이 바뀔 때마다
            // stdout에 진행 상황을 남긴다 (브리프의 최종 요약 출력에 더한 것).
            print("진행: \(combination.dieCount)개 / \(combination.direction) 시작 — 지금까지 채택 \(model.result.accepted.count) / 기각 \(model.result.rejected.count)")
            for variant in 0..<BakePlan.variantsPerCombination {
                model.progress = "\(combination.dieCount)개 / \(combination.direction) / \(variant + 1)"
                let outcome = await model.bakeOne(
                    id: nextID, dieCount: combination.dieCount, direction: combination.direction,
                    advanceFrame: advanceFrame)
                switch outcome {
                case .success(let trajectory):
                    model.result.accepted.append(trajectory)
                    nextID += 1
                case .failure(let reason):
                    model.result.rejected.append((reason, combination.dieCount, combination.direction))
                    print("  기각: \(reason)")
                }
            }
        }

        do {
            let data = try TrajectoryArchive.encode(model.result.accepted)
            let url = URL(fileURLWithPath: "/private/tmp/trajectories.bin")
            try data.write(to: url)
            model.progress = "완료: \(url.path) (\(data.count / 1024)KB)"
            print(model.progress)
            print(model.result.summary)
        } catch {
            model.progress = "쓰기 실패: \(error)"
            print(model.progress)
        }
        model.isRunning = false
        exit(0)   // 셸에서 돌리므로 다 구우면 스스로 종료한다
    }
}
