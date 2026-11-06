import AppKit
import SwiftUI
import Vision
import ImageIO
import Combine
import CoreServices

struct TextSpan: Sendable {
    let text: String
    let box: CGRect
}

struct TextLine: Sendable {
    let text: String
    let box: CGRect
    let words: [TextSpan]
}

struct Match: Identifiable, Sendable {
    let url: URL
    let lines: [TextLine]
    let date: Date?
    var id: URL { url }

    func highlights(for query: String) -> [CGRect] {
        guard !query.isEmpty else { return [] }
        return lines.flatMap { line in
            let boxes = line.words.filter { $0.text.localizedStandardContains(query) }.map(\.box)
            if !boxes.isEmpty { return boxes }
            return line.text.localizedStandardContains(query) ? [line.box] : []
        }
    }
}

struct FileStamp: Equatable, Sendable {
    let created: Date?
    let modified: Date?
    let bytes: Int?
}

struct Entry: Sendable {
    let stamp: FileStamp
    let match: Match?
}

func recognize(_ url: URL, date: Date?) -> Match? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    let supported = (try? request.supportedRecognitionLanguages()) ?? []
    let languages = ["tr-TR", "en-US"].filter { supported.contains($0) }
    if !languages.isEmpty { request.recognitionLanguages = languages }
    do {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        try VNImageRequestHandler(url: url, orientation: orientation).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> TextLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            var words: [TextSpan] = []
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { word, range, _, _ in
                guard let word, let region = try? candidate.boundingBox(for: range) else { return }
                words.append(TextSpan(text: word, box: region.boundingBox))
            }
            return TextLine(text: text, box: observation.boundingBox, words: words)
        }
        return Match(url: url, lines: lines, date: date)
    } catch {
        return nil
    }
}

func refresh(_ folder: URL, previous: [URL: Entry]) async -> [URL: Entry]? {
    let types: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "webp"]
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey]
    guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys),
                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
    var next: [URL: Entry] = [:]
    var pending: [(URL, FileStamp)] = []
    while let url = files.nextObject() as? URL {
        if Task.isCancelled { return nil }
        guard types.contains(url.pathExtension.lowercased()),
              let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
        let stamp = FileStamp(created: values.creationDate, modified: values.contentModificationDate, bytes: values.fileSize)
        if let old = previous[url], old.stamp == stamp {
            next[url] = old
        } else {
            pending.append((url, stamp))
        }
    }
    await withTaskGroup(of: (URL, Entry).self) { group in
        var jobs = pending.makeIterator()
        func enqueue() {
            guard let (url, stamp) = jobs.next() else { return }
            group.addTask {
                (url, Entry(stamp: stamp, match: Task.isCancelled ? nil : recognize(url, date: stamp.created ?? stamp.modified)))
            }
        }
        for _ in 0..<min(3, pending.count) { enqueue() }
        for await (url, entry) in group {
            if Task.isCancelled { group.cancelAll(); break }
            next[url] = entry
            enqueue()
        }
    }
    return Task.isCancelled ? nil : next
}

final class FolderEvents {
    let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var stream: FSEventStreamRef?

    init?(_ folder: URL) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
                                            | kFSEventStreamCreateFlagNoDefer
                                            | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderEvents>.fromOpaque(info).takeUnretainedValue().requestRefresh()
        }, &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.15, flags) else { return nil }

        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
        requestRefresh()
    }

    func requestRefresh() { continuation.yield(()) }

    deinit {
        continuation.finish()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}


func loadImage(_ url: URL, limit: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: limit] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
}

final class PreviewModel: ObservableObject {
    @Published var image: CGImage?
}

struct ImagePreview: View {
    let url: URL
    let boxes: [CGRect]
    let limit: Int
    var selected: Int? = nil
    @StateObject private var model = PreviewModel()

    var body: some View {
        GeometryReader { geometry in
            if let image = model.image {
                let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
                let width = CGFloat(image.width) * scale
                let height = CGFloat(image.height) * scale
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1).resizable()
                    ForEach(Array(boxes.enumerated()), id: \.offset) { index, box in
                        Rectangle().fill(.yellow.opacity(selected == index ? 0.65 : 0.24))
                            .overlay(Rectangle().strokeBorder(selected == index ? .orange : .yellow, lineWidth: selected == index ? 2 : 1))
                            .frame(width: box.width * width, height: box.height * height)
                            .offset(x: box.minX * width, y: (1 - box.maxY) * height)
                    }
                }.frame(width: width, height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.task(id: url) {
            let image = await Task.detached(priority: .utility) { loadImage(url, limit: limit) }.value
            if !Task.isCancelled { model.image = image }
        }.accessibilityLabel("Image preview")
    }
}

@MainActor final class SearchModel: ObservableObject {
    @Published var results: [Match] = []
    @Published var query = ""
    @Published var dateFilter = DateFilter.all
    @Published var selected = 0
    @Published var status = "Choose your screenshot folder."
    @Published var opened: Match?
    @Published private(set) var folder: URL?
    private var watcher: Task<Void, Never>?
    private var monitor: FolderEvents?

