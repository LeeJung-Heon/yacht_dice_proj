import Testing
@testable import YachtDice

@Suite("테마 대비")
struct ThemeTests {
    @Test("본문·보조·황동·상아 조합이 4.5:1 이상이다", arguments: [ThemePalette.light, ThemePalette.dark])
    func 대비(palette: ThemePalette) {
        let pairs: [(String, RGB, RGB)] = [
            ("ink/paper", palette.ink, palette.paper),
            ("inkSecondary/paper", palette.inkSecondary, palette.paper),
            ("brassInk/brass", palette.brassInk, palette.brass),
            ("pip/ivory", palette.pip, palette.ivory),
            ("ivory/leather", palette.ivory, palette.leather),
        ]
        for (name, a, b) in pairs {
            #expect(contrastRatio(a, b) >= 4.5, "\(name) 대비 \(contrastRatio(a, b))")
        }
    }

    @Test("대비 계산: 흑백은 21, 같은 색은 1")
    func 대비_공식() {
        #expect(abs(contrastRatio(RGB(hex: 0x000000), RGB(hex: 0xFFFFFF)) - 21) < 0.01)
        #expect(abs(contrastRatio(RGB(hex: 0x808080), RGB(hex: 0x808080)) - 1) < 0.001)
    }
}
