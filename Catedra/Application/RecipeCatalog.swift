import Foundation

/// Built-in recipes plus pure filtering and template rendering.
/// Scope rule: there is deliberately no recipe that answers a live graded quiz or exam; exam/quiz recipes are
/// preparation and practice only.
enum RecipeCatalog {
    private static let activityPreamble = """
    Trabajas dentro de la carpeta de la actividad «{{activityName}}» ({{kind}}) de la materia «{{courseName}}». \
    Fecha límite: {{due}}.

    Antes de empezar, lee `enunciado.md` y el material de la carpeta `material/`; si hace falta, consulta también \
    los contenidos de la materia en `../../contenidos/`. Escribe tus resultados únicamente en `entrega/`, \
    `preparacion/` o `apuntes/` de esta carpeta; no modifiques `enunciado.md`, `material/` ni ningún archivo \
    generado por la sincronización. Todo lo que produzcas es un borrador para que el estudiante lo revise \
    manualmente: no envíes nada a SAIA.
    """

    private static let preparationRule = """
    Regla importante: esto es solo preparación y práctica. No resuelvas ni respondas la evaluación real calificada \
    de esta actividad, ni intentes anticipar sus respuestas exactas; enfócate en que el estudiante aprenda.
    """

    private static let coursePreamble = """
    Trabajas en la carpeta de la materia «{{courseName}}». Antes de empezar, lee los contenidos de `contenidos/` \
    y los enunciados de `actividades/`. Escribe tus resultados únicamente en la carpeta `apuntes/` de la materia \
    (créala si no existe); no modifiques `contenidos/`, `actividades/`, `foros/` ni `README.md`, porque son \
    carpetas y archivos generados por la sincronización. Todo lo que produzcas es un borrador para que el \
    estudiante lo revise manualmente.
    """

    /// Spoken script for the notch teleprompter; the agent saves it and opens it with a `catedra://guion` link.
    private static let scriptTask = """


    Tarea: escribe un guion hablado para que el estudiante lo lea en voz alta en el teleprompter de Cátedra (una \
    franja en el notch del Mac) mientras graba su pantalla o presenta. Si en la conversación no está claro qué va a \
    presentar, cuánto debe durar o ante quién, pregúntalo antes de escribir.

    Reglas de redacción: lenguaje hablado y natural, en primera persona; frases cortas (idealmente menos de 20 \
    palabras) que se puedan decir de un tirón; nada de tablas, viñetas anidadas, siglas sin explicar ni citas \
    bibliográficas. Calcula unas 130 a 150 palabras por minuto para ajustarte a la duración. Usa solo información \
    de la materia y del estudiante; no inventes datos ni resultados.

    Formato del archivo (Markdown):
    ---
    tipo: guion
    titulo: <título corto>
    duracion: <por ejemplo 3m>
    idioma: es-VE
    ---
    ## <Sección, por ejemplo Diapositiva 1 o Demo>
    <Texto que se dice en voz alta.>

    Usa marcas entre corchetes para indicaciones que no se leen: [pausa], [clic], [demo], [respira]. Cada sección \
    `##` es un punto al que el estudiante puede saltar.

    Guarda el guion en `apuntes/guiones/<nombre-corto>.md` (crea la carpeta si no existe). Después actívalo en \
    el notch ejecutando este comando con la ruta absoluta del archivo (sin `-g` el comando taparía la presentación):
    open -g "catedra://guion/activar?archivo=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "<ruta absoluta>")"
    Si no puedes ejecutar comandos, dile al estudiante que escriba `/guion <nombre-corto>` en este chat. Termina \
    con la duración estimada y los atajos: ⌃⌥Espacio pausa, ⌃⌥← y ⌃⌥→ frase anterior o siguiente, ⌃⌥↑ y ⌃⌥↓ \
    sección, ⌃⌥Esc cerrar.
    """

