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
                } else {
                    Color(red: 0.075, green: 0.085, blue: 0.115)
                }

                LinearGradient(colors: [Color.black.opacity(0.48), Color(red: 0.025, green: 0.035, blue: 0.065).opacity(0.52)], startPoint: .top, endPoint: .bottom)

                if contrast != .increased {
                    ambientGradient(in: geometry.size)
                        .opacity(reduceTransparency ? 0.42 : 0.78)
                }

                // Keep the physical camera area seamless while the glass opens below it.
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: min(1, notchHeight / max(1, geometry.size.height))),
                    .init(color: .clear, location: min(1, (notchHeight + 72) / max(1, geometry.size.height))),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ambientGradient(in size: CGSize) -> some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.48, green: 0.36, blue: 0.79).opacity(0.54))
                .frame(width: size.width * 0.95, height: size.height * 0.85)
                .position(x: size.width * 0.12, y: size.height * 0.60)
            Ellipse()
                .fill(Color(red: 0.20, green: 0.46, blue: 0.82).opacity(0.45))
                .frame(width: size.width * 0.82, height: size.height * 0.80)
                .position(x: size.width * 0.85, y: size.height * 0.46)
            Ellipse()
                .fill(Color(red: 0.12, green: 0.60, blue: 0.57).opacity(0.40))
                .frame(width: size.width * 0.75, height: size.height * 0.55)
                .position(x: size.width * 0.64, y: size.height * 1.02)
        }
        .compositingGroup()
        .blur(radius: 48)
    }
}

private struct HaloFrostedMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> HaloEffectView {
        let view = HaloEffectView()
        view.material = .hudWindow
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
