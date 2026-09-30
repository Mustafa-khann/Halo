import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

@MainActor struct HaloView: View {
    @ObservedObject var model: AppModel
    @Namespace private var navigation
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var reduceMotion: Bool { model.preferences.respectReduceMotion && (systemReduceMotion || model.reduceMotion) }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header.frame(height: model.geometry.notchHeight)
                if model.expanded {
                    expandedContent
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: -5)), removal: .opacity))
                }
            }
            .frame(width: model.currentWidth, height: model.currentHeight, alignment: .top)
            .background {
                if model.expanded {
                    HaloBackground(notchHeight: model.geometry.notchHeight)
                } else {
                    HaloPalette.surface
                }
            }
            .clipShape(HaloShape(topRadius: model.expanded ? HaloLayout.topRadius : 5, bottomRadius: model.expanded ? HaloLayout.bottomRadius : 12))
            .overlay {
                if model.expanded {
                    HaloGlassEdge(notchHeight: model.geometry.notchHeight)
                }
                if model.preferences.filesEnabled && model.fileShelf.draggingOver {
                    HaloShape(topRadius: HaloLayout.topRadius, bottomRadius: HaloLayout.bottomRadius).stroke(HaloPalette.accent, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(model.expanded ? 0.2 : 0), radius: 24, x: 0, y: 12)
            .shadow(color: .black.opacity(model.expanded ? 0.22 : 0), radius: 4, x: 0, y: 3)
            .contentShape(Rectangle())
            .onTapGesture { if !model.expanded { model.open(pin: true) } }
            .onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { model.fileShelf.draggingOver }, set: { model.fileShelf.draggingOver = $0 })) { providers in
                model.preferences.filesEnabled && model.fileShelf.acceptDrop(providers)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .environment(\.haloReduceMotion, reduceMotion)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: model.preferences.animationSpeed, dampingFraction: 0.86), value: model.expanded)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: model.compactActivity)
        .onChange(of: model.tabs) { _, tabs in if !tabs.contains(model.selectedTab) { model.selectedTab = .overview } }
        .onChange(of: model.fileShelf.draggingOver) { _, over in
            if over && model.preferences.filesEnabled { model.open(tab: .files) }
        }
    }

    private var header: some View {
        let wing = max(0, (model.currentWidth - model.geometry.notchWidth) / 2)
        return HStack(spacing: 0) {
            Group {
                if model.expanded {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.lefthalf.filled").font(.system(size: 11))
                        Text("Halo").font(.system(size: 12, weight: .semibold))
                    }.foregroundStyle(HaloPalette.secondary)
                } else if model.compactActivity { compactLeading }
            }.frame(width: wing)
            Color.clear.frame(width: model.geometry.notchWidth)
            Group {
                if model.expanded {
                    HStack(spacing: 0) {
                        headerButton(model.pinned ? "pin.fill" : "pin", label: model.pinned ? "Unpin Halo" : "Keep Halo open") { model.pin() }
                        headerButton("gearshape", label: "Open Settings") { model.showSettings?() }
                        headerButton("xmark", label: "Close Halo") { model.close() }
                    }
                } else if model.compactActivity { compactTrailing }
            }.padding(.trailing, model.expanded ? HaloLayout.topRadius : 0).frame(width: wing)
        }
    }
    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                .contentShape(Rectangle())
        }
            .buttonStyle(HaloIconButtonStyle(size: 26)).help(label).accessibilityLabel(label)
    }
    @ViewBuilder private var compactLeading: some View {
        if model.chargingToast {
            Image(systemName: model.power.onAC ? "bolt.fill" : "battery.100percent").foregroundStyle(.green).font(.system(size: 14))
        } else if model.timer.active || model.timer.phase == .finished {
            Image(systemName: model.timer.phase == .finished ? "checkmark.circle.fill" : "timer").foregroundStyle(.orange).font(.system(size: 14))
        } else if model.keepAwake.session.active {
            Image(systemName: "cup.and.saucer.fill").foregroundStyle(HaloPalette.accent).font(.system(size: 14))
        } else {
            ArtworkView(url: model.media.artworkURL, data: model.media.artworkData, size: 21)
        }
    }
    @ViewBuilder private var compactTrailing: some View {
        if model.chargingToast {
            Text("\(model.power.percent)%").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.green)
        } else if model.timer.active || model.timer.phase == .finished {
            Text(model.timer.phase == .finished ? "Done" : clockString(model.timer.remaining(at: model.now)))
                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.orange)
        } else if model.keepAwake.session.active {
            Text(model.keepAwake.session.remaining(at: model.keepAwake.now).map { clockString($0) } ?? "Awake")
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(HaloPalette.accent)
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
                            Image(systemName: tab.symbol).font(.system(size: 12, weight: .medium))
                            Text(tab.title).font(.system(size: 10, weight: .medium))
                        }.frame(maxWidth: .infinity).frame(height: 36)
                            .foregroundStyle(model.selectedTab == tab ? .white : .white.opacity(contrast == .increased ? 0.74 : 0.62))
                            .background {
                                if model.selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.065)], startPoint: .top, endPoint: .bottom))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(contrast == .increased ? 0.32 : 0.10), lineWidth: 0.5))
                                        .matchedGeometryEffect(id: "selectedTab", in: navigation)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HaloTileButtonStyle(radius: 12))
                    .onHover { hovering in if hovering { model.selectedTab = tab } }
                    .accessibilityLabel(tab.title).accessibilityAddTraits(model.selectedTab == tab ? [.isSelected] : [])
                }
            }.padding(3).frame(height: 42)
                .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.horizontal, HaloLayout.contentInset).padding(.top, 6).padding(.bottom, 10)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.selectedTab)
            Group {
                switch model.selectedTab {
                case .overview: OverviewView(model: model)
                case .music: MusicView(model: model)
                case .timer: TimerHaloView(model: model)
                case .files: FileShelfView(shelf: model.fileShelf)
                case .awake: KeepAwakeView(service: model.keepAwake)
                case .power: PowerView(model: model)
                }
            }.padding(.horizontal, HaloLayout.contentInset).frame(maxWidth: .infinity).frame(height: HaloLayout.contentHeight)
            HStack {
                Label(model.pinned ? "Pinned" : "Hover to open", systemImage: model.pinned ? "pin.fill" : "cursorarrow")
                Spacer()
                Text(model.preferences.shortcut.glyphs).font(.system(size: 9, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }.font(.system(size: 10)).foregroundStyle(contrast == .increased ? HaloPalette.secondary : HaloPalette.tertiary).frame(height: 14)
                .padding(.horizontal, HaloLayout.contentInset).padding(.top, 8).padding(.bottom, 6)
        }
    }
}

