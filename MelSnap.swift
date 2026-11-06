import AppKit
import SwiftUI
import Vision
import Combine

struct Match: Identifiable, Sendable {
    let url: URL
    let text: String
    var id: URL { url }
}

func indexImages(in folder: URL) -> ([Match], Int) {
    let types = Set(["png", "jpg", "jpeg", "heic", "tiff", "webp"])
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                               options: [.skipsHiddenFiles, .skipsPackageDescendants])
    var matches: [Match] = []
    var failures = 0
    while let url = files?.nextObject() as? URL {
        guard types.contains(url.pathExtension.lowercased()),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let languages = ["tr-TR", "en-US"].filter { supported.contains($0) }
        if !languages.isEmpty { request.recognitionLanguages = languages }
        do {
            try VNImageRequestHandler(url: url).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            matches.append(Match(url: url, text: lines.joined(separator: "\n")))
        } catch {
            failures += 1
        }
    }
    return (matches.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }, failures)
}


final class SearchModel: ObservableObject {
    @Published var results: [Match] = []
    @Published var query = ""
    @Published var status = "Choose your screenshot folder."
    @Published var busy = false
}

struct SearchView: View {
    @StateObject private var model = SearchModel()
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("Choose Folder…", action: chooseFolder).disabled(model.busy)
                TextField("Search text in images", text: $model.query)
                if model.busy { ProgressView().controlSize(.small) }
            }
            Text(model.status).foregroundStyle(.secondary)
            List(model.results.filter {
                model.query.isEmpty || $0.text.localizedStandardContains(model.query)
                    || $0.url.lastPathComponent.localizedStandardContains(model.query)
            }) { match in
                HStack {
                    VStack(alignment: .leading) {
                        Text(match.url.lastPathComponent).bold()
                        Text(match.text).lineLimit(2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open") { NSWorkspace.shared.open(match.url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([match.url]) }
                }.buttonStyle(.borderless)
            }
        }.padding().frame(minWidth: 660, minHeight: 440)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        model.busy = true
        model.status = "Scanning \(folder.lastPathComponent)…"
        Task {
            let (results, failures) = await Task.detached { indexImages(in: folder) }.value
            model.results = results
            model.status = "\(results.count) images · \(failures) unreadable"
            model.busy = false
        }
    }
}

@main struct MelSnap: App {
    var body: some Scene { WindowGroup("MelSnap 0.1") { SearchView() } }
}
