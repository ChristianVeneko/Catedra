# Catedra

Native macOS (SwiftUI) cockpit over a local mirror of a student's Moodle (SAIA, Universidad Fermin Toro). It reads the
workspace produced by `_sistema/sync_moodle.py` (bundled in the app), shows what is due, renders statements, manages your own files per
activity and can run the sync for you. UI copy is Spanish; code is English.

## Requirements
- macOS 15+, Xcode 26+ (developed with Xcode 27 / Swift 6)
- `xcodegen` (`brew install xcodegen`) only if you want to regenerate the project
- A Python 3.9+ with `requests` for syncing (the setup wizard checks it)

## Build
Open `Catedra.xcodeproj` in Xcode and run, or:

    xcodegen generate
    xcodebuild -project Catedra.xcodeproj -scheme Catedra -destination 'platform=macOS' build
    xcodebuild -project Catedra.xcodeproj -scheme Catedra -destination 'platform=macOS' test

The app is not sandboxed (it reads `~/Desktop/UFT` and runs `python3`) and is signed with the team's Apple Development identity
(automatic signing, team `28U4T9UK9R`) so the Keychain ACL ("Permitir siempre") survives rebuilds.
Settings (⌘,) hold the workspace path, Python interpreter and SAIA credentials.

## Architecture (hexagonal)
- `Domain/` pure types: `Domain/Onboarding/` (SemanticVersion, DependencyCheck + DependencyEvaluator/DependencyPlan, MoodleAuth, StarterInstructions), Activity, ActivityState, Course, CountdownFormatter, ActivityDiff, Agenda, SyncLogParser; `Domain/Agent/` AgentScope, AgentRun, AgentEvent, AgentProviderID, AgentOptions (permission levels, models), AgentEventParsing + ClaudeStreamParser / AntigravityStreamParser / OpenCodeEventParser, CancellationPolicy, ModelListParser, Recipe, SlashCommand, SlashCommandMatcher, SlashToken, AppCommand, SkillFrontmatter, PromptHistory, ScopeRelativePath
- `Application/` use cases: LoadWorkspace, Sync (installs the bundled script first), ImportFiles, RunAgent, RecipeCatalog
- `Ports/` protocols: WorkspaceReading, MoodleSyncing, CredentialStoring, FileImporting, AgentRunning, AgentProvider, AgentRunStoring, AgentNotifying, TerminalOpening, SlashCommandCatalogStoring, SlashCommandScanning, SyncScriptInstalling, MoodleAuthChecking, DependencyProbing, CommandStreaming
- `Adapters/` FileSystemWorkspace, PythonSyncAdapter, KeychainCredentialStore, FileSystemImporter, WorkspaceWatcher, CLIAgentRunner, ClaudeProvider / AntigravityProvider / OpenCodeProvider, BinaryLocator, AgentBinaryProbe, LoginShellEnvironment, JSONAgentRunStore, JSONSlashCommandCatalogStore, LocalSlashCommandScanner, GeneratedFilesScanner, TerminalLauncher, UserNotificationAdapter, SyncScriptInstaller, MoodleAuthChecker, DependencyProbe, BoundedProcess, CommandStreamer, WorkspaceInspector (+ StarterFilesWriter)
- `UI/` feature folders (Dashboard, Sidebar, ActivityDetail, Contents, Sync, Agent, Settings, Components)
- `App/` composition root (`AppContainer`) and `@Observable` models (including `OnboardingModel`)

## Setup wizard
A multi-step window (`OnboardingView`, scene id `onboarding`) opens on first launch (`onboardingCompleted` in
UserDefaults) and can be re-run from Settings ("Volver a ejecutar el asistente") or the app menu ("Asistente de
configuración…"). Launching with `-CatedraForceOnboarding YES` forces it once.
1. **Bienvenida**.
2. **Carpeta de datos**: pick an existing workspace or create a folder (`NSOpenPanel` with "Nueva carpeta"); it must be
   writable. A folder containing `_sistema/data/activities.json` is reported as "Se encontró un espacio existente con N
   actividades". Suggested folder for a new workspace: `~/Documents/Cátedra` (the current setting is kept when the user
   chose it or it already holds a synced workspace). For a NEW workspace without `CLAUDE.md`/`AGENTS.md`, a checkbox
   (default on) creates a starter `AGENTS.md` (layout and rules, English) and a `CLAUDE.md` containing `@AGENTS.md`.
   Existing files are never overwritten.
