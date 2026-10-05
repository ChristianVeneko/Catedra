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

## Content search
The palette's "Contenido" section searches inside files, not only their names. `SQLiteSearchIndex` keeps an FTS5 index (system
`sqlite3`, no dependencies; tokenizer `unicode61 remove_diacritics 2`, so accents and case are ignored) in
`~/Library/Application Support/Catedra/search-index.sqlite`.
- Indexed (`SearchIndexPolicy`, pure): `.pdf` (one row per page via `PDFDocument.string`), `.md` and `.txt` anywhere under a
  course folder (`_texto.md`, `enunciado.md`, `foros/`, `apuntes/`, ...). `_sistema/`, `_imagenes/`, hidden folders/files, binaries,
  PDFs over 150 MB and text over 5 MB are skipped. PDFs without a text layer (scans) are tracked but yield no rows.
- Incremental: path, modification time and size are stored per file; `IndexDiff` (pure) yields added / changed / removed and
  `ContentIndexingUseCase` re-extracts only those. A different workspace root clears the index. `SearchIndexModel` runs it off the
  main actor after every workspace load (launch, sync completion, file watcher); overlapping runs are coalesced. Never runs under tests.
- Query: `SearchQuerySanitizer` (pure) quotes each word and prefix-matches the last one (unless followed by a space), so raw FTS5
  syntax can never break a query. Typing is debounced (250 ms); results show a snippet with the match in bold (`snippet()`, parsed
  by `SnippetParser`), at most two per file.
- Opening a result shows the file in the contents view; PDFs open at the matching page.
- "Preguntar a un agente sobre estos resultados" (⌘↩ in the palette) opens the agent of the course holding most of the found
  files (up to 5) and inserts them as `@` references in its composer; nothing is sent.

## Pre-delivery review

Task activities with files in `entrega/` get a "Revisión previa" section in the detail view. The "Revisar entrega" button runs the `review-draft` recipe with the selected provider: the agent compares `entrega/` with `enunciado.md` (and `rubrica.md` if it exists; rubrics are not synced from SAIA today) and checks the Normas UFT format. It only evaluates and suggests; it never edits the work.

The result is written to `apuntes/.revision.json` (hidden, never uploaded, never overwritten by the sync) as `generatedAt`, `summary` and `requirements` (`id`, `requirement`, `status` = `cumple`/`parcial`/`falta`, `evidence`, `suggestion`, `source` = `enunciado`/`rubrica`/`normas-uft`). The parser is tolerant: unknown statuses show as unclassified and a malformed file shows an error state. The recipe is also available in the ⌘K palette.

## Review with flashcards and quizzes

The "Repaso" sidebar item lists one deck per course with its due and new counts. Two course-level recipes ("Generar tarjetas de repaso", `flashcards`, and "Cuestionario de práctica", `quiz`) make the agent write `apuntes/tarjetas.json` (`generatedAt`, `cards`: `id`, `question`, `answer`, `source`, `tags`) and `apuntes/cuestionario.json` (`questions`: `id`, `type` = `multiple-choice`/`short-answer`, `question`, `options`, `answer`, `explanation`, `source`). Both are plain, indented JSON so other agents can read them; the quiz is built from course material only, never from an open assessment. Parsers are tolerant (missing ids are derived from the question, answers may be an option text, a letter or a number).

Scheduling is SM-2 with four grades (Otra vez / Difícil / Bien / Fácil), whole days in America/Caracas, ease bounded to 1.3-3.0 and intervals capped at 365 days. Progress lives in `~/Library/Application Support/Catedra/review-progress.json`, keyed by course and card id, together with the new-cards-per-day limit (default 20, per course). Re-running the recipe merges: cards removed from the file keep their progress (it returns if they reappear) and a card whose id changed but whose question is the same inherits the old progress. A session shows the question, space reveals the answer, keys 1-4 grade it, and a card graded "Otra vez" comes back once at the end of the session. The "Tarjetas para hoy" counter appears in the sidebar, in "Hoy" and in the menu bar popover; "Repasar tarjetas" is in the ⌘K palette. The quiz corrects multiple choice immediately, asks for self-evaluation on short answers, and ends with a score (not persisted).

