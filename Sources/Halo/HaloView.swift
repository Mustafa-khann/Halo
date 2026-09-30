import AppKit
import SwiftUI

// Keep the stable property wrapper unambiguous with SDKs that also export a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

struct HaloShape: Shape {
    var topRadius: CGFloat = 10
    var bottomRadius: CGFloat = 26
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.height / 3)
        let b = min(bottomRadius, (rect.height - t) / 2)
        let left = t, right = rect.width - t
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addQuadCurve(to: CGPoint(x: right, y: t), control: CGPoint(x: right, y: 0))
        path.addLine(to: CGPoint(x: right, y: rect.height - b))
        path.addQuadCurve(to: CGPoint(x: right - b, y: rect.height), control: CGPoint(x: right, y: rect.height))
        path.addLine(to: CGPoint(x: left + b, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.height - b), control: CGPoint(x: left, y: rect.height))
        path.addLine(to: CGPoint(x: left, y: t))
        path.addQuadCurve(to: .zero, control: CGPoint(x: left, y: 0))
        path.closeSubpath()
        return path
    }
}

enum HaloPalette {
    static let surface = Color(red: 0.015, green: 0.015, blue: 0.018)
    static let card = Color.white.opacity(0.065)
    static let secondary = Color.white.opacity(0.48)
    static let accent = Color(red: 0.54, green: 0.72, blue: 1)
}

struct HaloButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(prominent ? Color.white : Color.white.opacity(configuration.isPressed ? 0.17 : 0.085), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
            .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.9))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

@MainActor struct HaloView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header.frame(height: model.geometry.notchHeight)
                if model.expanded {
                    expandedContent
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity))
                }
            }
            .frame(width: model.currentWidth, height: model.currentHeight, alignment: .top)
            .background(HaloPalette.surface)
            .clipShape(HaloShape(topRadius: model.expanded ? 12 : 5, bottomRadius: model.expanded ? 28 : 12))
            .overlay {
                if model.expanded {
                    HaloShape(topRadius: 12, bottomRadius: 28).strokeBorderFallback(Color.white.opacity(0.065))
                }
            }
            .shadow(color: .black.opacity(model.expanded ? 0.32 : 0), radius: 18, x: 0, y: 10)
            .contentShape(Rectangle())
            .onTapGesture { if !model.expanded { model.open(pin: true) } }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(model.reduceMotion ? .easeOut(duration: 0.08) : .spring(response: model.preferences.animationSpeed, dampingFraction: 0.86), value: model.expanded)
        .animation(model.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: model.compactActivity)
        .onChange(of: model.tabs) { _, tabs in if !tabs.contains(model.selectedTab) { model.selectedTab = .overview } }
    }

    private var header: some View {
        let wing = max(0, (model.currentWidth - model.geometry.notchWidth) / 2)
        return HStack(spacing: 0) {
            Group {
                if model.expanded {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.lefthalf.filled").font(.system(size: 11))
                        Text("Halo").font(.system(size: 11, weight: .medium))
                    }.foregroundStyle(.white.opacity(0.58))
                } else if model.compactActivity { compactLeading }
            }.frame(width: wing)
            Color.clear.frame(width: model.geometry.notchWidth)
            Group {
                if model.expanded {
                    HStack(spacing: 1) {
                        headerButton(model.pinned ? "pin.fill" : "pin", label: model.pinned ? "Unpin Halo" : "Keep Halo open") { model.pin() }
                        headerButton("gearshape", label: "Open Settings") { model.showSettings?() }
                        headerButton("xmark", label: "Close Halo") { model.close() }
                    }
                } else if model.compactActivity { compactTrailing }
            }.frame(width: wing)
        }
    }
    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                .frame(width: 25, height: 25).contentShape(Rectangle())
        }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.55)).help(label).accessibilityLabel(label)
    }
    @ViewBuilder private var compactLeading: some View {
        if model.chargingToast {
            Image(systemName: model.power.onAC ? "bolt.fill" : "battery.100percent").foregroundStyle(.green).font(.system(size: 14))
        } else if model.timer.active || model.timer.phase == .finished {
            Image(systemName: model.timer.phase == .finished ? "checkmark.circle.fill" : "timer").foregroundStyle(.orange).font(.system(size: 14))
        } else {
            ArtworkView(url: model.media.artworkURL, size: 21)
        }
    }
    @ViewBuilder private var compactTrailing: some View {
        if model.chargingToast {
            Text("\(model.power.percent)%").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.green)
        } else if model.timer.active || model.timer.phase == .finished {
            Text(model.timer.phase == .finished ? "Done" : clockString(model.timer.remaining(at: model.now)))
                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.orange)
        } else {
            Image(systemName: "waveform").font(.system(size: 15)).foregroundStyle(HaloPalette.accent)
        }
    }
    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(model.tabs) { tab in
                    Button { model.selectedTab = tab } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol).font(.system(size: 13, weight: .medium))
                            Text(tab.title).font(.system(size: 9, weight: .medium))
                        }.frame(maxWidth: .infinity).frame(height: 39)
                            .foregroundStyle(model.selectedTab == tab ? .white : HaloPalette.secondary)
                            .background(model.selectedTab == tab ? Color.white.opacity(0.085) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in if hovering { model.selectedTab = tab } }
                    .accessibilityLabel(tab.title).accessibilityAddTraits(model.selectedTab == tab ? [.isSelected] : [])
                }
            }.padding(.horizontal, 18).padding(.top, 7)
            Group {
                switch model.selectedTab {
                case .overview: OverviewView(model: model)
                case .music: MusicView(model: model)
                case .timer: TimerHaloView(model: model)
                case .power: PowerView(model: model)
                }
            }.padding(.horizontal, 24).frame(maxWidth: .infinity).frame(height: 174)
            HStack {
                Text(model.pinned ? "Pinned open" : "Here when you need it")
                Spacer()
                Text(model.preferences.shortcut.glyphs).fontDesign(.monospaced)
            }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.30)).padding(.horizontal, 26).padding(.top, 7)
        }
    }
}