3. **Credenciales del SAIA**: stored in the Keychain; "Probar conexión" POSTs `username`, `password` and
   `service=moodle_mobile_app` to `https://saia.uft.edu.ve/login/token.php`. Only the verdict is kept: the token is
   discarded and neither value is logged. Can be skipped.
4. **Agente**: Claude Code, Antigravity or OpenCode with their marks, install state and the OpenCode ToS warning.
5. **Dependencias**: live checklist (Python >= 3.9, `requests`, the selected agent CLI = required; the other agents, Git
   and Node = optional) with versions, copyable install commands and "Volver a comprobar". "Instalar" (only on an explicit
   click) runs `python -m pip install --user requests` and streams its output. Commands run through the login-shell
   environment with timeouts (`DependencyProbe`); `/usr/bin` shims are never executed without Command Line Tools.
6. **Listo**: summary and "Sincronizar ahora". Finishing writes the settings (workspace, provider, interpreter), installs
   the sync script and sets the flag. If a required dependency is missing the wizard can still finish; a banner stays in
   the main window until it is fixed.

## Sync script bundling
`Catedra/Resources/Sync/sync_moodle.py` is the canonical script and ships in the app's Resources (tests under
`Resources/Sync/tests/` are excluded from the bundle). `SyncScriptInstaller` makes `<workspace>/_sistema/sync_moodle.py`
equal to the bundled copy (SHA-256 comparison), creates `_sistema/data/`, and, if a different script is already there,
copies it once to `sync_moodle.py.bak-<yyyyMMdd-HHmmss>` before overwriting. It runs when the wizard finishes and before
every sync; the script is then run as `python sync_moodle.py --root <workspace>` (`--root` or `CATEDRA_WORKSPACE`
override the default root, the parent of the script's folder).
Python tests (stdlib): `cd Catedra/Resources/Sync && python3 -m unittest discover -s tests -v` (needs `requests`).

## Richer SAIA data
Besides `activities.json`, the sync writes optional files under `_sistema/data/`. The app tolerates any of them missing or
malformed (empty result, never a crash), and old `activities.json` files still decode.
- `activities.json` gains optional keys, omitted when unknown: `opens`, `cutoff` (unix seconds, like `due`), `gradeRaw`,
  `gradeMax` (numbers), `feedback` (teacher feedback as plain text), `gradedAt` (unix seconds), `cmid`.
- `grades_<courseid>.json`: `{courseid, items[], total}` built from the same `gradereport_user_get_grade_items` response
  that renders the README table (no extra call). Item keys: `itemname, itemtype, itemmodule, cmid, graderaw,
  gradeformatted, grademin, grademax, weightraw, percentageformatted, feedback, gradedatesubmitted, gradedategraded`.
- `calendar.json`: array of `{id, name, courseid, course, eventtype, modulename, timestart, timeduration, url, cmid}` from
  `core_calendar_get_action_events_by_timesort` (last 7 days onward, up to 100 events).
- `rubrics/<cmid>.json` and a readable `rubrica.md` in the activity folder, from `core_grading_get_definitions`
  (`areaname=submissions`, `activeonly=1`), for assignments that define a rubric or marking guide.
The calendar and grading calls are optional: a Moodle exception (function not enabled for the mobile service), an HTTP
error or an unexpected shape logs one line to stderr and the sync continues unchanged. In Swift they load into
`WorkspaceSnapshot` (`gradeReports`, `calendarEvents`, `activitiesWithRubric`); the activity detail shows the teacher
feedback and the opening/cutoff dates.

## Calendar and study planner
The "Calendario" sidebar item (next to "Hoy") shows a week view (hours grid for classes and study blocks, a strip for
deadlines, weekly load: deadlines this week and planned study hours) and a month view (compact chips per day; the day list
sits in the middle column). Toolbar: Semana/Mes, previous/next, "Hoy", "+" and an export menu.
- `CalendarBuilder` (pure) merges activity dates (`due` = Entrega, `opens` = Apertura, `cutoff` = Cierre), Moodle calendar events
  (`meeting_start`/BigBlueButton = Clase, `due`, `close`, `open`, anything else = Evento) and study blocks (Estudio). A calendar
  event is dropped when it has the same `cmid` and the same instant as one of that activity's dates, so the activity (which links
  to the activity detail) wins. Clicking an activity opens its detail, a class opens its URL, a study block opens its editor.
  Course colors reuse `CoursePalette`.
