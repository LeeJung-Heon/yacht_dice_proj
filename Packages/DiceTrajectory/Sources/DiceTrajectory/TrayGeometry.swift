import Foundation
import simd

/// 베이커와 앱이 반드시 같은 치수를 써야 한다. 어긋나면 궤적이 트레이를 뚫는다.
/// 실물 주사위 16mm를 기준으로 잡았다.
public enum TrayGeometry {
    public static let trayInner = SIMD3<Float>(0.24, 0.12, 0.24)
    public static let dieSize: Float = 0.016
    public static let wallThickness: Float = 0.01
    /// keep한 주사위가 올라가는 상단 선반의 높이.
    public static let shelfHeight: Float = 0.16
}
