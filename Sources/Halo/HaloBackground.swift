import AppKit
import SwiftUI

struct HaloBackground: View {
    var notchHeight: CGFloat
    var showsMaterial = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if showsMaterial && !reduceTransparency && contrast != .increased {
                    HaloFrostedMaterial()
                    // A neutral wash keeps controls legible without adding a fixed hue.
                    Color.black.opacity(0.10)
                } else {
                    HaloPalette.surface
                }

                // Keep the physical camera area seamless while the glass opens below it.
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: min(1, notchHeight / max(1, geometry.size.height))),
                    .init(color: .clear, location: min(1, (notchHeight + 36) / max(1, geometry.size.height))),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HaloFrostedMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> HaloEffectView {
        let view = HaloEffectView()
        view.material = .underWindowBackground
        // Let macOS blur the live windows or wallpaper underneath this panel.
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: HaloEffectView, context: Context) {}
}

private final class HaloEffectView: NSVisualEffectView {
    private var maskSize = CGSize.zero

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard bounds.size != maskSize, bounds.width > 0, bounds.height > 0 else { return }
        maskSize = bounds.size
        // Native backdrop materials also need a mask to respect the notch's shoulders.
        maskImage = NSImage(size: maskSize, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(HaloShape(topRadius: HaloLayout.topRadius, bottomRadius: HaloLayout.bottomRadius).path(in: rect).cgPath)
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()
            return true
        }
    }
}