- Study blocks (title, start, end, optional activity/course, notes, done) are stored in
  `~/Library/Application Support/Catedra/study-blocks.json` (tolerant decoding), never in the workspace. Click an empty slot,
  "+" or the palette action "Nuevo bloque de estudio" to create one; "Abrir calendario" is also in the palette.
- "Exportar a Calendario" (explicit, never automatic) requests full Calendar access through EventKit on first use, creates a
  calendar named "Cátedra" and upserts events for deadlines (30 min ending at the due time), classes and study blocks within
  30 days back to 1 year ahead. Each event carries a `catedra-id:<entry id>` marker in its notes; `CalendarExportPlanner` (pure)
  diffs desired vs existing events by that marker (create / update / delete / extra duplicates removed), so re-exporting never
  duplicates and entries that disappeared are removed. Only events with the marker in the "Cátedra" calendar are touched.
  Denied access shows a message pointing to System Settings. EventKit sits behind `CalendarEventStoring`; tests use a fake.
  The usage string is `NSCalendarsFullAccessUsageDescription` in `project.yml`.

## Grades dashboard
The "Notas" sidebar item (next to "Calendario") summarizes the `grades_<courseid>.json` files per subject. Detail view: totals,
a progress bar with the target marker, the "¿Cuánto necesito?" simulator, a Swift Charts cumulative-points chart (by
`gradedategraded`) and the item table. Palette: "Abrir notas".
- UFT accumulates by points, so every item weighs its `grademax` and teacher totals are never "fixed". Only `mod`/`manual` rows
  are summed (`category`/`course` rows are aggregates). `GradeCourseResolver` maps a report to its course folder by matching item
  `cmid`s against activities (fallback: calendar event course name); unmatched reports show as "Curso <id>".
- Formulas (`GradeCalculator`, pure): earned = sum of graded points that count (extra credit and grades above the maximum count in
  full); total possible = sum of `grademax` of counting items; graded possible = same over graded items; remaining = total -
  graded possible; current % = earned / graded possible; projected = current % x total; target points = target % x total; needed
  = max(0, target points - earned), average required = needed / remaining. Status: passed (earned >= target), unreachable
  (earned + remaining < target), at risk (projection < target), otherwise on track.
- "Extra" and "Bonus" items add earned points but never possible points. Makeups ("Diferido", "Sustitutivo") are left out of the
  possible points until graded; any item can be marked "No cuenta" to leave the arithmetic entirely (use it on the exam a makeup
  replaces).
- Subjects can merge courses (e.g. "Electrónica II" + "Laboratorio de Electrónica II", 50 + 50 = 100). A "Laboratorio de X"
  course matching a course named "X" (accent/case insensitive) is suggested; accept, dismiss or merge by hand from "Agrupar materias".
- The passing target defaults to 50 % of the total and is stored per subject (merged subjects use the sorted course folders as id).
- Persistence: `~/Library/Application Support/Catedra/grade-settings.json` (`groups`, `targets`, `excludedItems`,
  `dismissedSuggestions`; tolerant decoding), never the workspace.
- Notifications: `GradeChangeDetector` compares the snapshots before and after a sync (grade reports plus the activities'
  `grade`/`feedback`) and adds `gradeChanges` to `ActivityDiff` (shown in the sync summary). A system notification fires for new
  or changed grades and new teacher feedback when Settings > "Notas" is on. That toggle is independent of deadline reminders; until
  the user chooses, it is on only if the notification permission was already granted. Nothing is reported for a course's first sync.

