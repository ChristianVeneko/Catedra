import Foundation

struct LoadWorkspaceUseCase: Sendable {
    let reader: WorkspaceReading

    func execute(root: URL) async throws -> WorkspaceSnapshot {
        let reader = self.reader
        return try await Task.detached { try reader.loadSnapshot(root: root) }.value
    }
}
