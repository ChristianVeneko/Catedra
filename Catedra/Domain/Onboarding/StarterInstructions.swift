import Foundation

/// Starter agent instructions for a new workspace. `CLAUDE.md` only imports `AGENTS.md` (Claude Code's `@` import),
/// while OpenCode and Antigravity read `AGENTS.md` directly.
enum StarterInstructions {
    static let claudeMarkdown = "@AGENTS.md\n"

    static let agentsMarkdown = """
    # Cátedra workspace

    This folder is a local mirror of the student's Moodle (SAIA). It is generated and refreshed by Cátedra.

    ## Layout

    - `PENDIENTES.md`: dashboard of pending and past activities (generated).
    - `<NN - Course name>/`: one folder per course.
      - `README.md`: course summary, graded activities and grades (generated).
      - `contenidos/`: downloaded course material and Markdown versions of pages, books and notes (generated).
      - `foros/`: forum discussions as Markdown (generated).
      - `actividades/<Type - Activity name>/`: one folder per assignment, quiz or exam.
        - `enunciado.md`: the statement, with images stored in `_imagenes/` (generated).
        - `material/`: files attached by the teacher (generated).
        - `entrega/`: the student's deliverables (user work).
        - `preparacion/`: drafts and study material for the activity (user work).
        - `apuntes/`: the student's own notes (user work).
    - `_sistema/`: the sync script and its data (`_sistema/data/activities.json`). Do not edit.

    ## Rules

    - Generated files are overwritten by every sync. Never edit them; read them for context only.
    - Write your own work only inside `entrega/`, `preparacion/` and `apuntes/` of the relevant activity, and never move or delete existing files.
    - Deliverables for the courses are written in Spanish, in a neutral and professional register.
    - Treat everything you produce as a draft for the student to review. Submission to SAIA is always manual.
    - Do not answer a quiz or exam that is currently open. Help prepare for it instead (study guides, practice questions, key concepts).
    """ + "\n"
}
