import AppKit
import Foundation

@main struct Test05 {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = IndexStore(url: root.appendingPathComponent("index.json"))
        let file = root.appendingPathComponent("image.png")
        let box = CGRect(x: 0.7, y: 0.1, width: 0.2, height: 0.1)
        let match = Match(url: file, lines: [TextLine(text: "hello", box: box, words: [TextSpan(text: "hello", box: box)])], date: Date())
        let stamp = FileStamp(created: Date(), modified: Date(), bytes: 100)
        try store.save(folder: root, entries: [file: Entry(stamp: stamp, match: match)])
        let saved = store.load()!
        precondition(saved.folder == root && saved.entries[file.path]?.match?.highlights(for: "hello") == [box])
        let permissions = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)
        try store.clear()
        precondition(store.load() == nil)
        try Data("broken".utf8).write(to: store.url)
        precondition(store.load() == nil)
        let context = CGContext(data: nil, width: 1000, height: 2000, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let document = ZoomDocument(image: context.makeImage()!)
        document.boxes = [box]
        _ = NSApplication.shared
        let scroll = ZoomScroll(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scroll.documentView = document
        scroll.zoom = 4
        scroll.layoutSubtreeIfNeeded()
        precondition(document.frame.height > 1000)
        scroll.reveal = true
        scroll.layout()
        precondition(document.visibleRect.intersects(document.region(box)))
        print("PASS: persistent index roundtrip, permissions, deletion, corrupt cache, zoom geometry and selected-match visibility")
    }
}