## Images
The script downloads the `<img>` images of every HTML it converts (assignment and quiz statements, pages and books,
labels, forum posts) into an `_imagenes/` folder next to the generated Markdown and rewrites the references to relative
paths (`![alt](_imagenes/blobid0.jpg)`). SAIA (`/pluginfile.php`) images use the token; external http(s) images are
fetched anonymously with a timeout and keep their remote URL on failure. Existing files are not downloaded again;
`--no-files` downloads nothing (images already on disk are still referenced). `_imagenes/` is generated output and is
overwritten by sync. The script also repairs mojibake in converted text (`vÃÂ­deo` becomes `vídeo`).
In the app, `MarkdownParser` splits inline images into blocks (several images on one line become several blocks) and
`MarkdownImageView` renders local files with `NSImage` (async, rounded, click for Quick Look) and remote ones with
`AsyncImage`; missing images show a placeholder with the alt text and a link.

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

## Menu bar
A `MenuBarExtra` (style `.window`, toggle in Settings "Mostrar en la barra de menús", default on) shows a graduation-cap glyph
plus the countdown to the next open deadline ("1 d 7 h"), orange under 24 h and red under 3 h (`MenuBarLabel`, pure; the label is
rendered as an image so the color survives; the text can be hidden in Settings). The popover has the next activity card
("Abrir" brings the main window forward and navigates to it, "SAIA" opens the URL), the next 5 pending activities, running
agents (animated provider mark, elapsed time, "Ver") and the footer: "Sincronizar" (option-click or the menu for "sin archivos";
shows progress through `SyncModel`), "Abrir Cátedra", Ajustes, Salir. The minute refresh comes from `MinuteClock` (label) and
`TimelineView(.everyMinute)` (popover). The main window is a single-instance `Window` scene (id `main`).

## Notifications
`DeadlineReminderPlanner` (pure) turns activities into reminders at 48 h / 24 h / 3 h (plus an optional custom offset) before
the due date: past fire dates, submitted and undated activities are skipped, ids are stable
(`catedra.deadline.<folder>|<hours>|<due>`) so re-planning is idempotent, title "Vence en 24 h: <name>", body
"<course> · <type> · <due, America/Caracas>". `ReminderModel` diffs the pending `UNUserNotificationCenter` requests against the
plan after every workspace load, sync and settings change (only our prefix is touched; 60 pending max, nearest first) through the
`NotificationScheduling` port. Permission is requested lazily when reminders are enabled; Settings shows the state, a button
to open System Settings when denied and "Enviar notificación de prueba". Reminders are **off by default**. Tapping a
notification opens the app on that activity (`NotificationRouter`, `userInfo.activityID`).

## Command palette
⌘K (toolbar magnifier, menu "Ir > Buscar…") opens a Spotlight-style overlay: type, ↑/↓, Enter, Esc. `PaletteMatcher` (same tiers
as `SlashCommandMatcher`, every word must match) ranks per section: Actividades, Materias (open + "Agente de <materia>"),
Contenidos (files under each `contenidos/`, `_imagenes` excluded; `ContentIndexModel` builds the index lazily in the
background and refreshes it on workspace changes), Acciones (sync, sync sin archivos, Ajustes, Asistente, Cambiar agente,
Mostrar Hoy) and Recetas ("Ejecutar <receta> en <actividad seleccionada o que coincide>", opens the agent panel with the prompt
prefilled, never runs it). With an empty query it shows the last 10 items (`PaletteRecents`, UserDefaults).

## Background sync on launch
After the workspace loads, `LaunchSyncPolicy` (pure) starts a silent sync when onboarding is completed, SAIA credentials and a
Python interpreter exist, the mode is not "Desactivada" (Settings > Sincronización: completa / solo datos / desactivada) and the
last successful sync is older than N minutes (default 30). It shares the single `SyncModel`: nothing starts while a sync runs,
and pressing ⌘R during a background sync just opens the sheet on the live log. The script runs with utility QoS. A toolbar
indicator and the "Hoy" header show "Sincronizando…"; the result appears as a 5 s toast (`SyncSummary`, "2 actividades nuevas ·
1 fecha cambió" or "Sin cambios"), a local notification if the app is in the background and there are new activities or moved
deadlines, or a warning banner with "Ver detalles" on failure. Set `CATEDRA_DISABLE_LAUNCH_SYNC=1` to disable it (always off
under tests).