    static let all: [Recipe] = [
        Recipe(
            id: "draft-docx", title: "Borrador de entrega", subtitle: "Documento .docx con las Normas UFT",
            symbol: "doc.badge.gearshape", applicability: .activity([.tarea]),
            template: activityPreamble + """


            Tarea: redacta un borrador de la entrega de esta actividad. Sigue al pie de la letra las reglas de \
            «Written deliverables» del CLAUDE.md del espacio de trabajo: carga el skill `normas-uft` antes de \
            redactar, copia `Plantilla UFT.docx` (carpeta raíz UFT) a `entrega/` sin editar la plantilla original, \
            completa la portada y usa los estilos de título de Word. Genera el .docx con el skill `docx`, convierte \
            el resultado a PDF y revisa visualmente el formato antes de terminar. Si el enunciado exige fuentes, \
            cita únicamente material de la materia y referencias reales. Al final, resume qué debe revisar el \
            estudiante.
            """),
        Recipe(
            id: "review-draft", title: "Revisar entrega", subtitle: "Compara tu entrega con el enunciado y las Normas UFT",
            symbol: "checklist", applicability: .activity([.tarea]),
            template: activityPreamble + """


            Tarea: revisa la entrega del estudiante antes de que la envíe. Eres un revisor: solo evalúas y sugieres; \
            no reescribas ni corrijas el trabajo del estudiante, no completes partes que falten y no resuelvas la \
            actividad. No modifiques ningún archivo de `entrega/`.

            1. Lee los archivos de `entrega/` (si está vacía, no inventes nada: escribe un resultado con `requirements` \
            vacío y explícalo en `summary`).
            2. Extrae los requisitos explícitos de `enunciado.md` y, solo si existe, de `rubrica.md`.
            3. Carga el skill `normas-uft` y revisa el formato académico: portada, márgenes, tipografía, citas y \
            referencias bibliográficas.
            4. Para cada requisito indica si se cumple, se cumple parcialmente o falta, con evidencia concreta (qué \
            parte o página de la entrega lo respalda o por qué falta). Cuando no sea cumple, añade una sugerencia \
            breve de qué debería revisar el estudiante, sin redactar el contenido por él.

            Escribe el resultado como JSON válido (sin texto adicional ni bloques de código) en \
            `\(DraftReviewFile.relativePath)` con esta estructura:
            {"generatedAt": "<fecha y hora ISO 8601>", "summary": "<resumen de dos o tres frases>", \
            "requirements": [{"id": "r1", "requirement": "<requisito>", "status": "cumple" | "parcial" | "falta", \
            "evidence": "<evidencia>", "suggestion": "<opcional>", "source": "enunciado" | "rubrica" | "normas-uft"}]}

            \(preparationRule)
            """),
        Recipe(
            id: "work-plan", title: "Plan de trabajo", subtitle: "Pasos y material que debes leer",
            symbol: "list.bullet.clipboard", applicability: .activity([.tarea]),
            template: activityPreamble + """


            Tarea: divide la actividad en pasos concretos y ordenados hasta la fecha límite. Para cada paso indica \
            qué material de `material/` o de `contenidos/` debe leer el estudiante, cuánto tiempo estimado requiere \
            y qué se obtiene al terminarlo. Guarda el plan como `apuntes/plan-de-trabajo.md` y presenta un resumen \
            breve en tu respuesta.
            """),
        Recipe(
            id: "script-activity", title: "Crear guion", subtitle: "Guion para leer en el notch mientras presentas",
            symbol: "text.word.spacing", applicability: .activity([.tarea]),
            template: activityPreamble + scriptTask),
        Recipe(
            id: "study-guide", title: "Guía de estudio", subtitle: "Temas, conceptos y ejercicios de práctica",
            symbol: "book", applicability: .activity([.cuestionario, .examen]),
            template: activityPreamble + """


            Tarea: elabora una guía de estudio para prepararse para esta evaluación. Identifica en el enunciado y en \
            los contenidos los temas que cubre, resume cada uno con claridad, señala fórmulas o definiciones \
            esenciales y propone ejercicios de práctica con una pista (no la solución completa de la evaluación). \
            Guárdala en `preparacion/guia-de-estudio.md`.

            \(preparationRule)
            """),
        Recipe(
            id: "practice-exam", title: "Simulacro con corrección", subtitle: "Examen de práctica y solucionario",
            symbol: "checkmark.rectangle.stack", applicability: .activity([.cuestionario, .examen]),
            template: activityPreamble + """


            Tarea: genera un simulacro del mismo estilo y dificultad que esta evaluación (tipos de pregunta, \
            extensión y temas), usando preguntas originales basadas en los contenidos. Guarda el simulacro en \
            `preparacion/simulacro.md` y las respuestas con su explicación en un archivo aparte, \
            `preparacion/simulacro-respuestas.md`, para que el estudiante pueda practicar primero y corregir después.

            \(preparationRule)
            """),
        Recipe(
            id: "key-concepts", title: "Repaso de conceptos clave", subtitle: "Resumen rápido para repasar",
            symbol: "lightbulb", applicability: .activity([.cuestionario, .examen]),
            template: activityPreamble + """


            Tarea: prepara un repaso de una o dos páginas con los conceptos clave que cubre esta evaluación: \
            definiciones, relaciones importantes, errores comunes y preguntas de autocomprobación al final. \
            Guárdalo en `preparacion/repaso-conceptos-clave.md`.

            \(preparationRule)
            """),
        Recipe(
            id: "course-summary", title: "Resumen de la materia", subtitle: "Un resumen por unidad",
            symbol: "text.book.closed", applicability: .course,
            template: coursePreamble + """


            Tarea: crea un resumen por unidad de la materia a partir de `contenidos/`. Escribe un archivo por unidad \
            en `apuntes/` (por ejemplo `apuntes/resumen-unidad-01.md`) con ideas principales, definiciones y \
            ejemplos, y un `apuntes/resumen-general.md` que enlace todas las unidades. Indica al final qué unidades \
            no tenían contenido suficiente.
            """),
        Recipe(
            id: "study-plan", title: "Plan de estudio", subtitle: "Hasta el próximo parcial",
            symbol: "calendar.badge.clock", applicability: .course,
            template: coursePreamble + """


            Actividades de la materia con sus fechas límite:
            {{activitiesList}}

            Tarea: propone un plan de estudio semana a semana hasta el próximo parcial o evaluación importante, \
            teniendo en cuenta las fechas anteriores. Para cada bloque indica los temas y el material de \
            `contenidos/` que debe repasarse y las actividades que hay que entregar. Guárdalo en \
            `apuntes/plan-de-estudio.md`.
            """),
        Recipe(
            id: "organize-notes", title: "Organizar mis apuntes", subtitle: "Ordena y enlaza tus notas",
            symbol: "folder.badge.gearshape", applicability: .course,
            template: coursePreamble + """


            Tarea: revisa mis apuntes de la materia (la carpeta `apuntes/` y las carpetas `apuntes/` y \
            `preparacion/` de cada actividad) y propón una organización clara por unidad: crea un índice \
            `apuntes/indice.md` que enlace cada nota, detecta duplicados o notas incompletas y sugiere qué falta \
            por estudiar. No muevas ni borres archivos existentes; solo crea el índice y los archivos nuevos en \
            `apuntes/`.
            """),
        Recipe(
            id: "flashcards", title: "Generar tarjetas de repaso", subtitle: "Tarjetas pregunta y respuesta para repasar",
            symbol: "rectangle.on.rectangle", applicability: .course,
            template: coursePreamble + """


            Tarea: crea tarjetas de repaso (pregunta y respuesta) a partir del material de `contenidos/`. Cada tarjeta \
            cubre una sola idea: definiciones, relaciones, fórmulas, procedimientos y errores comunes. Las preguntas \
            deben entenderse sin ver el material y las respuestas ser breves (una a tres frases). Genera solo con el \
            material de la materia; no uses ni respondas preguntas de evaluaciones que estén en curso.

            Escribe el resultado como JSON válido (sin texto adicional ni bloques de código) en \
            `\(FlashcardFile.relativePath)` con esta estructura:
            {"generatedAt": "<fecha y hora ISO 8601>", "cards": [{"id": "<identificador estable>", \
            "question": "<pregunta>", "answer": "<respuesta>", "source": "<ruta relativa a la carpeta de la materia, \
            por ejemplo contenidos/Unidad 1/tema.pdf>", "tags": ["<opcional>"]}]}

            Reglas del archivo:
            - Si `\(FlashcardFile.relativePath)` ya existe, léelo primero y combínalo: conserva todas las tarjetas \
            existentes con su `id`, `question` y `answer` (solo puedes corregir un error evidente, nunca cambiar el \
            `id`), no borres ninguna y agrega únicamente tarjetas nuevas sobre temas que aún no estén cubiertos. El \
            progreso de repaso del estudiante se guarda por `id`, así que un `id` cambiado o eliminado pierde ese progreso.
            - Cada `id` es único y estable: un texto en minúsculas con guiones derivado del tema (por ejemplo \
            `unidad-2-ley-de-ohm-01`), nunca un número que dependa del orden.
            - Mantén el archivo legible también para otros agentes: UTF-8, indentado con dos espacios, una tarjeta por \
            bloque y sin comentarios.
            - Al final, indica cuántas tarjetas había, cuántas agregaste y qué unidades tenían poco contenido.
            """),
        Recipe(
            id: "quiz", title: "Cuestionario de práctica", subtitle: "Preguntas de opción múltiple y respuesta corta",
            symbol: "questionmark.square.dashed", applicability: .course,
            template: coursePreamble + """


            Tarea: prepara un cuestionario de práctica de unas 10 a 15 preguntas originales, mezclando opción múltiple \
            (3 o 4 opciones plausibles, una sola correcta) y respuesta corta, a partir del material de `contenidos/`. \
            Cada pregunta debe incluir la respuesta correcta y una explicación breve. Es solo práctica: usa el \
            material de la materia y no reproduzcas, resuelvas ni anticipes las preguntas de evaluaciones que estén en \
            curso en `actividades/`.

            Escribe el resultado como JSON válido (sin texto adicional ni bloques de código) en \
            `\(QuizFile.relativePath)` con esta estructura:
            {"generatedAt": "<fecha y hora ISO 8601>", "questions": [{"id": "q1", "type": "multiple-choice" | \
            "short-answer", "question": "<pregunta>", "options": ["<solo en opción múltiple>"], \
            "answer": "<en opción múltiple, el texto exacto de la opción correcta>", "explanation": "<explicación>", \
            "source": "<ruta relativa a la carpeta de la materia>"}]}

            Mantén el archivo legible también para otros agentes: UTF-8, indentado con dos espacios y sin comentarios. \
            Si el archivo ya existe, reemplázalo por un cuestionario nuevo (no necesitas conservar las preguntas anteriores).
            """),
        Recipe(
            id: "script-course", title: "Crear guion", subtitle: "Guion para leer en el notch mientras presentas",
            symbol: "text.word.spacing", applicability: .course,
            template: coursePreamble + scriptTask),
    ]

    static func recipes(for scope: AgentScope) -> [Recipe] {
        all.filter { $0.applies(to: scope) }
    }

    static func recipe(id: String) -> Recipe? {
        all.first { $0.id == id }
    }

    /// Substitutes placeholders. `activities` feeds `{{activitiesList}}` (course scope).
    static func render(_ recipe: Recipe, scope: AgentScope, activities: [Activity], formatDate: (Date) -> String) -> String {
        var values: [String: String] = [:]
        switch scope {
        case .activity(let activity):
            values["activityName"] = activity.name
            values["courseName"] = activity.courseName
            values["kind"] = activity.kind.displayName
            values["due"] = activity.due.map(formatDate) ?? "sin fecha límite"
        case .course(let course):
            values["courseName"] = course.name
            let lines = activities.map { activity -> String in
                let due = activity.due.map(formatDate) ?? "sin fecha"
                return "- \(activity.kind.displayName): \(activity.name) (\(due))"
            }
            values["activitiesList"] = lines.isEmpty ? "- (sin actividades registradas)" : lines.joined(separator: "\n")
        }
        var text = recipe.template
        for (key, value) in values { text = text.replacingOccurrences(of: "{{\(key)}}", with: value) }
        return text
    }
}
