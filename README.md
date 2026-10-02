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
- `Domain/` pure types: Activity, ActivityState, Course, CountdownFormatter, ActivityDiff, Agenda, SyncLogParser; `Domain/Agent/` AgentScope, AgentRun, AgentEvent, AgentProviderID, AgentOptions (permission levels, models), AgentEventParsing + ClaudeStreamParser / AntigravityStreamParser / OpenCodeEventParser, CancellationPolicy, ModelListParser, Recipe, SlashCommand, SlashCommandMatcher, SlashToken, AppCommand, SkillFrontmatter, PromptHistory, ScopeRelativePath
- `Application/` use cases: LoadWorkspace, Sync, ImportFiles, RunAgent, RecipeCatalog
- `Ports/` protocols: WorkspaceReading, MoodleSyncing, CredentialStoring, FileImporting, AgentRunning, AgentProvider, AgentRunStoring, AgentNotifying, TerminalOpening, SlashCommandCatalogStoring, SlashCommandScanning
- `Adapters/` FileSystemWorkspace, PythonSyncAdapter, KeychainCredentialStore, FileSystemImporter, WorkspaceWatcher, CLIAgentRunner, ClaudeProvider / AntigravityProvider / OpenCodeProvider, BinaryLocator, AgentBinaryProbe, LoginShellEnvironment, JSONAgentRunStore, JSONSlashCommandCatalogStore, LocalSlashCommandScanner, GeneratedFilesScanner, TerminalLauncher, UserNotificationAdapter
- `UI/` feature folders (Dashboard, Sidebar, ActivityDetail, Contents, Sync, Agent, Settings, Components)
- `App/` composition root (`AppContainer`) and `@Observable` models

## Credentials
The SAIA username and password are stored only in the macOS Keychain (service `com.cmendoza.catedra.saia`). On sync
they are passed to the Python process exclusively via the `MOODLE_USER` / `MOODLE_PASS` environment variables;
stdin is closed so the script can never prompt. They are never written to files or logs.

## File safety
User files are only ever copied (never moved) into `entrega/`, `preparacion/` or `apuntes/` of an activity, with
" (2)" suffixes on name collisions; paths outside the workspace or symlinked targets are refused.

## Agents
An agent can run from the app at two scopes: an **activity** (cwd = the activity folder; the "Agente" tab of the
activity detail) and a **course** (cwd = the course folder; the "Agente" item under each course in the sidebar, or the
toolbar button). The workspace context file (`CLAUDE.md` / `AGENTS.md`) is loaded by the CLI from the cwd and its
parents, so the UFT rules apply in both.

### Providers
Pick the provider in Settings › Agente (default Claude Code). New conversations use it; a stored conversation always
continues with its own provider (`AgentRun.provider`, absent in old JSON = Claude), and `/resume`, "Abrir en Terminal" and
the icons follow the run's provider. Each provider is an `AgentProvider` (arguments, parser, resume) driven by one generic
`CLIAgentRunner` (Process + line streaming; stdin closed).

| | Claude Code | Antigravity (`agy`) | OpenCode |
|---|---|---|---|
| Headless turn | `claude -p <prompt> --output-format stream-json --verbose --permission-mode <m> [--model] [--resume <id>]` | `agy -p <prompt> --output-format stream-json [--mode …] [--model <id>] [--conversation <id>]` | `opencode run --format json --dir <cwd> [--agent plan \| --auto] [-m provider/model] [--session <id>] [--command <name>] -- <message>` |
| Read only | `plan` | `--mode plan` | `--agent plan` |
| Accept edits (default) | `acceptEdits` | `--mode accept-edits` | no flag (permission asks are auto-rejected) |
| Automatic | `auto` | not available (hidden) | not available (hidden) |
| Sin restricciones | `bypassPermissions` | `--dangerously-skip-permissions` | `--auto` |
| Models | Predeterminado / Opus / Sonnet / Haiku | list from `agy models` (cached) | free text `provider/model` + list from `opencode models` |
| Slash catalog | `commands_changed` stream event (+ local scan) | local scan of `.agents/skills`, `~/.agents/skills`, `~/.gemini/config/skills` | local scan of `.opencode/{command,commands}`, `~/.config/opencode/{command,commands}`; `/name args` runs with `--command` |
| Terminal resume | `claude --resume <id>` | `agy --conversation <id>` | `opencode --session <id>` |
| Cost | USD | tokens only | USD (if the provider reports it) + tokens |
| Install | `curl -fsSL https://claude.ai/install.sh \| bash` | antigravity.google | `curl -fsSL https://opencode.ai/install \| bash` |

