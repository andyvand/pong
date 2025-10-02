import SwiftUI

// MARK: - PongIconView
// A scalable, resolution-independent Pong-themed icon.
// Use with any square size (e.g., 1024 for App Store asset generation).
struct PongIconView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let s = min(w, h)

            ZStack {
                // Background superellipse-like rounded rectangle
                RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.black, Color.black.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        // Subtle inner stroke for depth
                        RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: s * 0.02)
                            .blendMode(.overlay)
                    )
                    .shadow(color: .black.opacity(0.25), radius: s * 0.06, x: 0, y: s * 0.03)

                // Soft vignette
                RadialGradient(colors: [Color.white.opacity(0.08), .clear],
                               center: .topLeading,
                               startRadius: s * 0.05,
                               endRadius: s * 0.8)
                    .clipShape(RoundedRectangle(cornerRadius: s * 0.22, style: .continuous))

                // Center dashed net line
                VStack(spacing: s * 0.02) {
                    ForEach(0..<24, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(0.32))
                            .frame(width: s * 0.02, height: s * 0.045)
                    }
                }

                // Paddles and ball
                let paddleWidth = s * 0.06
                let paddleHeight = s * 0.36
                let inset = s * 0.12
                let ballSize = s * 0.08

                // Left (AI) paddle
                RoundedRectangle(cornerRadius: paddleWidth * 0.4, style: .continuous)
                    .fill(Color.white)
                    .frame(width: paddleWidth, height: paddleHeight)
                    .position(x: inset + paddleWidth / 2, y: h * 0.5)
                    .shadow(color: .white.opacity(0.25), radius: s * 0.02, x: 0, y: 0)

                // Right (Player) paddle
                RoundedRectangle(cornerRadius: paddleWidth * 0.4, style: .continuous)
                    .fill(Color.white)
                    .frame(width: paddleWidth, height: paddleHeight)
                    .position(x: w - inset - paddleWidth / 2, y: h * 0.56)
                    .shadow(color: .white.opacity(0.25), radius: s * 0.02, x: 0, y: 0)

                // Ball
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: ballSize, height: ballSize)
                        .shadow(color: .white.opacity(0.7), radius: s * 0.03)
                    // Subtle highlight
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: ballSize * 0.45)
                        .offset(x: -ballSize * 0.18, y: -ballSize * 0.18)
                        .blur(radius: s * 0.003)
                }
                .position(x: w * 0.55, y: h * 0.42)

                // Suggestion of motion path (a few faint dashes)
                Group {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: s * 0.09, height: s * 0.012)
                        .rotationEffect(.degrees(-24))
                        .position(x: w * 0.50, y: h * 0.46)
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: s * 0.07, height: s * 0.01)
                        .rotationEffect(.degrees(-24))
                        .position(x: w * 0.46, y: h * 0.49)
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: s * 0.05, height: s * 0.008)
                        .rotationEffect(.degrees(-24))
                        .position(x: w * 0.42, y: h * 0.515)
                }

                // Soft inner glow at bottom for depth
                LinearGradient(colors: [Color.white.opacity(0.08), .clear], startPoint: .bottom, endPoint: .top)
                    .mask(
                        RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                            .stroke(lineWidth: s * 0.12)
                            .blur(radius: s * 0.06)
                    )
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Pong Icon")
    }
}

// MARK: - Renderer
// Helper to export the icon to PNG data or a temporary file URL using SwiftUI's ImageRenderer.
@MainActor
enum PongIconRenderer {
    static func pngData(size: CGFloat = 1024) -> Data? {
        let view = PongIconView()
            .frame(width: size, height: size)
            .drawingGroup() // ensure vector to raster at high quality

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1 // size already accounts for pixel dimensions in points; adjust if needed

        return nil
    }

    static func writePNG(to url: URL, size: CGFloat = 1024) throws {
        guard let data = pngData(size: size) else { throw ExportError.renderFailed }
        try data.write(to: url, options: .atomic)
    }

    static func writePNGToTemporary(size: CGFloat = 1024, fileName: String = "PongIcon.png") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try writePNG(to: url, size: size)
        return url
    }

    enum ExportError: Error { case renderFailed }
}
