import AppKit
import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, activities, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .activities: return "Activities"
        case .about: return "About Halo"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .activities: return "square.stack.3d.up"
        case .about: return "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "A small space that feels right at home."
        case .appearance: return "Fine-tune the feeling."
        case .activities: return "Bring the things you love a little closer."
        case .about: return "Made for the space above everything else."
        }
    }
}

@MainActor struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ViewState private var page: SettingsPage? = .general
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var startupError: String?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage()).resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Halo").font(.system(size: 17, weight: .semibold))
                        Text("A little more Mac.").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    }
                    Spacer()
                }.padding(.horizontal, 17).padding(.top, 24).padding(.bottom, 22)
                List(SettingsPage.allCases, selection: $page) { item in
                    Label(item.title, systemImage: item.symbol).font(.system(size: 13)).padding(.vertical, 4).tag(item)
                }.listStyle(.sidebar)
                HStack { Text(model.preferences.shortcut.glyphs).font(.system(size: 10, design: .monospaced)); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0") }
                    .font(.system(size: 10)).foregroundStyle(.tertiary).padding(19)
            }.navigationSplitViewColumnWidth(min: 185, ideal: 195, max: 210)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text((page ?? .general).title).font(.system(size: 26, weight: .semibold))
                    Text((page ?? .general).subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 18)
                switch page ?? .general {
                case .general: general
                case .appearance: appearance
                case .activities: activities
                case .about: about
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.open(pin: true, tab: .overview) } label: { Label("Show Halo", systemImage: "viewfinder") }.help("Show Halo · \(model.preferences.shortcut.title)")
            }
        }
        .frame(minWidth: 740, minHeight: 550)
    }
    private func preference<Value>(_ key: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(get: { model.preferences[keyPath: key] }, set: { model.preferences[keyPath: key] = $0 })
    }

    private var general: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "cursorarrow.rays").font(.system(size: 24, weight: .light)).foregroundStyle(.tint).frame(width: 42)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Meet your Halo.").font(.system(size: 15, weight: .medium))
                        Text("Hover at the camera notch or press \(model.preferences.shortcut.title). A little room for your music, your focus, and whatever comes next.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.vertical, 7)
            }
            Section("At your fingertips") {
                Toggle("Open on hover", isOn: preference(\.openOnHover))
                Toggle("Show compact activity beside the notch", isOn: preference(\.showCompactActivity))
                Toggle("Show over full-screen apps", isOn: preference(\.showInFullScreen))
                Toggle("Use a floating halo on displays without a notch", isOn: preference(\.showOnUnnotchedDisplay))
            }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                        startupError = nil
                    } catch { startupError = error.localizedDescription }
                }))
                if let startupError { Text(startupError).font(.caption).foregroundStyle(.red) }
            } header: { Text("Startup") } footer: { Text("Halo lives in the menu bar and stays out of your Dock.") }
            Section {
                Picker("Open or close Halo", selection: preference(\.shortcut)) {
                    ForEach(GlobalShortcut.allCases) { Text($0.title).tag($0) }
                }
                if !model.shortcutAvailable { Text("This shortcut is already in use. Choose another combination.").font(.caption).foregroundStyle(.orange) }
                LabeledContent("Close an open Halo", value: "Escape")
                LabeledContent("Keep Halo open", value: "Click the pin")
            } header: { Text("The little details") } footer: { Text("Clicks outside Halo pass through to your apps. Your current app keeps keyboard focus.") }
        }.formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Section { HaloAppearancePreview().frame(height: 150).listRowInsets(EdgeInsets()) }
            Section("Shape & motion") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("Expanded width"); Spacer(); Text("\(Int(model.preferences.expandedWidth)) pt").foregroundStyle(.secondary).monospacedDigit() }
                    Slider(value: preference(\.expandedWidth), in: 400...520, step: 10)
                }.padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("Animation"); Spacer(); Text(model.preferences.animationSpeed < 0.30 ? "Quick" : model.preferences.animationSpeed > 0.45 ? "Gentle" : "Balanced").foregroundStyle(.secondary) }
                    Slider(value: preference(\.animationSpeed), in: 0.22...0.6, step: 0.02)
                }.padding(.vertical, 4)
                Toggle("Follow the system’s Reduce Motion setting", isOn: preference(\.respectReduceMotion))
            }
            Section("Hover behavior") {
                Picker("Open after", selection: preference(\.hoverDelay)) {
                    Text("Immediately").tag(0.0)
                    Text("A brief pause").tag(0.18)
                    Text("Half a second").tag(0.5)
                }
                Picker("Close after", selection: preference(\.collapseDelay)) {
                    Text("A brief pause").tag(0.25)
                    Text("A little breathing room").tag(0.45)
                    Text("One second").tag(1.0)
                }
            }
            Section { Button("Preview on your notch") { model.open(pin: true, tab: .overview) } }
        }.formStyle(.grouped)
    }

    private var activities: some View {
        Form {
            Section {
                Toggle("Music", isOn: preference(\.musicEnabled))
                Picker("Preferred player", selection: preference(\.musicProvider)) {
                    ForEach(MusicProvider.allCases) { Text($0.title).tag($0) }
                }.disabled(!model.preferences.musicEnabled)
                Text("Spotify and Apple Music. macOS will ask before Halo controls your player.").font(.caption).foregroundStyle(.secondary)
                if model.preferences.musicEnabled {
                    HStack {
                        Label(model.media.available ? "Connected to \(model.media.provider.title)" : model.media.message, systemImage: model.media.available ? "checkmark.circle.fill" : "music.note")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Refresh") { model.mediaService.refresh() }.controlSize(.small)
                    }
                }
            } header: { Label("Music, right here", systemImage: "music.note") }
            Section {
                Toggle("Focus timers", isOn: preference(\.timerEnabled))
                Toggle("Play a sound when a timer ends", isOn: preference(\.playTimerSound))
                Toggle("Notify when a timer ends", isOn: Binding(get: { model.preferences.timerNotifications }, set: { value in
                    if value { model.requestTimerNotifications() } else { model.preferences.timerNotifications = false }
                }))
            } header: { Label("A moment to focus", systemImage: "timer") } footer: { Text("Timers keep their place through sleep and app restarts.") }
            Section {
                Toggle("File shelf", isOn: preference(\.filesEnabled))
                Text("Drop files onto Halo to keep them close. Drag them into apps, copy them, or share with AirDrop. Removing a file from the shelf leaves the original in place.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Files on your shelf", value: "\(model.fileShelf.state.files.count) of 20")
                Button("Clear file shelf") { model.fileShelf.clear() }.disabled(model.fileShelf.state.files.isEmpty)
            } header: { Label("A place for your files", systemImage: "tray") } footer: { Text("File references are saved only on this Mac. Halo does not copy or upload your files automatically.") }
            Section {
                Toggle("Keep awake", isOn: preference(\.keepAwakeEnabled))
                Text("Keep your Mac awake for presentations, downloads, and long tasks. Start a timed session or stop it yourself from the Awake tab.").font(.caption).foregroundStyle(.secondary)
            } header: { Label("Stay with it", systemImage: "cup.and.saucer") } footer: { Text("Sessions end when Halo quits or your Mac sleeps. Disabling this activity ends the current session.") }
            Section {
                Toggle("Battery status", isOn: preference(\.batteryEnabled))
                Toggle("Briefly show charging changes", isOn: preference(\.chargingAlerts))
            } header: { Label("A little peace of mind", systemImage: "battery.100percent") }
        }.formStyle(.grouped)
    }

    private var about: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage()).resizable().frame(width: 112, height: 112).padding(.top, 24)
                Text("Halo").font(.system(size: 32, weight: .medium))
                Text("A little more Mac.").font(.system(size: 15)).foregroundStyle(.secondary)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0")").font(.system(size: 11)).foregroundStyle(.tertiary)
                Divider().padding(.vertical, 12)
                VStack(alignment: .leading, spacing: 16) {
                    aboutRow("hand.raised", "Your Mac, your choice.", "Music access is optional. Halo never records your keystrokes or sends usage analytics.")
                    aboutRow("sparkles", "Small by design.", "Native SwiftUI and AppKit. No account, no subscription, and no background animation when Halo is idle.")
                    aboutRow("laptopcomputer", "At home on your Mac.", "macOS Sonoma 14 or later. Built for Apple silicon and Intel, with support for notched and external displays.")
                }
            }.padding(.horizontal, 32).padding(.bottom, 28).frame(maxWidth: .infinity)
        }
    }
    private func aboutRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .light)).foregroundStyle(.tint).frame(width: 25)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HaloAppearancePreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var expanded = false
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(nsColor: .controlBackgroundColor), Color.accentColor.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.primary.opacity(0.04).frame(height: 22)
            VStack(spacing: 9) {
                Color.clear.frame(height: 22)
                if expanded {
                    HStack(spacing: 3) {
                        ForEach(["square.grid.2x2", "music.note", "timer", "tray", "cup.and.saucer", "battery.100percent"], id: \.self) { symbol in
                            Image(systemName: symbol).font(.system(size: 9, weight: .medium))
                                .frame(maxWidth: .infinity).frame(height: 23)
                                .background(.white.opacity(symbol == "square.grid.2x2" ? 0.13 : 0), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }.foregroundStyle(.white.opacity(0.7)).padding(3).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    HStack(spacing: 7) {
                        previewCard("timer", title: "Focus", value: "25 min", tint: HaloPalette.orange)
                        previewCard("tray", title: "File shelf", value: "Drop files", tint: HaloPalette.accent)
                    }
                }
            }.padding(.horizontal, expanded ? 18 : 0)
                .frame(width: expanded ? 276 : 150, height: expanded ? 126 : 26, alignment: .top)
                .foregroundStyle(.white).background(HaloPalette.surface)
                .clipShape(HaloShape(topRadius: expanded ? 10 : 4, bottomRadius: expanded ? 22 : 9))
                .shadow(color: .black.opacity(expanded ? 0.18 : 0), radius: 12, y: 5)
            Text("Hover to preview").font(.system(size: 10)).foregroundStyle(.tertiary).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 8)
        }.onHover { expanded = $0 }.animation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.36, dampingFraction: 0.86), value: expanded)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func previewCard(_ symbol: String, title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.system(size: 8)).foregroundStyle(tint)
            Text(value).font(.system(size: 15, weight: .medium, design: .rounded))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(9).haloCard(radius: 11)
    }
}