- Event schemas: Claude `stream-json`; Antigravity NDJSON keyed by `event` (`init`, `step_update`, `result`; text arrives as
  `text_delta` chunks per `step_index` and is emitted as one block when the step finishes; a `tool` step goes ACTIVE then
  DONE); OpenCode lines `{type, timestamp, sessionID, part|error}` with `step_start`, `text`, `reasoning`, `tool_use`
  (emitted once, already completed or failed), `step_finish` (cost, tokens) and `error`. OpenCode has no final event: a
  clean exit without an `error` event becomes a successful result built from the accumulated text, cost and tokens.
  All parsers are tolerant (unknown events ignored, malformed lines skipped).
- Binaries are found by `BinaryLocator` (provider-specific well-known folders, then a login shell) and can be overridden in
  Settings, which also shows the version (`--version`) or the install command. The child PATH comes from the user's login
  shell (cached) with the binary's own folder first, so `node`/`python3` resolve.
- Stopping a run sends SIGINT (clean end of turn), SIGTERM after 4 s and SIGKILL after 3 s more (`CancellationPolicy`).
- **OpenCode and Claude subscriptions:** do not sign in to OpenCode with a Claude Pro/Max subscription: Anthropic does not
  allow it. Use another provider or an API key. The same warning is shown in Settings.

### Common behavior
- Sending a message after a run continues the same conversation (`--resume`, `--conversation` or `--session`).
- The child process never sees a parent Claude Code session's `CLAUDECODE` / `CLAUDE_CODE_*` variables.
- Settings: per provider, executable, default model and permission level ("Sin restricciones" is shown with a warning).
  Denied tool calls are listed in the transcript with a hint to change the mode (Claude `permission_denials`; OpenCode
  rejected tool calls).
- Recipes (`RecipeCatalog`) are one-click, editable Spanish prompts. By design there is **no** recipe that answers a live
  graded quiz or exam: exam/quiz recipes only prepare (study guide, practice exam with separate answers, key concepts).
  Everything the agent writes is a draft for manual review; submission to SAIA stays manual.
- Several agents can run in parallel (one per scope, any mix of providers). The sidebar, activity cards and a toolbar badge
  show running agents with their provider marks (overlapped when several providers run). A local notification is posted when
  a run finishes while the app is in the background.
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
- Chips: model and permission level, both specific to the provider of the conversation (unsupported levels are hidden). The paperclip opens an
  `NSOpenPanel` restricted to the scope folder and inserts `@relative/path` (quoted when it has spaces); files dragged from
  Finder onto the composer do the same. Files outside the scope folder are refused.

### Slash commands
Typing `/` at the start of the text or after whitespace opens a popup above the composer, grouped as **Cátedra**,
**Skills** and **Comandos de Claude Code** (Claude) or **Skills / Comandos de <Proveedor>** (Antigravity, OpenCode). Ranking (`SlashCommandMatcher`): name prefix, alias prefix, word-boundary or
substring on the name, substring in the description, then subsequence; case and diacritics are ignored. ↑/↓ move, Tab/Enter
accept (inserts `/name `), Esc dismisses, click accepts.
- Everything except the Cátedra commands is sent to the agent as part of the prompt (`/skill-name …` works in `-p` mode;
  OpenCode commands run with `--command`).
- The catalog comes from the `system/commands_changed` stream event (fallback: `system/init.slash_commands` minus
  `terminal_slash_commands`). The latest full catalog is cached in
  `~/Library/Application Support/Catedra/slash-commands.json` and refreshed by every run, so autocomplete works before the
  first run of a session. Without a cache, a local scan (no tokens spent) reads `SKILL.md` / `commands/*.md` frontmatter from
  `~/.claude` and every `.claude` folder between the scope and the home directory. Terminal-only commands (`/doctor`,
  `/login`, …) are hidden because they do nothing in headless mode.
- Cátedra commands are handled by the app and never sent to Claude; they override same-named CLI builtins:
  `/resume` (picker of past runs of this scope, optionally all scopes; continues with `--resume <session_id>`),
  `/new` (alias `/clear`), `/model <model|predeterminado>`, `/permisos <solo-lectura|aceptar|auto|sin-restricciones>` (options depend on the provider),
  `/recetas`, `/terminal`, `/archivos`.

### Testing notes
- Real-CLI smoke tests (temp dir, never the workspace) are opt-in: `CATEDRA_LIVE_CLAUDE=1` (model `haiku`),
  `CATEDRA_LIVE_AGY=1` (expects a successful "OK") and `CATEDRA_LIVE_OPENCODE=1` (expects a clean failed run when the
  configured provider is unreachable; OpenCode retries about a minute before reporting). With xcodebuild, pass them as
  `TEST_RUNNER_CATEDRA_LIVE_AGY=1 xcodebuild … test -only-testing:CatedraTests/CLIAgentRunnerTests`.
- Under tests, or with `CATEDRA_SKIP_KEYCHAIN=1`, the app does not touch the Keychain. Every rebuild changes the ad-hoc
  signature, which makes macOS show a blocking Keychain access prompt that would hang the test host.
