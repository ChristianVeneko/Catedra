import Foundation
import Observation

@Observable @MainActor
final class SyncModel {
    enum State: Equatable { case idle, running, finished(SyncOutcome) }

    private(set) var state: State = .idle
    private(set) var log: [SyncLogLine] = []
    private(set) var currentCourse: String?
    private(set) var lastIncludeFiles = true
    var isPresented = false

    private let useCase: SyncUseCase
    private let workspace: WorkspaceModel
    private var task: Task<Void, Never>?

    init(useCase: SyncUseCase, workspace: WorkspaceModel) {
        self.useCase = useCase
        self.workspace = workspace
    }

    var isRunning: Bool { state == .running }

    func start(includeFiles: Bool) {
        guard !isRunning else { isPresented = true; return }
        lastIncludeFiles = includeFiles
        log = []
        currentCourse = nil
        state = .running
        isPresented = true
        let settings = workspace.settings
        let stream = useCase.execute(root: settings.workspaceURL, pythonPath: settings.pythonPath, includeFiles: includeFiles)
        task = Task { [weak self] in
            for await progress in stream {
                guard let self else { return }
                switch progress {
                case .log(let line):
                    self.log.append(line)
                    if case .course(let name) = line.event { self.currentCourse = name }
                case .finished(let outcome):
                    self.state = .finished(outcome)
                }
            }
            if let self {
                if self.state == .running { self.state = .finished(.failed(exitCode: -1)) }
                await self.workspace.reload()
            }
        }
    }

    func cancel() {
        task?.cancel()
        if isRunning { state = .finished(.failed(exitCode: -15)) }
    }
}
