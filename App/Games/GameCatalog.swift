import Foundation

/// 허브에 보이는 게임 넷. rawValue는 서버 `matches.game`과 같다.
enum GameID: String, CaseIterable, Sendable {
    case yacht, omok, cuppong, alkkagi

    var title: String {
        switch self { case .yacht: "요트 다이스"; case .omok: "오목"; case .cuppong: "컵퐁"; case .alkkagi: "알까기" }
    }
    var subtitle: String {
        switch self {
        case .yacht: "주사위 다섯, 12턴"
        case .omok: "다섯을 먼저 잇는다"
        case .cuppong: "컵을 먼저 비운다"
        case .alkkagi: "돌을 튕겨 밀어낸다"
        }
    }
    var icon: String {
        switch self { case .yacht: "dice"; case .omok: "circle.grid.3x3"; case .cuppong: "cup.and.saucer"; case .alkkagi: "circle.circle" }
    }
    /// 아직 만들지 않은 게임은 타일이 흐리고 "준비 중"이다.
    var isAvailable: Bool { self != .alkkagi }
}
