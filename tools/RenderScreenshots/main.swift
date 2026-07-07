import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import DrachmaCore
import DrachmaApp

// Renders README screenshots straight from the real views (Pulse playbook).
// Usage: swift run render-screenshots [output-directory]

/// Deterministic fixture using the actual ECB reference rates of 2026-07-06,
/// captured during the MCP smoke test — so the screenshots are reproducible
/// and show real numbers.
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

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "docs/screenshots")

let model = ConverterViewModel(ratesClient: FixtureRates())
await model.load()
model.amountText = "100"

@MainActor
func render(scheme: ColorScheme, to url: URL) throws {
    let content = VStack(alignment: .leading, spacing: 0) {
        Text("Drachma")
            .font(.largeTitle.bold())
            .padding(.horizontal, 20)
            .padding(.top, 18)
        ConverterView(model: model, staticControls: true)
    }
    .frame(width: 393, height: 330, alignment: .top)
    .background(scheme == .dark ? Color(white: 0.11) : Color(white: 0.96))
    .environment(\.colorScheme, scheme)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2

    guard let image = renderer.cgImage else {
        throw RenderError.noImage
    }
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw RenderError.cannotWrite(url.path)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw RenderError.cannotWrite(url.path)
    }
    print("wrote \(url.path) (\(image.width)x\(image.height))")
}

enum RenderError: Error {
    case noImage
    case cannotWrite(String)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try render(scheme: .light, to: outputDirectory.appendingPathComponent("converter.png"))
try render(scheme: .dark, to: outputDirectory.appendingPathComponent("converter-dark.png"))
