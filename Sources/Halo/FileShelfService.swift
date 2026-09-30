import AppKit
import Combine
import UniformTypeIdentifiers

struct ShelfFile: Codable, Equatable, Identifiable {
    var id = UUID()
    var url: URL
    var bookmark: Data?
    var name: String { url.lastPathComponent }
    var available: Bool { FileManager.default.fileExists(atPath: url.path) }
}

struct FileShelfState: Codable, Equatable {
    static let capacity = 20
    var files: [ShelfFile] = []

    @discardableResult mutating func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.isFileURL {
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            guard !files.contains(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == normalized }), files.count < Self.capacity else { continue }
            let bookmark = try? normalized.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            files.append(ShelfFile(url: normalized, bookmark: bookmark))
            added += 1
        }
        return added
    }

    mutating func resolveBookmarks() {
        for index in files.indices {
            guard let bookmark = files[index].bookmark else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            files[index].url = url.standardizedFileURL.resolvingSymlinksInPath()
            if stale { files[index].bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
        }
    }
}

@MainActor final class FileShelfService: NSObject, ObservableObject, NSSharingServiceDelegate {
    @Published private(set) var state: FileShelfState
    @Published var selection = Set<UUID>()
    @Published var message: String?
    @Published var draggingOver = false
    @Published private(set) var loading = false
    var onInteractionChanged: ((Bool) -> Void)?
    var onFilesAdded: (() -> Void)?
    private let defaults: UserDefaults
    private let storageKey = "halo.files.v1"
    private var sharingService: NSSharingService?
    private var openPanel: NSOpenPanel?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey), let saved = try? JSONDecoder().decode(FileShelfState.self, from: data) {
            var restored = saved
            restored.files = Array(restored.files.prefix(FileShelfState.capacity))
            restored.resolveBookmarks()
            state = restored
        } else { state = FileShelfState() }
        super.init()
    }

    var selectedFiles: [ShelfFile] { state.files.filter { selection.contains($0.id) } }
    var actionFiles: [ShelfFile] { selection.isEmpty ? state.files : selectedFiles }
    var actionURLs: [URL] { actionFiles.filter(\.available).map(\.url) }

    @discardableResult func add(_ urls: [URL]) -> Int {
        let valid = urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
        let existing = Set(state.files.map { $0.url.standardizedFileURL.resolvingSymlinksInPath() })
        let newCount = Set(valid.map { $0.standardizedFileURL.resolvingSymlinksInPath() }).subtracting(existing).count
        let previous = Set(state.files.map(\.id))
        let added = state.add(valid)
        if added > 0 {
            selection = Set(state.files.filter { !previous.contains($0.id) }.map(\.id))
            persist()
            onFilesAdded?()
        }
        if valid.count != urls.count { message = "Some files are no longer available." }
        else if added < newCount { message = "Your shelf holds 20 files. Remove a few to make room." }
        else { message = nil }
        return added
    }

    func remove(_ ids: Set<UUID>) {
        state.files.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        message = nil
        persist()
    }
    func clear() { remove(Set(state.files.map(\.id))) }
    func toggleSelection(_ file: ShelfFile) {
        if selection.contains(file.id) { selection.remove(file.id) } else { selection.insert(file.id) }
        message = nil
    }
    func chooseFiles() {
        guard openPanel == nil else { return }
        let picker = NSOpenPanel()
        picker.title = "Add to Halo"
        picker.prompt = "Add to shelf"
        picker.canChooseDirectories = true
        picker.canChooseFiles = true
        picker.allowsMultipleSelection = true
        openPanel = picker
        onInteractionChanged?(true)
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            guard let self else { return }
            if response == .OK { self.add(picker.urls) }
            self.openPanel = nil
            self.onInteractionChanged?(false)
        }
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty, !loading else { return false }
        loading = true
        onInteractionChanged?(true)
        // Load all URLs before adding them so a multi-file drop keeps Finder's order.
        Task {
            defer { loading = false; onInteractionChanged?(false) }
            var urls: [URL] = []
            for provider in files {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        if let url = item as? URL { continuation.resume(returning: url) }
                        else if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                        else if let string = item as? String { continuation.resume(returning: URL(string: string)) }
                        else { continuation.resume(returning: nil) }
                    }
                }
                if let url, url.isFileURL { urls.append(url) }
            }
            if urls.isEmpty { message = "These files could not be added. Try Add files instead." }
            else {
                add(urls)
                if urls.count < files.count && message == nil { message = "Some files could not be added. Try Add files instead." }
            }
        }
        return true
    }

    func open(_ file: ShelfFile) {
        guard file.available else { message = "This file has moved or is no longer available."; return }
        if !NSWorkspace.shared.open(file.url) { message = "Your Mac could not open this file." }
    }
    func reveal(_ urls: [URL]? = nil) {
        let files = urls ?? actionURLs
        guard !files.isEmpty else { message = "These files are no longer available."; return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }
    func copy(_ urls: [URL]? = nil) {
        let files = urls ?? actionURLs
        guard !files.isEmpty else { message = "These files are no longer available."; return }
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.writeObjects(files.map { $0 as NSURL })
        message = copied ? (files.count == 1 ? "File copied." : "\(files.count) files copied.") : "These files could not be copied."
    }
    func airDrop() {
        let urls = actionURLs
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            message = "AirDrop is unavailable for these files on this Mac."
            return
        }
        sharingService = service
        service.delegate = self
        onInteractionChanged?(true)
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        // AirDrop can call this when its picker closes, even without a transfer.
        // Let the system's picker report delivery rather than claiming success.
        message = nil
        finishSharing()
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let cocoaError = error as NSError
        message = cocoaError.code == NSUserCancelledError ? nil : "AirDrop: \(error.localizedDescription)"
        finishSharing()
    }
    private func finishSharing() { sharingService = nil; onInteractionChanged?(false) }
    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: storageKey) }
    }
}