struct ArtworkView: View {
    var url: URL?
    var data: Data? = nil
    var size: CGFloat
    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else { remoteArtwork }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false))
    }
    private var remoteArtwork: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack {
                LinearGradient(colors: [Color(red: 0.24, green: 0.32, blue: 0.55), Color(red: 0.12, green: 0.13, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

@MainActor struct OverviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("At a glance").font(.system(size: 17, weight: .semibold))
                Spacer()
                if model.keepAwake.session.active {
                    Button { model.selectedTab = .awake } label: {
                        Label("Awake", systemImage: "cup.and.saucer.fill").font(.system(size: 10, weight: .medium))
                    }.buttonStyle(HaloButtonStyle()).help("View Keep awake")
                }
            }.frame(height: 24)
            HStack(spacing: 10) {
                if model.preferences.timerEnabled {
                    overviewCard("Focus", symbol: "timer", tint: HaloPalette.orange,
                                 value: model.timer.active ? clockString(model.timer.remaining(at: model.now)) : "25 min",
                                 detail: model.timer.active ? (model.timer.phase == .paused ? "Paused" : "In progress") : "A moment for you", tab: .timer)
                }
                if model.preferences.filesEnabled {
                    overviewCard("File shelf", symbol: "tray", tint: HaloPalette.accent,
                                 value: model.fileShelf.state.files.isEmpty ? "Drop files" : "\(model.fileShelf.state.files.count) \(model.fileShelf.state.files.count == 1 ? "file" : "files")",
                                 detail: "Always within reach", tab: .files)
                }
                if !model.preferences.timerEnabled && !model.preferences.filesEnabled {
                    Button { model.showSettings?() } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Make room for your day.").font(.system(size: 14, weight: .medium))
                            Text("Choose your activities in Settings.").font(.system(size: 11)).foregroundStyle(HaloPalette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 108).haloCard()
                    }.buttonStyle(HaloTileButtonStyle())
                }
            }
            if model.preferences.musicEnabled {
                Button { model.selectedTab = .music } label: {
                    HStack(spacing: 10) {
                        ArtworkView(url: model.media.artworkURL, data: model.media.artworkData, size: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.media.available ? model.media.title : "Now playing, right here").font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(model.media.available ? model.media.artist : "Music, podcasts, and video").font(.system(size: 11)).foregroundStyle(HaloPalette.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: model.media.playing ? "waveform" : "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(HaloPalette.secondary)
                    }.padding(.horizontal, 10).frame(height: 48).haloCard(radius: 14).contentShape(Rectangle())
                }.buttonStyle(HaloTileButtonStyle(radius: 14)).accessibilityLabel("Open Media")
            } else {
                Button { model.showSettings?() } label: {
                    Label("Customize your Halo", systemImage: "slider.horizontal.3")
                }.buttonStyle(HaloButtonStyle()).frame(maxWidth: .infinity)
            }
        }
    }
    private func overviewCard(_ title: String, symbol: String, tint: Color, value: String, detail: String, tab: HaloTab) -> some View {
        Button { model.selectedTab = tab } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).foregroundStyle(tint)
                    Text(title).foregroundStyle(HaloPalette.secondary)
                }.font(.system(size: 11, weight: .medium))
                Text(value).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                Text(detail).font(.system(size: 11)).foregroundStyle(HaloPalette.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).frame(height: 108)
                .haloCard().contentShape(Rectangle())
        }.buttonStyle(HaloTileButtonStyle())
    }
}

