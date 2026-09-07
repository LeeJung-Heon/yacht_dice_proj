// 앱 아이콘 1024x1024 PNG를 코드로 그린다.
// 외부 디자인 파일 없이 아이콘을 재현 가능하게 두기 위한 스크립트다.
//
//   swift Tools/AppIcon/GenerateAppIcon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//
// 같은 자리에 60px 축소본(AppIcon-60-preview.png)도 저장한다 — 홈 화면 크기에서 주사위가 읽히는지 확인용.
// 알파 채널을 쓰지 않는다 — App Store는 마케팅 아이콘에 알파를 허용하지 않는다.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
                 ? CommandLine.arguments[1]
                 : "AppIcon-1024.png")

let space = CGColorSpaceCreateDeviceRGB()

func makeContext(_ size: Int) -> CGContext {
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("컨텍스트를 만들지 못했다")
    }
    return context
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

let context = makeContext(side)
let s = CGFloat(side)

// 1. 호두나무 테두리 — 전체를 나무로 칠하고 결 줄무늬를 긋는다
context.setFillColor(color(0.33, 0.20, 0.11))
context.fill(CGRect(x: 0, y: 0, width: s, height: s))
var seed: UInt64 = 42
func rand() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat(seed >> 40) / CGFloat(1 << 24)
}
for i in 0..<48 {
    let y = CGFloat(i) / 48 * s + rand() * 12
    let dark = rand() > 0.5
    context.setStrokeColor(dark ? color(0.22, 0.12, 0.06, 0.55) : color(0.46, 0.30, 0.16, 0.45))
    context.setLineWidth(3 + rand() * 9)
    context.move(to: CGPoint(x: 0, y: y))
    context.addCurve(to: CGPoint(x: s, y: y + (rand() - 0.5) * 30),
                     control1: CGPoint(x: s * 0.35, y: y + (rand() - 0.5) * 40),
                     control2: CGPoint(x: s * 0.65, y: y + (rand() - 0.5) * 40))
    context.strokePath()
}

// 2. 안쪽 가죽 — 테두리 폭 6%, 모서리 라운드. 가운데가 밝은 방사 그러데이션
let inset = s * 0.06
let leatherRect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
let leatherPath = CGPath(roundedRect: leatherRect, cornerWidth: s * 0.06, cornerHeight: s * 0.06, transform: nil)
context.saveGState()
context.setShadow(offset: .zero, blur: s * 0.02, color: color(0, 0, 0, 0.6))
context.setFillColor(color(0.30, 0.06, 0.07))
context.addPath(leatherPath)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(leatherPath)
context.clip()
let leatherGradient = CGGradient(colorsSpace: space, colors: [
    color(0.56, 0.17, 0.17), color(0.42, 0.10, 0.11), color(0.27, 0.05, 0.07),
] as CFArray, locations: [0, 0.6, 1])!
context.drawRadialGradient(leatherGradient, startCenter: CGPoint(x: s * 0.5, y: s * 0.55), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.5, y: s * 0.5), endRadius: s * 0.75, options: [])
// 가죽 결 — 반투명 점 700개
for _ in 0..<700 {
    let r = 6 + rand() * 18
    let bright = rand() > 0.5
    context.setFillColor(bright ? color(1, 0.85, 0.8, 0.035) : color(0, 0, 0, 0.06))
    context.fillEllipse(in: CGRect(x: inset + rand() * leatherRect.width - r, y: inset + rand() * leatherRect.height - r,
                                   width: r * 2, height: r * 2))
}
context.restoreGState()

// 3. 주사위 두 개 — 상아색, 기울여서. 그림자를 아래로.
func drawDie(center: CGPoint, sideLength: CGFloat, angleDegrees: CGFloat, value: Int) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: angleDegrees * .pi / 180)
    let rect = CGRect(x: -sideLength / 2, y: -sideLength / 2, width: sideLength, height: sideLength)
    let path = CGPath(roundedRect: rect, cornerWidth: sideLength * 0.18, cornerHeight: sideLength * 0.18, transform: nil)

    context.setShadow(offset: CGSize(width: 0, height: -sideLength * 0.06), blur: sideLength * 0.12, color: color(0, 0, 0, 0.5))
    context.setFillColor(color(0.97, 0.95, 0.90))
    context.addPath(path)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    // 위쪽이 살짝 밝은 면
    context.addPath(path)
    context.clip()
    let faceGradient = CGGradient(colorsSpace: space, colors: [color(1, 1, 0.98, 0.5), color(0.9, 0.87, 0.8, 0.0)] as CFArray,
                                  locations: [0, 1])!
    context.drawLinearGradient(faceGradient, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])

    context.setFillColor(color(0.09, 0.08, 0.09))
    let pipRadius = sideLength * 0.095
    let a: CGFloat = 0.26, b: CGFloat = 0.5, c: CGFloat = 0.74
    let layouts: [Int: [(CGFloat, CGFloat)]] = [
        1: [(b, b)], 2: [(a, c), (c, a)], 3: [(a, c), (b, b), (c, a)],
        4: [(a, a), (a, c), (c, a), (c, c)], 5: [(a, a), (a, c), (b, b), (c, a), (c, c)],
        6: [(a, a), (a, b), (a, c), (c, a), (c, b), (c, c)],
    ]
    for (fx, fy) in layouts[value] ?? [] {
        let p = CGPoint(x: rect.minX + fx * sideLength, y: rect.minY + fy * sideLength)
        context.fillEllipse(in: CGRect(x: p.x - pipRadius, y: p.y - pipRadius, width: pipRadius * 2, height: pipRadius * 2))
    }
    context.restoreGState()
}

// 눈이 서로 가려지지 않게 두 주사위는 모서리만 스치도록 떨어뜨린다
let dieSide = s * 0.31
drawDie(center: CGPoint(x: s * 0.33, y: s * 0.40), sideLength: dieSide, angleDegrees: -12, value: 5)
drawDie(center: CGPoint(x: s * 0.68, y: s * 0.62), sideLength: dieSide, angleDegrees: 9, value: 2)

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("PNG를 만들지 못했다")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG 쓰기 실패") }
    print("wrote \(url.path)")
}

guard let image = context.makeImage() else { fatalError("이미지를 만들지 못했다") }
write(image, to: output)

// 60px 축소본 — 홈 화면 크기 확인용. 커밋하지 않는다.
let preview = makeContext(60)
preview.interpolationQuality = .high
preview.draw(image, in: CGRect(x: 0, y: 0, width: 60, height: 60))
if let small = preview.makeImage() {
    write(small, to: output.deletingLastPathComponent().appending(path: "AppIcon-60-preview.png"))
}