    var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func watch(_ folder: URL) {
        watcher?.cancel()
        self.folder = folder
        results = []
        status = "Scanning \(folder.lastPathComponent)…"
        monitor = nil
        guard let monitor = FolderEvents(folder) else {
            status = "Could not watch the folder. Choose it again."
            return
        }
        self.monitor = monitor
        let events = monitor.events
        watcher = Task { [weak self] in
            var entries: [URL: Entry] = [:]
            var first = true
            for await _ in events {
                let worker = Task.detached { [entries] in await refresh(folder, previous: entries) }
                let next = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self else { return }
                guard let next else {
                    self.status = "Could not read the folder."
                    return
                }
                if first || next.mapValues(\.stamp) != entries.mapValues(\.stamp) {
                    self.results = next.values.compactMap(\.match).sorted {
                        $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
                    }
                    self.status = "Watching \(folder.lastPathComponent) · \(self.results.count) images"
                    let failures = next.count - self.results.count
                    if failures > 0 { self.status += " · \(failures) unreadable" }
                }
                first = false
                entries = next
                
            }
        }
    }
    deinit { watcher?.cancel() }
}

enum DateFilter: String, CaseIterable {
    case all = "All Dates"
    case today = "Today"
    case week = "Last 7 Days"

    func includes(_ date: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        if self == .all { return true }
        let today = calendar.startOfDay(for: now)
        guard let date, let start = calendar.date(byAdding: .day, value: self == .today ? 0 : -6, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return false }
        return date >= start && date < end
    }
}

struct SearchView: View {
    @StateObject private var model = SearchModel()
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu {
                    Button("Choose Folder…", action: chooseFolder).keyboardShortcut("o", modifiers: .command)
                    Button("Open Folder in Finder") { if let folder = model.folder { NSWorkspace.shared.open(folder) } }
                        .disabled(model.folder == nil)
                    Divider()
                    Button("Rescan Folder") { if let folder = model.folder { model.watch(folder) } }
                        .disabled(model.folder == nil)
                } label: {
                    Label(model.folder?.lastPathComponent ?? "Folder", systemImage: "folder")
                }.fixedSize().accessibilityLabel("Folder actions")
                TextField("Search text in images", text: $model.query).focused($searchFocused)
                Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }
                    .keyboardShortcut("f", modifiers: .command)
                    .help("Focus search")
            }
            HStack {
                Text(model.status).foregroundStyle(.secondary)
                Spacer()
                Picker("Date", selection: $model.dateFilter) {
                    ForEach(DateFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.fixedSize()
            }
            let now = Date()
            List(model.results.filter {
                model.dateFilter.includes($0.date, now: now) && (model.term.isEmpty || $0.lines.contains { $0.text.localizedStandardContains(model.term) }
                    || $0.url.lastPathComponent.localizedStandardContains(model.term))
            }) { match in
                HStack(spacing: 12) {
                    ImagePreview(url: match.url, boxes: [], limit: 200).frame(width: 96, height: 60)
                    VStack(alignment: .leading) {
                        Text(match.url.lastPathComponent).bold()
                        Text(match.lines.first { !model.term.isEmpty && $0.text.localizedStandardContains(model.term) }?.text
                             ?? match.lines.first?.text ?? "").lineLimit(2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open") { model.selected = 0; model.opened = match }
                }.buttonStyle(.borderless).padding(.vertical, 3)
            }
        }.padding().frame(minWidth: 660, minHeight: 440)
        .sheet(item: $model.opened) { match in
            let boxes = match.highlights(for: model.term)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(match.url.lastPathComponent).bold()
                    Spacer()
                    if !boxes.isEmpty {
                        Button { model.selected = (model.selected + boxes.count - 1) % boxes.count } label: {
                            Image(systemName: "chevron.left")
                        }.accessibilityLabel("Previous match")
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .disabled(boxes.count < 2)
                        Text("\(model.selected + 1) / \(boxes.count)").monospacedDigit()
                        Button { model.selected = (model.selected + 1) % boxes.count } label: {
                            Image(systemName: "chevron.right")
                        }.accessibilityLabel("Next match")
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .disabled(boxes.count < 2)
                    }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([match.url]) }
                    Button("Close") { model.opened = nil }.keyboardShortcut(.cancelAction)
                }
                ImagePreview(url: match.url, boxes: boxes, limit: 2200, selected: model.selected)
            }.padding().frame(width: 820, height: 580)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let folder = panel.url { model.watch(folder) }
    }
}

@main struct MelSnap: App {
    var body: some Scene { WindowGroup("MelSnap 0.4") { SearchView() } }
}