private extension Shape {
    func strokeBorderFallback(_ color: Color) -> some View { stroke(color, lineWidth: 0.65) }
}

struct ArtworkView: View {
    var url: URL?
    var size: CGFloat
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack {
                LinearGradient(colors: [Color(red: 0.24, green: 0.32, blue: 0.55), Color(red: 0.12, green: 0.13, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}

@MainActor struct OverviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Mac. A little closer.").font(.system(size: 15, weight: .medium)).padding(.top, 4)
            HStack(spacing: 10) {
                if model.preferences.timerEnabled {
                    Button { model.selectedTab = .timer } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(model.timer.active ? model.timer.label : "A moment to focus", systemImage: "timer").font(.system(size: 11)).foregroundStyle(HaloPalette.secondary)
                            Text(model.timer.active ? clockString(model.timer.remaining(at: model.now)) : "25 min").font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                            Text(model.timer.active ? (model.timer.phase == .paused ? "Paused" : "In progress") : "Start a focus timer").font(.system(size: 10)).foregroundStyle(HaloPalette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
                            .background(HaloPalette.card, in: RoundedRectangle(cornerRadius: 15))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if !model.preferences.timerEnabled {
                    Text("Make Halo your own in Settings.").font(.system(size: 12)).foregroundStyle(HaloPalette.secondary).frame(height: 95)
                }
            }
            HStack(spacing: 13) {
                if model.preferences.musicEnabled {
                    Button { model.selectedTab = .music } label: {
                        Label(model.media.available ? model.media.title : "Music", systemImage: "music.note")
                            .lineLimit(1).padding(.vertical, 5).contentShape(Rectangle())
                    }
                }
                Spacer()
                Button { model.showSettings?() } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                        .padding(.vertical, 5).contentShape(Rectangle())
                }
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(HaloPalette.secondary)
        }
    }
}

@MainActor struct TimerHaloView: View {
    @ObservedObject var model: AppModel
    @ViewState private var minutes = 25
    var body: some View {
        VStack(spacing: 9) {
            Text(model.timer.phase == .finished ? "A moment well spent." : model.timer.active ? model.timer.label : "Make time for what matters.")
                .font(.system(size: 11)).foregroundStyle(HaloPalette.secondary)
            Text(model.timer.phase == .idle ? clockString(Double(minutes * 60)) : clockString(model.timer.remaining(at: model.now)))
                .font(.system(size: 43, weight: .light, design: .rounded)).monospacedDigit().contentTransition(.numericText())
            if model.timer.phase == .idle {
                HStack(spacing: 5) {
                    ForEach([5, 15, 25, 45], id: \.self) { preset in
                        Button("\(preset)m") { minutes = preset }
                            .font(.system(size: 11, weight: .medium)).frame(width: 43, height: 26)
                            .background(minutes == preset ? Color.white.opacity(0.17) : HaloPalette.card, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                    }
                    Stepper(value: $minutes, in: 1...180) { Text("\(minutes)m").font(.system(size: 10)).frame(width: 31) }.frame(width: 82)
                }
                Button { model.startTimer(minutes: minutes) } label: { Label("Start timer", systemImage: "play.fill") }.buttonStyle(HaloButtonStyle(prominent: true))
            } else if model.timer.phase == .finished {
                HStack {
                    Button("Done") { model.resetTimer() }.buttonStyle(HaloButtonStyle(prominent: true))
                    Button("Again") { model.startTimer(minutes: Int(model.timer.duration / 60)) }.buttonStyle(HaloButtonStyle())
                }
            } else {
                HStack(spacing: 9) {
                    Button { model.timer.phase == .running ? model.pauseTimer() : model.resumeTimer() } label: {
                        Label(model.timer.phase == .running ? "Pause" : "Resume", systemImage: model.timer.phase == .running ? "pause.fill" : "play.fill")
                    }.buttonStyle(HaloButtonStyle(prominent: true))
                    Button { model.resetTimer() } label: { Label("End", systemImage: "stop.fill") }.buttonStyle(HaloButtonStyle())
                }
            }
        }
    }
}

@MainActor struct MusicView: View {
    @ObservedObject var model: AppModel
    @ViewState private var seekPreview: Double?
    @ViewState private var seeking = false
    var body: some View {
        if model.media.available {
            VStack(spacing: 8) {
                HStack(spacing: 13) {
                    ArtworkView(url: model.media.artworkURL, size: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.media.title).font(.system(size: 14, weight: .medium)).lineLimit(1).help(model.media.title)
                        Text(model.media.artist).font(.system(size: 11)).foregroundStyle(HaloPalette.secondary).lineLimit(1)
                        Text(model.mediaControlError ?? model.media.provider.title)
                            .font(.system(size: 9)).foregroundStyle(model.mediaControlError == nil ? Color.white.opacity(0.3) : .orange)
                            .lineLimit(1).help(model.mediaControlError ?? model.media.provider.title)
                    }
                    Spacer(minLength: 0)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let position = min(seekPreview ?? model.media.elapsed(at: context.date), max(0, model.media.duration))
                    HStack(spacing: 9) {
                        Text(clockString(position)).frame(width: 32)
                        Slider(value: Binding(get: { position }, set: { value in
                            seekPreview = value
                            // Keyboard and accessibility changes commit without a drag session.
                            if !seeking { model.mediaService.seek(to: value, in: model.media) }
                        }), in: 0...max(1, model.media.duration), onEditingChanged: { editing in
                            seeking = editing
                            if editing { seekPreview = position }
                            else if let seekPreview { model.mediaService.seek(to: seekPreview, in: model.media) }
                        })
                        .labelsHidden().controlSize(.small).tint(.white.opacity(0.85))
                        .disabled(model.media.duration <= 0 || model.media.trackID.isEmpty)
                        .accessibilityLabel("Playback position")
                        .accessibilityValue("\(clockString(position)) of \(clockString(model.media.duration))")
                        .help("Drag to seek")
                        Text(clockString(model.media.duration)).frame(width: 32)
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(HaloPalette.secondary)
                }
                HStack(spacing: 27) {
                    musicButton("backward.end.fill", "Previous track") { model.mediaService.command(.previous) }
                    musicButton(model.media.playing ? "pause.fill" : "play.fill", model.media.playing ? "Pause" : "Play", large: true) { model.mediaService.command(.playpause) }
                    musicButton("forward.end.fill", "Next track") { model.mediaService.command(.next) }
                }
                SystemVolumeView(model: model)
            }
            .onChange(of: model.media.observedAt) { _, _ in
                if !seeking { seekPreview = nil }
            }
            .onChange(of: model.media.trackID) { _, _ in seekPreview = nil; seeking = false }
        } else {
            VStack(spacing: 8) {
                EmptyHaloState(symbol: "music.note", title: model.media.message == "Automation access is needed." ? "One small permission." : "Room for your music.", detail: model.media.message) {
                    if model.media.message == "Automation access is needed." {
                        Button("Open Privacy Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }.buttonStyle(HaloButtonStyle())
                    } else {
                        Button("Open player") { model.mediaService.openPlayer() }.buttonStyle(HaloButtonStyle())
                        Button("Refresh") { model.mediaService.refresh() }.buttonStyle(HaloButtonStyle())
                    }
                }
                SystemVolumeView(model: model)
            }
        }
    }
    private func musicButton(_ symbol: String, _ label: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: large ? 20 : 14))
                .frame(width: large ? 42 : 30, height: 36).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}

@MainActor struct SystemVolumeView: View {
    @ObservedObject var model: AppModel
    @ViewState private var preview: Double?
    @ViewState private var adjusting = false
    private var value: Double { preview ?? model.systemVolume.displayedVolume }
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: value == 0 ? "speaker.slash.fill" : "speaker.fill")
                .font(.system(size: 10)).frame(width: 16).accessibilityHidden(true)
            Slider(value: Binding(get: { value }, set: { volume in
                preview = volume
                model.volumeService.setVolume(volume)
            }), in: 0...100, onEditingChanged: { editing in
                adjusting = editing
                if !editing { preview = nil }
            })
            .labelsHidden().controlSize(.small).tint(.white.opacity(0.85))
            .disabled(!model.systemVolume.available)
            .accessibilityLabel("System volume")
            .accessibilityValue(model.systemVolume.available ? "\(Int(value.rounded())) percent" : "Unavailable for this output")
            .help(model.systemVolume.help)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).accessibilityHidden(true)
            Text(model.systemVolume.available ? "\(Int(value.rounded()))%" : "—")
                .font(.system(size: 9, design: .monospaced)).monospacedDigit().frame(width: 30, alignment: .trailing)
        }
        .frame(height: 22).foregroundStyle(HaloPalette.secondary)
        .onChange(of: model.systemVolume) { _, _ in if !adjusting { preview = nil } }
        .onChange(of: model.systemVolume.outputID) { _, _ in preview = nil; adjusting = false }
    }
}

