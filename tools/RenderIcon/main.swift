import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// Renders the app icon: a drachma coin on an ink field. v1 is deliberately
// minimal — the owl engraving (the Athenian tetradrachm nod) is Phase C
// design work. Usage: swift run render-icon [output.png]

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "ios/Shell/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

let ink = Color(red: 0.086, green: 0.114, blue: 0.180)
let inkDeep = Color(red: 0.045, green: 0.060, blue: 0.100)
let goldLight = Color(red: 0.949, green: 0.800, blue: 0.427)
let gold = Color(red: 0.855, green: 0.663, blue: 0.263)
let goldDeep = Color(red: 0.639, green: 0.443, blue: 0.122)

let icon = ZStack {
    LinearGradient(colors: [ink, inkDeep], startPoint: .top, endPoint: .bottom)

    Circle()
        .fill(
            RadialGradient(
                colors: [goldLight, gold, goldDeep],
                center: .init(x: 0.38, y: 0.32),
                startRadius: 40,
                endRadius: 560
            )
        )
        .frame(width: 720, height: 720)
        .overlay(Circle().strokeBorder(goldDeep.opacity(0.9), lineWidth: 22))
        .overlay(Circle().inset(by: 54).strokeBorder(goldDeep.opacity(0.55), lineWidth: 7))
        .shadow(color: .black.opacity(0.45), radius: 46, y: 26)

    // U+20AF GREEK DRACHMA SIGN — the currency's own mark on its own coin.
    Text("₯")
        .font(.system(size: 400, weight: .semibold, design: .serif))
        .foregroundStyle(inkDeep.opacity(0.92))
        .offset(y: -6)
}
.frame(width: 1024, height: 1024)

let renderer = ImageRenderer(content: icon)
renderer.scale = 1

guard let image = renderer.cgImage else {
    FileHandle.standardError.write(Data("render failed: no image\n".utf8))
    exit(1)
}
try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL, UTType.png.identifier as CFString, 1, nil
) else { exit(2) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(3) }
print("wrote \(output.path) (\(image.width)x\(image.height))")
