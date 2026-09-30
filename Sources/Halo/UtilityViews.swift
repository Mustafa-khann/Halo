import AppKit
import SwiftUI

@MainActor struct FileShelfView: View {
    @ObservedObject var shelf: FileShelfService
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(shelf.loading ? "Adding your files…" : shelf.draggingOver ? "Drop to keep it close." : "A place between apps.")
                    .font(.system(size: 11)).foregroundStyle(HaloPalette.secondary)
                Spacer()
                Button { shelf.chooseFiles() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Add files").accessibilityLabel("Add files")
                if !shelf.state.files.isEmpty {
                    Menu {
                        Button("Select all") { shelf.selection = Set(shelf.state.files.map(\.id)) }
                        Button("Remove selected from shelf") { shelf.remove(shelf.selection) }.disabled(shelf.selection.isEmpty)
                        Button("Clear shelf") { shelf.clear() }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 24, height: 24).contentShape(Rectangle())
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Shelf actions").accessibilityLabel("Shelf actions")
                }
            }
            if shelf.state.files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 28, weight: .light)).foregroundStyle(shelf.draggingOver ? HaloPalette.accent : HaloPalette.secondary)
                    Text("Drop files onto Halo.").font(.system(size: 13, weight: .medium))
                    Text("Pick them up in any app. Send them with AirDrop.").font(.system(size: 10)).foregroundStyle(HaloPalette.secondary)
                }.frame(maxWidth: .infinity).frame(height: 95)
                    .background(HaloPalette.card, in: RoundedRectangle(cornerRadius: 13))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(shelf.state.files) { file in
                            fileCard(file)
                        }
                    }.padding(2)
                }.scrollIndicators(.hidden).frame(height: 95)
            }
            if shelf.state.files.isEmpty {
                Button("Add files…") { shelf.chooseFiles() }.buttonStyle(HaloButtonStyle())
            } else {
                HStack(spacing: 6) {
                    Button { shelf.airDrop() } label: { Label("AirDrop", systemImage: "airdrop") }.buttonStyle(HaloButtonStyle(prominent: true))
                    Button { shelf.copy() } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(HaloButtonStyle())
                    Button { shelf.reveal() } label: { Label("Finder", systemImage: "folder") }.buttonStyle(HaloButtonStyle())
                }.disabled(shelf.actionURLs.isEmpty)
            }
            Text(shelf.message ?? (shelf.state.files.isEmpty ? "Your originals stay right where they are." : shelf.selection.isEmpty ? "Actions apply to all files. Click to select." : "\(shelf.selection.count) selected · Drag a file into another app."))
                .font(.system(size: 9)).foregroundStyle(shelf.message == nil ? HaloPalette.secondary : HaloPalette.accent)
                .lineLimit(1).help(shelf.message ?? "Removing a file from the shelf leaves the original in place.")
        }
    }
    private func fileCard(_ file: ShelfFile) -> some View {
        let selected = shelf.selection.contains(file.id)
        return Button { shelf.toggleSelection(file) } label: {
            VStack(spacing: 5) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().scaledToFit().frame(width: 35, height: 35)
                Text(file.name).font(.system(size: 10, weight: .medium)).lineLimit(2).multilineTextAlignment(.center).frame(height: 25)
            }.frame(width: 89, height: 82)
                .opacity(file.available ? 1 : 0.4)
                .background(selected ? HaloPalette.accent.opacity(0.15) : HaloPalette.card, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? HaloPalette.accent.opacity(0.65) : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(file.available ? file.url.path : "\(file.name) is no longer available.")
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
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: service.session.active ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(service.session.active ? HaloPalette.accent : HaloPalette.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.session.active ? "Staying with you." : "A little longer, awake.").font(.system(size: 15, weight: .medium))
                    Text(service.session.active ? (service.session.keepDisplayAwake ? "Mac and display stay awake" : "Mac stays awake · display can sleep") : "For presentations and tasks that take time.")
                        .font(.system(size: 10)).foregroundStyle(HaloPalette.secondary)
                }
                Spacer(minLength: 0)
            }
            if service.session.active {
                Text(service.session.remaining(at: service.now).map { clockString($0) } ?? "Until you stop")
                    .font(.system(size: service.session.deadline == nil ? 23 : 36, weight: .light, design: .rounded)).monospacedDigit()
                Button { service.stop() } label: { Label("Stop keeping awake", systemImage: "stop.fill") }.buttonStyle(HaloButtonStyle(prominent: true))
            } else {
                HStack {
                    Text("Keep awake for").font(.system(size: 11)).foregroundStyle(HaloPalette.secondary)
                    Spacer()
                    Picker("Duration", selection: $duration) {
                        ForEach(AwakeDuration.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 145).controlSize(.small)
                }
                Toggle("Keep the display awake too", isOn: $keepDisplayAwake).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                Button { service.start(duration: duration, keepDisplayAwake: keepDisplayAwake) } label: {
                    Label("Keep awake", systemImage: "cup.and.saucer")
                }.buttonStyle(HaloButtonStyle(prominent: true))
            }
            Text(service.error ?? "Stops when Halo quits or your Mac sleeps.")
                .font(.system(size: 9)).foregroundStyle(service.error == nil ? HaloPalette.secondary : .orange)
                .lineLimit(1).help("Closing the lid or choosing Sleep still puts your Mac to sleep.")
        }
    }
}
