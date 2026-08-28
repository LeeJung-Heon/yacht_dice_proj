import Foundation
import simd

/// 베이커와 앱이 반드시 같은 치수를 써야 한다. 어긋나면 궤적이 트레이를 뚫는다.
/// 실물 주사위 16mm를 기준으로 잡았다.
public enum TrayGeometry {
    /// 물리 공간. 베이커가 이 상자 안에서 주사위를 굴리고
    /// TrajectoryValidator가 이 상한으로 궤적을 검사한다. 절대 바꾸지 않는다.
    public static let trayInner = SIMD3<Float>(0.24, 0.12, 0.24)
    public static let dieSize: Float = 0.016
    public static let wallThickness: Float = 0.01

    /// 화면에 그리는 벽 높이. 물리 높이(0.12)와 일부러 다르다.
    ///
    /// 55도 부감 카메라에서 0.12짜리 앞벽은 트레이 바닥 앞쪽 절반을 가린다 —
    /// 구운 궤적 593개의 정지 위치 중 41%가 앞벽 뒤에 숨어 아예 보이지 않았다.
    /// 0.03으로 낮추면 정지한 주사위의 윗면(눈이 보이는 면)이 100% 드러나고,
    /// 그 대가는 "테두리보다 높이 뜬 채 벽에 닿는" 프레임 0.04%뿐이다.
    /// (전체 프레임의 6.8%는 테두리보다 높지만, 그건 던져 넣는 도중의 공중 구간이라
    ///  낮은 테두리 위로 날아 들어오는 것처럼 자연스럽게 읽힌다.)
    public static let visualWallHeight: Float = 0.030

    // MARK: - keep 선반

    /// 선반 윗면 높이. 여기에 keep한 주사위가 올라앉는다.
    public static let shelfTop: Float = 0.022
    /// 선반 앞면의 z. 이 뒤(더 작은 z)로는 구운 궤적 어디에서도 주사위가 멈추지 않는다
    /// (실측 정지 위치의 최소 z = -0.069, 주사위 반폭 0.008을 빼도 -0.077).
    /// 그래서 선반과 굴러간 주사위는 절대 겹치지 않는다.
    public static let shelfFrontZ: Float = -0.078
    /// 선반 뒷면의 z — 트레이 안쪽 뒷벽.
    public static var shelfBackZ: Float { -trayInner.z / 2 }
    /// 선반 위에 놓인 주사위의 중심.
    public static var shelfDieY: Float { shelfTop + dieSize / 2 }
    public static var shelfDieZ: Float { (shelfBackZ + shelfFrontZ) / 2 }
}
