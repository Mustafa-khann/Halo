import AppKit
import SwiftUI

@MainActor struct FileShelfView: View {
    @ObservedObject var shelf: FileShelfService
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 6) {
                Text("File shelf").font(.system(size: 15, weight: .semibold))
                Text(shelf.loading ? "Adding…" : shelf.state.files.isEmpty ? "" : "\(shelf.state.files.count)")
                    .font(.system(size: 11)).foregroundStyle(HaloPalette.secondary)
                Spacer()
                Button { shelf.chooseFiles() } label: { Image(systemName: "plus").font(.system(size: 12, weight: .medium)) }
                    .buttonStyle(HaloIconButtonStyle(size: 28)).help("Add files").accessibilityLabel("Add files")
                if !shelf.state.files.isEmpty {
                    Menu {
                        Button("Select all") { shelf.selection = Set(shelf.state.files.map(\.id)) }
                        Button("Remove selected from shelf") { shelf.remove(shelf.selection) }.disabled(shelf.selection.isEmpty)
                        Button("Clear shelf") { shelf.clear() }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(Rectangle())
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Shelf actions").accessibilityLabel("Shelf actions")
                }
            }.frame(height: 28)
            if shelf.state.files.isEmpty {
                VStack(spacing: 7) {
                    HaloSymbolBadge(symbol: "tray.and.arrow.down", size: 34)
                    Text(shelf.draggingOver ? "Drop to add to your shelf" : "Drop files here").font(.system(size: 13, weight: .medium))
                    Text("Drag into any app, or share with AirDrop.").font(.system(size: 11)).foregroundStyle(HaloPalette.secondary)
                }.frame(maxWidth: .infinity).frame(height: 108)
                    .haloCard(highlighted: shelf.draggingOver)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(shelf.draggingOver ? HaloPalette.accent.opacity(0.6) : .white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4])).allowsHitTesting(false))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(shelf.state.files) { file in fileCard(file) }
                    }.padding(2)
                }.scrollIndicators(.hidden).frame(height: 108)
            }
            if shelf.state.files.isEmpty {
                Button("Choose files…") { shelf.chooseFiles() }.buttonStyle(HaloButtonStyle())
            } else {
                HStack(spacing: 6) {
                    Button { shelf.airDrop() } label: { Label("AirDrop", systemImage: "airdrop") }.buttonStyle(HaloButtonStyle(prominent: true))
                    Button { shelf.copy() } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(HaloButtonStyle())
                    Button { shelf.reveal() } label: { Label("Finder", systemImage: "folder") }.buttonStyle(HaloButtonStyle())
                }.disabled(shelf.actionURLs.isEmpty)
            }
            Text(shelf.message ?? (shelf.state.files.isEmpty ? "Your originals stay in place." : shelf.selection.isEmpty ? "Click to select. Drag to any app." : "\(shelf.selection.count) selected · Drag to any app."))
                .font(.system(size: 10)).foregroundStyle(shelf.message == nil ? HaloPalette.secondary : HaloPalette.accent)
                .lineLimit(1).help(shelf.message ?? "Removing a file from the shelf leaves the original in place.")
        }
    }
    private func fileCard(_ file: ShelfFile) -> some View {
        let selected = shelf.selection.contains(file.id)
        return Button { shelf.toggleSelection(file) } label: {
            VStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().scaledToFit().frame(width: 42, height: 42)
                Text(file.name).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center).frame(height: 28)
            }.padding(.horizontal, 7).frame(width: 98, height: 102)
                .opacity(file.available ? 1 : 0.4)
                .haloCard(radius: 16, highlighted: selected)
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(HaloPalette.accent).padding(7).accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }.buttonStyle(HaloTileButtonStyle(radius: 16)).help(file.available ? file.url.path : "\(file.name) is no longer available.")
            .accessibilityLabel(file.name).accessibilityAddTraits(selected ? [.isSelected] : [])
            .onDrag { file.available ? NSItemProvider(object: file.url as NSURL) : NSItemProvider() }
            .contextMenu {
                Button("Open") { shelf.open(file) }.disabled(!file.available)
                Button("Show in Finder") { shelf.reveal([file.url]) }.disabled(!file.available)
                Button("Copy file") { shelf.copy([file.url]) }.disabled(!file.available)
                Divider()
                Button("Remove from shelf") { shelf.remove([file.id]) }
            }
    }
}

@MainActor struct KeepAwakeView: View {
    @ObservedObject var service: KeepAwakeService
    @ViewState private var duration: AwakeDuration = .hour
    @ViewState private var keepDisplayAwake = true
    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 11) {
                HaloSymbolBadge(symbol: service.session.active ? "cup.and.saucer.fill" : "cup.and.saucer", size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.session.active ? "Keeping your Mac awake" : "Keep awake").font(.system(size: 15, weight: .semibold))
                    Text(service.session.active ? (service.session.keepDisplayAwake ? "Mac and display stay awake" : "Your display can still sleep") : "A little more time for the task at hand.")
                        .font(.system(size: 11)).foregroundStyle(HaloPalette.secondary).lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            if service.session.active {
                Text(service.session.remaining(at: service.now).map { clockString($0) } ?? "Until you stop")
                    .font(.system(size: service.session.deadline == nil ? 28 : 44, weight: .regular, design: .rounded)).monospacedDigit().frame(height: 80)
                Button { service.stop() } label: { Label("Stop keeping awake", systemImage: "stop.fill") }.buttonStyle(HaloButtonStyle(prominent: true))
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Duration").font(.system(size: 12))
                        Spacer()
                        Picker("Duration", selection: $duration) {
                            ForEach(AwakeDuration.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 138).controlSize(.small)
                    }.frame(height: 39)
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                    HStack {
                        Text("Keep display awake").font(.system(size: 12))
                        Spacer()
                        Toggle("Keep display awake", isOn: $keepDisplayAwake).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }.frame(height: 39)
                }.padding(.horizontal, 13).haloCard(radius: 16)
                Button { service.start(duration: duration, keepDisplayAwake: keepDisplayAwake) } label: {
                    Label("Keep awake", systemImage: "cup.and.saucer")
                }.buttonStyle(HaloButtonStyle(prominent: true))
            }
            Text(service.error ?? "Ends when Halo quits or your Mac sleeps.")
                .font(.system(size: 10)).foregroundStyle(service.error == nil ? HaloPalette.secondary : HaloPalette.orange)
                .lineLimit(1).help("Closing the lid or choosing Sleep still puts your Mac to sleep.")
        }
    }
}