@MainActor struct TimerHaloView: View {
    @ObservedObject var model: AppModel
    @ViewState private var minutes = 25
    private var progress: Double {
        guard model.timer.phase != .idle else { return 0 }
        return min(1, max(0, 1 - model.timer.remaining(at: model.now) / max(1, model.timer.duration)))
    }
    private var tint: Color { model.timer.phase == .finished ? HaloPalette.green : HaloPalette.orange }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(model.timer.active ? model.timer.label : "Focus timer").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(model.timer.phase == .finished ? "Complete" : model.timer.phase == .paused ? "Paused" : model.timer.active ? "In progress" : "Time for yourself")
                    .font(.system(size: 11)).foregroundStyle(HaloPalette.secondary)
            }
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(tint.opacity(0.13), lineWidth: 4)
                    Circle().trim(from: 0, to: progress).stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: model.timer.phase == .finished ? "checkmark" : "timer").font(.system(size: 25, weight: .light)).foregroundStyle(tint)
                }.frame(width: 66, height: 66).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.timer.phase == .idle ? clockString(Double(minutes * 60)) : clockString(model.timer.remaining(at: model.now)))
                        .font(.system(size: 48, weight: .regular, design: .rounded)).monospacedDigit()
                        .contentTransition(model.reduceMotion ? .identity : .numericText())
                    Text(model.timer.phase == .finished ? "A moment well spent." : "One thing at a time.").font(.system(size: 11)).foregroundStyle(HaloPalette.secondary)
                }
            }.frame(maxWidth: .infinity).frame(height: 76)
            if model.timer.phase == .idle {
                HStack(spacing: 5) {
                    ForEach([5, 15, 25, 45], id: \.self) { preset in
                        Button("\(preset)m") { minutes = preset }.buttonStyle(HaloChoiceStyle(selected: minutes == preset))
                            .accessibilityAddTraits(minutes == preset ? [.isSelected] : [])
                    }
                    Stepper(value: $minutes, in: 1...180) {
                        Text("\(minutes)m").font(.system(size: 11)).monospacedDigit().frame(width: 33)
                    }.frame(width: 84).controlSize(.small).accessibilityLabel("Custom timer duration")
                }
                Button { model.startTimer(minutes: minutes) } label: { Label("Start timer", systemImage: "play.fill") }.buttonStyle(HaloButtonStyle(prominent: true))
            } else if model.timer.phase == .finished {
                HStack(spacing: 8) {
                    Button("Done") { model.resetTimer() }.buttonStyle(HaloButtonStyle(prominent: true))
                    Button("Again") { model.startTimer(minutes: Int(model.timer.duration / 60)) }.buttonStyle(HaloButtonStyle())
                }
            } else {
                HStack(spacing: 8) {
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
            VStack(spacing: 10) {
                HStack(spacing: 13) {
                    ArtworkView(url: model.media.artworkURL, data: model.media.artworkData, size: 64)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.media.title).font(.system(size: 15, weight: .semibold)).lineLimit(1).help(model.media.title)
                        Text(model.media.artist).font(.system(size: 12)).foregroundStyle(HaloPalette.secondary).lineLimit(1)
                        Text(model.mediaControlError ?? model.media.playerName)
                            .font(.system(size: 11)).foregroundStyle(model.mediaControlError == nil ? HaloPalette.tertiary : HaloPalette.orange)
                            .lineLimit(1).help(model.mediaControlError ?? model.media.playerName)
                    }
                    Spacer(minLength: 0)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let position = seekPreview ?? model.media.elapsed(at: context.date)
                    HStack(spacing: 9) {
                        if model.media.canSeek {
                            Text(clockString(position)).frame(minWidth: 36, alignment: .leading)
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
                            .disabled(!model.media.canSeek)
                            .accessibilityLabel("Playback position")
                            .accessibilityValue("\(clockString(position)) of \(clockString(model.media.duration))")
                            .help("Drag to seek")
                            Text("−" + clockString(max(0, model.media.duration - position))).frame(minWidth: 42, alignment: .trailing)
                        } else {
                            Text("Now Playing").foregroundStyle(HaloPalette.tertiary)
                            Spacer()
                            Text(clockString(position))
                        }
                    }.font(.system(size: 10, design: .monospaced)).foregroundStyle(HaloPalette.secondary)
                }
                HStack(spacing: 24) {
                    musicButton(model.media.skipBackward ? "gobackward.15" : "backward.end.fill", model.media.skipBackward ? "Back 15 seconds" : "Previous track") { model.mediaService.command(.previous) }
                        .disabled(model.media.prohibitsSkip && !model.media.skipBackward)
                    musicButton(model.media.playing ? "pause.fill" : "play.fill", model.media.playing ? "Pause" : "Play", large: true) { model.mediaService.command(.playpause) }
                    musicButton(model.media.skipForward ? "goforward.15" : "forward.end.fill", model.media.skipForward ? "Forward 15 seconds" : "Next track") { model.mediaService.command(.next) }
                        .disabled(model.media.prohibitsSkip && !model.media.skipForward)
                }
                SystemVolumeView(model: model).padding(.top, 2)
            }
            .onChange(of: model.media.observedAt) { _, _ in
                if !seeking { seekPreview = nil }
            }
            .onChange(of: model.media.trackID) { _, _ in seekPreview = nil; seeking = false }
        } else {
            VStack(spacing: 8) {
                EmptyHaloState(symbol: "music.note", title: model.media.message == "Automation access is needed." ? "Connect your player" : "Now playing, right here", detail: model.media.message) {
                    if model.media.message == "Automation access is needed." {
                        Button("Open Privacy Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }.buttonStyle(HaloButtonStyle())
                    } else {
                        if model.preferences.musicProvider != .automatic {
                            Button("Open player") { model.mediaService.openPlayer() }.buttonStyle(HaloButtonStyle())
                        }
                        Button("Refresh") { model.mediaService.refresh() }.buttonStyle(HaloButtonStyle())
                    }
                }
                SystemVolumeView(model: model)
            }
        }
    }
    private func musicButton(_ symbol: String, _ label: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: large ? 18 : 15, weight: .semibold))
                .offset(x: large && symbol == "play.fill" ? 1 : 0).contentShape(Rectangle())
        }.buttonStyle(HaloIconButtonStyle(prominent: large, size: large ? 42 : 36)).accessibilityLabel(label).help(label)
    }
}

