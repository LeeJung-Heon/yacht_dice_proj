// 앱 아이콘 1024x1024 PNG를 코드로 그린다.
// 외부 디자인 파일 없이 아이콘을 재현 가능하게 두기 위한 스크립트다.
//
//   swift Tools/AppIcon/GenerateAppIcon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//
// 알파 채널을 쓰지 않는다 — App Store는 마케팅 아이콘에 알파를 허용하지 않는다.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
                 ? CommandLine.arguments[1]
                 : "AppIcon-1024.png")

guard let context = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("컨텍스트를 만들지 못했다")
}

let s = CGFloat(side)

// 트레이 가죽과 같은 붉은색 계열의 배경
let space = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: space, colors: [
    CGColor(colorSpace: space, components: [0.62, 0.15, 0.14, 1])!,
    CGColor(colorSpace: space, components: [0.33, 0.06, 0.07, 1])!,
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: s, y: 0), options: [])

// 주사위 한 개. 작은 크기에서도 읽히도록 기울이지 않고 크게 놓는다.
let dieSide = s * 0.62
let dieRect = CGRect(x: (s - dieSide) / 2, y: (s - dieSide) / 2, width: dieSide, height: dieSide)

context.setShadow(offset: CGSize(width: 0, height: -s * 0.018), blur: s * 0.05,
                  color: CGColor(colorSpace: space, components: [0, 0, 0, 0.45])!)
context.setFillColor(CGColor(colorSpace: space, components: [0.98, 0.97, 0.94, 1])!)
context.addPath(CGPath(roundedRect: dieRect, cornerWidth: dieSide * 0.18,
                       cornerHeight: dieSide * 0.18, transform: nil))
context.fillPath()
context.setShadow(offset: .zero, blur: 0, color: nil)

// 눈은 5. 1은 심심하고 6은 작은 크기에서 뭉친다.
context.setFillColor(CGColor(colorSpace: space, components: [0.13, 0.12, 0.12, 1])!)
let pipRadius = dieSide * 0.098
for (fx, fy) in [(0.27, 0.27), (0.27, 0.73), (0.5, 0.5), (0.73, 0.27), (0.73, 0.73)] {
    let center = CGPoint(x: dieRect.minX + CGFloat(fx) * dieSide,
                         y: dieRect.minY + CGFloat(fy) * dieSide)
    context.fillEllipse(in: CGRect(x: center.x - pipRadius, y: center.y - pipRadius,
                                   width: pipRadius * 2, height: pipRadius * 2))
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("PNG를 만들지 못했다")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("PNG 쓰기 실패") }
print("wrote \(output.path)")
