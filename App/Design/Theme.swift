import SwiftUI

/// sRGB 성분. 테마의 원본이며 대비 계산에 쓴다.
struct RGB: Equatable, Sendable {
    let r: Double, g: Double, b: Double

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    /// WCAG 상대 휘도.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}

/// WCAG 대비 비율 (1...21).
func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
    let (l1, l2) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
    return (l1 + 0.05) / (l2 + 0.05)
}

/// 보드게임 테이블 팔레트. 글자 조합의 대비는 ThemeTests가 4.5:1 이상으로 강제한다.
struct ThemePalette: Sendable {
    let table, paper, paperLine, leather, ink, inkSecondary, brass, brassInk, success, ivory, pip: RGB

    static let light = ThemePalette(
        table: RGB(hex: 0x5A3A22), paper: RGB(hex: 0xF4EDDC), paperLine: RGB(hex: 0xD8CDB4),
        leather: RGB(hex: 0x6B1E22), ink: RGB(hex: 0x1E1A17), inkSecondary: RGB(hex: 0x6E6255),
        brass: RGB(hex: 0xB8862B), brassInk: RGB(hex: 0x2A1D04), success: RGB(hex: 0x2E6B3F),
        ivory: RGB(hex: 0xF7F3EA), pip: RGB(hex: 0x171516))

    static let dark = ThemePalette(
        table: RGB(hex: 0x1E140D), paper: RGB(hex: 0x2A211A), paperLine: RGB(hex: 0x3F332A),
        leather: RGB(hex: 0x4A1418), ink: RGB(hex: 0xF1E9D6), inkSecondary: RGB(hex: 0xB8AC98),
        brass: RGB(hex: 0xD3A24A), brassInk: RGB(hex: 0x1E1608), success: RGB(hex: 0x7CC28F),
        ivory: RGB(hex: 0xF7F3EA), pip: RGB(hex: 0x171516))
}

/// 뷰가 읽는 색 토큰. `@Environment(\.theme)`.
struct Theme: Sendable {
    let palette: ThemePalette
    let isDark: Bool

    var table: Color { palette.table.color }
    var paper: Color { palette.paper.color }
    var paperLine: Color { palette.paperLine.color }
    var leather: Color { palette.leather.color }
    var ink: Color { palette.ink.color }
    var inkSecondary: Color { palette.inkSecondary.color }
    var brass: Color { palette.brass.color }
    var brassInk: Color { palette.brassInk.color }
    var success: Color { palette.success.color }
    var ivory: Color { palette.ivory.color }
    /// 주사위 눈. 상아색 면 위라 모드와 무관하게 어둡다.
    var pip: Color { palette.pip.color }

    static let light = Theme(palette: .light, isDark: false)
    static let dark = Theme(palette: .dark, isDark: true)
    static func forScheme(_ scheme: ColorScheme) -> Theme { scheme == .dark ? .dark : .light }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.light
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// 루트에서 한 번 건다. 시스템 색 구성표를 따라 테마를 고른다.
struct ThemedRoot<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content.environment(\.theme, Theme.forScheme(scheme))
    }
}