@MainActor struct SystemVolumeView: View {
    @ObservedObject var model: AppModel
    @ViewState private var preview: Double?
    @ViewState private var adjusting = false
    private var value: Double { preview ?? model.systemVolume.displayedVolume }
    var body: some View {
        VStack(spacing: 5) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
            HStack {
                Text("System volume")
                Spacer()
                Text(model.systemVolume.available ? "\(Int(value.rounded()))%" : "Unavailable").monospacedDigit()
            }.font(.system(size: 10)).foregroundStyle(HaloPalette.secondary)
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
            }
        }
        .foregroundStyle(HaloPalette.secondary)
        .onChange(of: model.systemVolume) { _, _ in if !adjusting { preview = nil } }
        .onChange(of: model.systemVolume.outputID) { _, _ in preview = nil; adjusting = false }
    }
}

@MainActor struct PowerView: View {
    @ObservedObject var model: AppModel
    private var tint: Color {
        !model.power.available ? HaloPalette.secondary : model.power.percent <= 20 && !model.power.onAC ? HaloPalette.orange : HaloPalette.green
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(model.power.available ? "\(model.power.percent)" : "—")
                            .font(.system(size: 48, weight: .regular, design: .rounded)).monospacedDigit()
                        if model.power.available { Text("%").font(.system(size: 23, weight: .regular, design: .rounded)).foregroundStyle(HaloPalette.secondary) }
                    }.accessibilityElement(children: .ignore).accessibilityLabel(model.power.available ? "Battery \(model.power.percent) percent" : "Battery unavailable")
                    Text(model.power.status).font(.system(size: 12)).foregroundStyle(HaloPalette.secondary)
                }
                Spacer()
                HStack(spacing: 3) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.42), lineWidth: 2)
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint)
                            .frame(width: model.power.available ? max(4, 96 * CGFloat(model.power.percent) / 100) : 0, height: 34).padding(.leading, 8)
                        if model.power.charging {
                            Image(systemName: "bolt.fill").font(.system(size: 23, weight: .semibold)).foregroundStyle(model.power.percent > 50 ? Color.black.opacity(0.7) : .white).frame(maxWidth: .infinity)
                        }
                    }.frame(width: 112, height: 50)
                    Capsule().fill(tint.opacity(0.42)).frame(width: 4, height: 18)
                }.accessibilityHidden(true)
            }
            HStack(spacing: 16) {
                batteryDetail("Power source", value: model.power.available ? (model.power.onAC ? "Power adapter" : "Battery") : "Unavailable")
                Rectangle().fill(.white.opacity(0.09)).frame(width: 0.5, height: 30)
                batteryDetail(model.power.minutesToFull == nil ? "Status" : "Full in", value: model.power.minutesToFull.map { "About \($0) min" } ?? (model.power.charging ? "Charging" : model.power.onAC ? "Connected" : "Discharging"))
            }.padding(.horizontal, 15).frame(height: 60).haloCard()
            Button("Battery Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!) }.buttonStyle(HaloButtonStyle())
        }
    }
    private func batteryDetail(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(HaloPalette.secondary)
            Text(model.power.available ? value : "Unavailable").font(.system(size: 12, weight: .medium)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyHaloState<Actions: View>: View {
    var symbol: String
    var title: String
    var detail: String
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: 8) {
            HaloSymbolBadge(symbol: symbol, size: 40)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(HaloPalette.secondary).multilineTextAlignment(.center).lineLimit(3)
            HStack(spacing: 8, content: actions).padding(.top, 3)
        }.frame(maxWidth: .infinity)
    }
}