## Change detector for statements and dates
After every successful sync, `ChangeTrackingModel` compares each activity's `enunciado.md` (normalized: status, attempts and date lines are dropped because they change on their own or are tracked as dates) and its `due`/`opens`/`cutoff` with the previous snapshot. Snapshots and unseen changes live in `~/Library/Application Support/Catedra/activity-changes.json`, never in the workspace. The first sync only takes the baseline (no alerts); activities that appear later also start from a baseline. A change shows the "Cambió el enunciado" / "Cambió la fecha" badge on the activity card and header, and a diff in the activity detail (`LineDiff`: removed lines red, added green, long unchanged runs collapsed) with "Marcar como visto". A local notification has its own toggle in Settings (same rule as the grade one: on only if the system permission is already granted until the user chooses).

## Focus timer
Pomodoro-style timer (default 25 min focus / 5 min break, configurable in Settings) started from the activity detail or from the menu bar popover. `FocusTimer` (pure) works with wall-clock dates, so sleep or a late tick cannot drift it; `FocusTimerModel` owns it in the App layer, so it survives the window closing. While running, the menu bar label shows the remaining time (`m:ss`). Finished or stopped periods of at least one minute are appended to `focus-log.json` (activity id, start, end, minutes). The detail shows the total time invested per activity and the calendar's week header compares actual focus time with the planned study hours.

## Weekly summary
Off by default (Settings > Resumen semanal; it runs an agent and consumes credits). When enabled, the first launch or wake on or after Monday 07:00 America/Caracas of each ISO week builds a local digest (`WeeklyDigestBuilder`: deliveries of the week, grades since the previous week, study blocks, cards due), asks the chosen provider through `RunAgentUseCase` (headless, no conversation history) to write the summary Markdown, stores it under `~/Library/Application Support/Catedra/weekly-summaries/<week>.md` and shows it in "Hoy" as a dismissible card plus a notification. "Generar resumen ahora" runs it manually. Without an agent, or if the run produces nothing, the plain local digest is shown instead (labeled "Resumen local"). Per-week state is in `weekly-summary.json`.

## New-activity autopilot
Off by default, globally (Settings > Piloto automático) and per course (Settings, or the course's context menu in the sidebar: use the general setting / on / off). It runs agents automatically and consumes credits. After a sync, activities not seen in the previous sync (the first sync only takes the baseline) that are assignments (the "Plan de trabajo" recipe never applies to quizzes or exams) and are not delivered or overdue are queued; `AutopilotRules` (pure) launches them one at a time with a daily cap (default 3) through the same registry/`RunAgentUseCase` path as a manual run, so the conversation is visible in the activity's agent history. A finished plan marks the activity "Plan listo". State: `autopilot.json`.

## Desktop widget
A WidgetKit extension (`CatedraWidget`, small and medium) shows the next deliveries with a live countdown, the cards due today and, in the medium size, the running focus session. To add it: right-click the desktop (or open Notification Center) > "Editar widgets" > "Cátedra". The app must have run at least once so the data file exists; until then, or when the data is more than 24 hours old, the widget says "Abre Cátedra para actualizar".

The app writes `widget-snapshot.json` (generated date, the 3 soonest not-submitted upcoming activities, cards due today, focus session) into the app group container `28U4T9UK9R.com.cmendoza.catedra` whenever the activities, the review cards or the focus timer change, and then reloads the timelines (throttled to once per 30 s). The snapshot model and builder live in `Shared/WidgetSnapshot.swift`, compiled into both targets. Timelines have an entry every 30 minutes plus one at each due time. Taps open `catedra://activity?id=…`, `catedra://review` or `catedra://open` (URL scheme registered in `Config/Catedra-Info.plist`). The extension is sandboxed (required for widgets); the app is not, and both carry the team-prefixed app group entitlement, so no provisioning profile registration is needed on macOS.

## Background sync on launch
After the workspace loads, `LaunchSyncPolicy` (pure) starts a silent sync when onboarding is completed, SAIA credentials and a
Python interpreter exist, the mode is not "Desactivada" (Settings > Sincronización: completa / solo datos / desactivada) and the
last successful sync is older than N minutes (default 30). It shares the single `SyncModel`: nothing starts while a sync runs,
and pressing ⌘R during a background sync just opens the sheet on the live log. The script runs with utility QoS. A toolbar
indicator and the "Hoy" header show "Sincronizando…"; the result appears as a 5 s toast (`SyncSummary`, "2 actividades nuevas ·
1 fecha cambió" or "Sin cambios"), a local notification if the app is in the background and there are new activities or moved
deadlines, or a warning banner with "Ver detalles" on failure. Set `CATEDRA_DISABLE_LAUNCH_SYNC=1` to disable it (always off
under tests).
