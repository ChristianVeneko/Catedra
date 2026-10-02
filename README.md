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
- `Domain/` pure types: Activity, ActivityState, Course, CountdownFormatter, ActivityDiff, Agenda, SyncLogParser; `Domain/Agent/` AgentScope, AgentRun, AgentEvent, AgentStreamParser, Recipe, SlashCommand, SlashCommandMatcher, SlashToken, AppCommand, SkillFrontmatter, PromptHistory, ScopeRelativePath
- `Application/` use cases: LoadWorkspace, Sync, ImportFiles, RunAgent, RecipeCatalog
- `Ports/` protocols: WorkspaceReading, MoodleSyncing, CredentialStoring, FileImporting, AgentRunning, AgentRunStoring, AgentNotifying, TerminalOpening, SlashCommandCatalogStoring, SlashCommandScanning
- `Adapters/` FileSystemWorkspace, PythonSyncAdapter, KeychainCredentialStore, FileSystemImporter, WorkspaceWatcher, ClaudeCLIAgentRunner, ClaudeLocator, LoginShellEnvironment, JSONAgentRunStore, JSONSlashCommandCatalogStore, LocalSlashCommandScanner, GeneratedFilesScanner, TerminalLauncher, UserNotificationAdapter
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

### Composer
The composer is an AppKit `NSTextView` wrapped for SwiftUI (`ComposerTextView`), because SwiftUI cannot intercept
Enter / Tab / Esc / arrows reliably on macOS. It grows from 1 to 8 lines and then scrolls.
- **Enter** sends, **Shift+Enter** (or Option+Enter) inserts a newline, **⌘↩** also sends. **Esc** closes the suggestions
  popup, then drops focus. While an agent runs you can keep typing a draft; sending is disabled and the button becomes Stop.
- **↑ / ↓** with the caret on the first / last line (popup closed) cycle through the prompts previously sent in that
  scope (derived from the stored runs; recipe templates are skipped).
- Chips: model (per conversation: Predeterminado/Opus/Sonnet/Haiku) and permission mode. The paperclip opens an
  `NSOpenPanel` restricted to the scope folder and inserts `@relative/path` (quoted when it has spaces); files dragged from
  Finder onto the composer do the same. Files outside the scope folder are refused.

### Slash commands
Typing `/` at the start of the text or after whitespace opens a popup above the composer, grouped as **Cátedra**,
**Skills** and **Comandos de Claude Code**. Ranking (`SlashCommandMatcher`): name prefix, alias prefix, word-boundary or
substring on the name, substring in the description, then subsequence; case and diacritics are ignored. ↑/↓ move, Tab/Enter
accept (inserts `/name `), Esc dismisses, click accepts.
- Everything except the Cátedra commands is sent to Claude as part of the prompt (`/skill-name …` works in `-p` mode).
- The catalog comes from the `system/commands_changed` stream event (fallback: `system/init.slash_commands` minus
  `terminal_slash_commands`). The latest full catalog is cached in
  `~/Library/Application Support/Catedra/slash-commands.json` and refreshed by every run, so autocomplete works before the
  first run of a session. Without a cache, a local scan (no tokens spent) reads `SKILL.md` / `commands/*.md` frontmatter from
  `~/.claude` and every `.claude` folder between the scope and the home directory. Terminal-only commands (`/doctor`,
  `/login`, …) are hidden because they do nothing in headless mode.
- Cátedra commands are handled by the app and never sent to Claude; they override same-named CLI builtins:
  `/resume` (picker of past runs of this scope, optionally all scopes; continues with `--resume <session_id>`),
  `/new` (alias `/clear`), `/model <opus|sonnet|haiku|predeterminado>`, `/permisos <aceptar|auto|sin-restricciones>`,
  `/recetas`, `/terminal`, `/archivos`.

### Testing notes
- `CATEDRA_LIVE_CLAUDE=1` enables a real-CLI smoke test (temp dir, model `haiku`). With xcodebuild, pass it as
  `TEST_RUNNER_CATEDRA_LIVE_CLAUDE=1 xcodebuild … test -only-testing:CatedraTests/ClaudeCLIAgentRunnerTests`.
- Under tests, or with `CATEDRA_SKIP_KEYCHAIN=1`, the app does not touch the Keychain. Every rebuild changes the ad-hoc
  signature, which makes macOS show a blocking Keychain access prompt that would hang the test host.