@MainActor struct PowerView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.power.available ? "\(model.power.percent)%" : "—").font(.system(size: 42, weight: .light, design: .rounded))
                    Text(model.power.status).font(.system(size: 12)).foregroundStyle(HaloPalette.secondary)
                }
                Spacer()
                Image(systemName: model.power.symbol).font(.system(size: 36, weight: .light)).foregroundStyle(model.power.percent <= 20 && !model.power.onAC ? .orange : .green)
            }
            ProgressView(value: Double(model.power.percent), total: 100).tint(model.power.percent <= 20 && !model.power.onAC ? .orange : .green)
            HStack {
                Text(model.power.minutesToFull.map { "About \($0) min to full" } ?? "Updates automatically with your Mac.").font(.system(size: 10)).foregroundStyle(HaloPalette.secondary)
                Spacer()
            }
            Button("Battery Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!) }.buttonStyle(HaloButtonStyle())
        }
    }
}

struct EmptyHaloState<Actions: View>: View {
    var symbol: String
    var title: String
    var detail: String
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light)).foregroundStyle(HaloPalette.secondary)
            Text(title).font(.system(size: 14, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(HaloPalette.secondary).multilineTextAlignment(.center).lineLimit(3)
            HStack(spacing: 8, content: actions).padding(.top, 3)
        }.frame(maxWidth: .infinity)
    }
}
