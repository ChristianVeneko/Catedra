import Foundation

/// Watches `_sistema/data` and calls `onChange` (debounced) when `activities.json` is rewritten.
final class WorkspaceWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var lastModified: Date?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "catedra.watcher")

    func start(root: URL, onChange: @escaping @Sendable () -> Void) {
        stop()
        let dataDir = root.appendingPathComponent("_sistema/data", isDirectory: true)
        let json = dataDir.appendingPathComponent("activities.json")
        lastModified = modificationDate(json)
        let fd = open(dataDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: queue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let current = self.modificationDate(json)
                if current != self.lastModified {
                    self.lastModified = current
                    onChange()
                }
            }
            self.pending = item
            self.queue.asyncAfter(deadline: .now() + 0.5, execute: item)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    deinit { source?.cancel() }
}
