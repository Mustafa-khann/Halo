import SwiftUI

private struct HaloReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var haloReduceMotion: Bool? {
        get { self[HaloReduceMotionKey.self] }
        set { self[HaloReduceMotionKey.self] = newValue }
    }
}

enum HaloLayout {
    static let expandedBodyHeight: CGFloat = 300
    static let contentHeight: CGFloat = 214
    static let panelInset: CGFloat = 64
    static let topRadius: CGFloat = 12
    static let bottomRadius: CGFloat = 30
}

enum HaloPalette {
    static let surface = Color(red: 0.012, green: 0.012, blue: 0.014)
    static let card = Color.white.opacity(0.065)
    static let secondary = Color.white.opacity(0.64)
    static let tertiary = Color.white.opacity(0.43)
    static let accent = Color(red: 0.57, green: 0.76, blue: 1)
    static let green = Color(red: 0.48, green: 0.87, blue: 0.62)
    static let orange = Color(red: 1, green: 0.72, blue: 0.40)
}

struct HaloCard: ViewModifier {
    var radius: CGFloat = 18
    var highlighted = false
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(highlighted ? 0.13 : 0.085), .white.opacity(highlighted ? 0.08 : 0.045)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(contrast == .increased ? 0.32 : 0.07), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func haloCard(radius: CGFloat = 18, highlighted: Bool = false) -> some View {
        modifier(HaloCard(radius: radius, highlighted: highlighted))
    }
}

struct HaloButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        HaloControlSurface(pressed: configuration.isPressed, prominent: prominent) {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 16).frame(height: 34)
        }
    }
}

struct HaloIconButtonStyle: ButtonStyle {
    var prominent = false
    var size: CGFloat = 30
    func makeBody(configuration: Configuration) -> some View {
        HaloControlSurface(pressed: configuration.isPressed, prominent: prominent, quiet: true) {
            configuration.label.frame(width: size, height: size)
        }
    }
}

struct HaloTileButtonStyle: ButtonStyle {
    var radius: CGFloat = 18
    func makeBody(configuration: Configuration) -> some View {
        HaloTileSurface(pressed: configuration.isPressed, radius: radius) { configuration.label }
    }
}

private struct HaloTileSurface<Content: View>: View {
    var pressed: Bool
    var radius: CGFloat
    @ViewBuilder var content: () -> Content
    @ViewState private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.haloReduceMotion) private var appReduceMotion
    private var reduceMotion: Bool { appReduceMotion ?? systemReduceMotion }
    var body: some View {
        content()
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.white.opacity(pressed ? 0.08 : hovering ? 0.04 : 0)).allowsHitTesting(false))
            .contentShape(Rectangle())
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
    }
}

private struct HaloControlSurface<Content: View>: View {
    var pressed: Bool
    var prominent: Bool
    var quiet = false
    @ViewBuilder var content: () -> Content
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.haloReduceMotion) private var appReduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var reduceMotion: Bool { appReduceMotion ?? systemReduceMotion }
    var body: some View {
        content()
            .foregroundStyle(prominent ? Color.black : Color.white.opacity(quiet && !hovering ? 0.65 : 0.94))
            .background {
                Capsule().fill(prominent ? Color.white.opacity(pressed ? 0.8 : hovering ? 0.94 : 1) : Color.white.opacity(pressed ? 0.17 : hovering ? 0.12 : quiet ? 0 : 0.075))
            }
            .overlay {
                Capsule().strokeBorder(.white.opacity(prominent || quiet ? 0 : contrast == .increased ? 0.32 : 0.08), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
    }
}

struct HaloSymbolBadge: View {
    var symbol: String
    var tint: Color = HaloPalette.accent
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct HaloChoiceStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .frame(maxWidth: .infinity).frame(height: 30)
            .foregroundStyle(selected ? .white : HaloPalette.secondary)
            .background(.white.opacity(configuration.isPressed ? 0.2 : selected ? 0.14 : 0.045), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.12 : 0.04), lineWidth: 0.5))
            .contentShape(Rectangle())
    }
}
