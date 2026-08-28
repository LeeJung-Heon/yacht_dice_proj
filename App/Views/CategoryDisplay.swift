import Foundation
import YachtCore

extension ScoreCategory {
    /// 점수판에 보이는 이름. 레퍼런스 표기를 따른다.
    var displayName: String {
        switch self {
        case .aces:          "Aces"
        case .deuces:        "Deuces"
        case .threes:        "Threes"
        case .fours:         "Fours"
        case .fives:         "Fives"
        case .sixes:         "Sixes"
        case .choice:        "Choice"
        case .fourOfAKind:   "4 of a Kind"
        case .fullHouse:     "Full House"
        case .smallStraight: "S. Straight"
        case .largeStraight: "L. Straight"
        case .yacht:         "Yacht"
        }
    }

    /// VoiceOver가 읽는 설명. 레퍼런스의 툴팁과 같은 역할이다.
    var accessibilityDescription: String {
        switch self {
        case .aces:          "1이 나온 주사위의 합"
        case .deuces:        "2가 나온 주사위의 합"
        case .threes:        "3이 나온 주사위의 합"
        case .fours:         "4가 나온 주사위의 합"
        case .fives:         "5가 나온 주사위의 합"
        case .sixes:         "6이 나온 주사위의 합"
        case .choice:        "주사위 5개의 합"
        case .fourOfAKind:   "같은 숫자 4개 이상이면 주사위 5개의 합"
        case .fullHouse:     "같은 숫자 3개와 2개면 주사위 5개의 합"
        case .smallStraight: "연속된 숫자 4개면 15점"
        case .largeStraight: "연속된 숫자 5개면 30점"
        case .yacht:         "같은 숫자 5개면 50점"
        }
    }
}
