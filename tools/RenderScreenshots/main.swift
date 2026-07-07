import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import DrachmaCore
import DrachmaApp

// Renders README screenshots straight from the real views (Pulse playbook).
// Usage: swift run render-screenshots [output.png]

/// Deterministic fixture using the actual ECB reference rates of 2026-07-06,
/// captured during the MCP smoke test — so the screenshot is reproducible and
/// shows real numbers.
struct FixtureRates: RatesClient {
    func latestRates(base: String) async throws -> RatesSnapshot {
        RatesSnapshot(base: "USD", date: "2026-07-06", rates: [
            "EUR": Decimal(string: "0.87604")!,
            "KRW": Decimal(string: "1538.46")!,
            "CHF": Decimal(string: "0.80604")!,
            "CNY": Decimal(string: "6.7957")!,
            "CAD": Decimal(string: "1.4223")!,
            "AUD": Decimal(string: "1.4421")!,
        ])
    }

    func rates(on day: String, base: String) async throws -> RatesSnapshot {
        try await latestRates(base: base)
    }
}

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "docs/screenshots/converter.png")

let model = ConverterViewModel(ratesClient: FixtureRates())
await model.load()
model.amountText = "100"

let content = VStack(alignment: .leading, spacing: 0) {
    Text("Drachma")
        .font(.largeTitle.bold())
        .padding(.horizontal, 20)
        .padding(.top, 18)
    ConverterView(model: model, staticControls: true)
        .formStyle(.grouped)
}
.frame(width: 393, height: 330, alignment: .top)
.background(Color(nsColor: .windowBackgroundColor))

let renderer = ImageRenderer(content: content)
renderer.scale = 2

guard let image = renderer.cgImage else {
    FileHandle.standardError.write(Data("render failed: ImageRenderer produced no image\n".utf8))
    exit(1)
}

try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL, UTType.png.identifier as CFString, 1, nil
) else {
    FileHandle.standardError.write(Data("render failed: cannot create \(output.path)\n".utf8))
    exit(2)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("render failed: could not finalize PNG\n".utf8))
    exit(3)
}
print("wrote \(output.path) (\(image.width)x\(image.height))")
