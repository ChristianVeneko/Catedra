# Catedra

Native macOS (SwiftUI) cockpit over a local mirror of a student's Moodle (SAIA, Universidad Fermin Toro). It reads the
workspace produced by `_sistema/sync_moodle.py`, shows what is due, renders statements, manages your own files per
activity and can run the sync for you. UI copy is Spanish; code is English.

## Requirements
- macOS 15+, Xcode 26+ (developed with Xcode 27 / Swift 6)
- `xcodegen` (`brew install xcodegen`) only if you want to regenerate the project
- A Python 3 with `requests` for syncing

## Build
Open `Catedra.xcodeproj` in Xcode and run, or:

    xcodegen generate
    xcodebuild -project Catedra.xcodeproj -scheme Catedra -destination 'platform=macOS' build
    xcodebuild -project Catedra.xcodeproj -scheme Catedra -destination 'platform=macOS' test

The app is not sandboxed (it reads `~/Desktop/UFT` and runs `python3`) and is signed locally ("Sign to Run Locally").
Settings (⌘,) hold the workspace path, Python interpreter and SAIA credentials.

## Architecture (hexagonal)
- `Domain/` pure types: Activity, ActivityState, Course, CountdownFormatter, ActivityDiff, Agenda, SyncLogParser; `Domain/Agent/` AgentScope, AgentRun, AgentEvent, AgentStreamParser, Recipe
- `Application/` use cases: LoadWorkspace, Sync, ImportFiles, RunAgent, RecipeCatalog
- `Ports/` protocols: WorkspaceReading, MoodleSyncing, CredentialStoring, FileImporting, AgentRunning, AgentRunStoring, AgentNotifying, TerminalOpening
- `Adapters/` FileSystemWorkspace, PythonSyncAdapter, KeychainCredentialStore, FileSystemImporter, WorkspaceWatcher, ClaudeCLIAgentRunner, ClaudeLocator, LoginShellEnvironment, JSONAgentRunStore, GeneratedFilesScanner, TerminalLauncher, UserNotificationAdapter
- `UI/` feature folders (Dashboard, Sidebar, ActivityDetail, Contents, Sync, Agent, Settings, Components)
- `App/` composition root (`AppContainer`) and `@Observable` models

## Credentials
The SAIA username and password are stored only in the macOS Keychain (service `com.cmendoza.catedra.saia`). On sync
they are passed to the Python process exclusively via the `MOODLE_USER` / `MOODLE_PASS` environment variables;
stdin is closed so the script can never prompt. They are never written to files or logs.

## File safety
User files are only ever copied (never moved) into `entrega/`, `preparacion/` or `apuntes/` of an activity, with
" (2)" suffixes on name collisions; paths outside the workspace or symlinked targets are refused.

## Agents (Claude Code)
Claude Code can run from the app at two scopes: an **activity** (cwd = the activity folder; the "Agente" tab of the
activity detail) and a **course** (cwd = the course folder; the "Agente" item under each course in the sidebar, or the
toolbar button). Claude loads the workspace `CLAUDE.md` from the cwd and its parents, so the UFT rules apply in both.

- Headless turn: `claude -p "<prompt>" --output-format stream-json --verbose --permission-mode <mode> [--model <alias>] [--resume <session>]`
  with stdin closed. The `stream-json` output is parsed incrementally by `AgentStreamParser` (tolerant: unknown events
  and malformed lines are ignored). Sending a message after a run continues the same conversation with `--resume`.
- The binary is found by `ClaudeLocator` (`~/.local/bin`, Homebrew, `/usr/local/bin`, then a login shell) and can be
  overridden in Settings. The child PATH comes from the user's login shell (cached) so tools like `python3` and `nlm` work.
- Settings: Claude path, default model (default/opus/sonnet/haiku) and permission mode (`acceptEdits` by default,
  `auto`, or "Sin restricciones" = `bypassPermissions`, shown with a warning). Denied tool calls are listed in the
  transcript with a hint to change the mode.
- Recipes (`RecipeCatalog`) are one-click, editable Spanish prompts. By design there is **no** recipe that answers a live
  graded quiz or exam: exam/quiz recipes only prepare (study guide, practice exam with separate answers, key concepts).
  Everything the agent writes is a draft for manual review; submission to SAIA stays manual.
- Several agents can run in parallel (one per scope). The sidebar, activity cards and a toolbar badge show running agents.
  A local notification is posted when a run finishes while the app is in the background.
- History (last 30 conversations per scope, with transcripts) is stored as JSON in
  `~/Library/Application Support/Catedra/agent-runs/`, never in the workspace. "Archivos generados" lists files under the
  scope folder modified since the run started. "Abrir en Terminal" resumes the session in Terminal.app.

### Testing notes
- `CATEDRA_LIVE_CLAUDE=1` enables a real-CLI smoke test (temp dir, model `haiku`). With xcodebuild, pass it as
  `TEST_RUNNER_CATEDRA_LIVE_CLAUDE=1 xcodebuild … test -only-testing:CatedraTests/ClaudeCLIAgentRunnerTests`.
- Under tests, or with `CATEDRA_SKIP_KEYCHAIN=1`, the app does not touch the Keychain. Every rebuild changes the ad-hoc
  signature, which makes macOS show a blocking Keychain access prompt that would hang the test host.
