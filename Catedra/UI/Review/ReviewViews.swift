import SwiftUI

/// Content column of "Repaso": one row per course with its due and new counts.
struct ReviewDecksView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let review = container.review
        let today = ReviewDay(date: container.clock.now)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repaso").font(.largeTitle.weight(.bold))
                    Text(ReviewSummary.todayText(review.todayCount(today: today))).foregroundStyle(.secondary)
                }
                HStack {
                    Stepper(value: Binding(get: { review.newCardsPerDay }, set: { review.setNewCardsPerDay($0) }), in: 0...200, step: 5) {
                        Text("Tarjetas nuevas por día y materia: \(review.newCardsPerDay)")
                    }
                    .help("Máximo de tarjetas nuevas que se introducen cada día en cada materia")
                }
                .font(.callout).foregroundStyle(.secondary)
                if let error = review.saveError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                }
                ForEach(container.workspace.snapshot.courses) { course in
                    DeckRow(course: course, today: today)
                }
                if container.workspace.snapshot.courses.isEmpty {
                    Text("Aún no hay materias sincronizadas.").foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle("Repaso")
        .navigationSplitViewColumnWidth(min: 380, ideal: 460, max: 640)
        .onAppear { reload() }
    }

    private func reload() {
        container.review.reload(courses: container.workspace.snapshot.courses, root: container.workspace.root)
    }
}

private struct DeckRow: View {
    @Environment(AppContainer.self) private var container
    let course: Course
    let today: ReviewDay

    var body: some View {
        let review = container.review
        let color = CoursePalette.color(for: course)
        let counts = review.counts(for: course.id, today: today)
        let selected = review.selectedCourseID == course.id
        Button {
            review.selectedCourseID = course.id
            if case .overview = review.mode {} else { review.endSession(); review.endQuiz() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: CoursePalette.symbol(for: course)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.name).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    switch review.state(for: course.id) {
                    case .missing:
                        Text("Sin tarjetas todavía").font(.callout).foregroundStyle(.secondary)
                    case .invalid:
                        Label("Archivo de tarjetas ilegible", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    case .loaded:
                        HStack(spacing: 10) {
                            countLabel(counts.due, "por repasar", .orange)
                            countLabel(counts.new, "nuevas", .blue)
                            Text("\(counts.total) en total").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                if counts.today > 0 {
                    Text("\(counts.today)").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(color)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: color, selected: selected)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func countLabel(_ count: Int, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count) \(title)").font(.callout.weight(.medium)).monospacedDigit()
        }
    }
}

/// Detail column of "Repaso": deck overview, study session or quiz.
struct ReviewDetailView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let review = container.review
        switch review.mode {
        case .studying(let id):
            if let course = course(id) { StudySessionView(course: course).id("study-\(id)") }
        case .quiz(let id):
            if let course = course(id) { QuizView(course: course).id("quiz-\(id)") }
        case .overview:
            if let id = review.selectedCourseID, let course = course(id) {
                DeckOverview(course: course)
            } else {
                ContentUnavailableView("Seleccione una materia", systemImage: "rectangle.on.rectangle",
                                       description: Text("Elija una materia para repasar sus tarjetas o practicar con un cuestionario."))
            }
        }
    }

    private func course(_ id: String) -> Course? { container.workspace.snapshot.courses.first { $0.id == id } }
}

private struct DeckOverview: View {
    @Environment(AppContainer.self) private var container
    let course: Course

    var body: some View {
        let review = container.review
        let color = CoursePalette.color(for: course)
        let counts = review.counts(for: course.id, today: ReviewDay(date: container.clock.now))
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(course.name).font(.largeTitle.weight(.bold))
                switch review.state(for: course.id) {
                case .missing:
                    Text("Esta materia aún no tiene tarjetas. Genere tarjetas de repaso con el agente a partir de los contenidos.")
                        .foregroundStyle(.secondary)
                case .invalid(let reason):
                    Label("No se pudo leer `apuntes/tarjetas.json`. \(reason) Vuelva a generarlas.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                case .loaded:
                    HStack(spacing: 14) {
                        stat(counts.due, "por repasar", .orange)
                        stat(counts.new, "nuevas hoy", .blue)
                        stat(counts.total, "tarjetas", .secondary)
                    }
                    Button { review.startSession(courseID: course.id, now: container.clock.now) } label: {
                        Label(counts.today == 0 ? "Nada que repasar hoy" : "Empezar repaso (\(counts.today))", systemImage: "play.fill")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(color).disabled(counts.today == 0)
                }
                Divider()
                SectionHeader(title: "Cuestionario de práctica")
                if let message = review.quizMessage {
                    Label(message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button { review.startQuiz(courseID: course.id) } label: {
                        Label("Hacer cuestionario", systemImage: "questionmark.square.dashed")
                    }
                    .disabled(!review.hasQuiz(courseID: course.id))
                }
                Divider()
                SectionHeader(title: "Generar con el agente")
                HStack {
                    recipeButton("flashcards", "Generar tarjetas de repaso", "rectangle.on.rectangle")
                    recipeButton("quiz", "Generar cuestionario", "questionmark.square.dashed")
                }
                Text("El agente escribe `apuntes/tarjetas.json` y `apuntes/cuestionario.json`. Al volver a generar las tarjetas se combinan con las existentes y su progreso se conserva.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { review.reload(courses: container.workspace.snapshot.courses, root: container.workspace.root) }
    }

    private func stat(_ value: Int, _ title: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
        .padding(14).frame(minWidth: 110, alignment: .leading).card()
    }

    private func recipeButton(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button {
            if let recipe = RecipeCatalog.recipe(id: id) { container.navigation.show(recipe: recipe, scope: .course(course)) }
        } label: { Label(title, systemImage: symbol) }
    }
}

private struct StudySessionView: View {
    @Environment(AppContainer.self) private var container
    let course: Course

    var body: some View {
        let review = container.review
        let color = CoursePalette.color(for: course)
        VStack(spacing: 18) {
            if let session = review.session {
                header(session, color: color)
                if let card = session.current {
                    cardView(card, color: color)
                    controls(review)
                } else {
                    summary(session, color: color)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 720).frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(course.name)
    }

    private func header(_ session: ReviewSession, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack {
                Button { container.review.endSession() } label: { Label("Salir", systemImage: "xmark") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(session.isFinished ? "Completado" : "\(session.remaining) restantes")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: session.fractionCompleted).tint(color)
        }
    }

    private func cardView(_ card: Flashcard, color: Color) -> some View {
        let revealed = container.review.isAnswerRevealed
        return VStack(alignment: .leading, spacing: 14) {
            Text("Pregunta").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(color)
            Text(card.question).font(.title2.weight(.semibold)).textSelection(.enabled)
            if revealed {
                Divider()
                Text("Respuesta").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
                Text(card.answer).font(.title3).textSelection(.enabled)
                if let source = card.source {
                    Label(source, systemImage: "doc.text").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(22).frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .card(tint: color)
        .animation(.snappy, value: revealed)
    }

    @ViewBuilder
    private func controls(_ review: ReviewModel) -> some View {
        if review.isAnswerRevealed {
            HStack(spacing: 10) {
                ForEach(ReviewGrade.allCases, id: \.self) { grade in
                    Button { review.grade(grade, courseID: course.id, now: container.clock.now) } label: {
                        VStack(spacing: 2) {
                            Text(grade.title).font(.headline)
                            Text(intervalText(review.previewInterval(for: grade, courseID: course.id, now: container.clock.now)))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(grade.shortcut).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .controlSize(.large)
                    .tint(tint(grade))
                    .buttonStyle(.bordered)
                    .keyboardShortcut(KeyEquivalent(Character(grade.shortcut)), modifiers: [])
                }
            }
        } else {
            Button { review.reveal() } label: {
                Label("Mostrar respuesta", systemImage: "eye").frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.space, modifiers: [])
            Text("Espacio para mostrar la respuesta; luego 1 a 4 para calificar.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func summary(_ session: ReviewSession, color: Color) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(color)
            Text("Repaso terminado").font(.title.weight(.bold))
            Text("\(session.reviewedCount) tarjetas repasadas").foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(ReviewGrade.allCases, id: \.self) { grade in
                    VStack {
                        Text("\(session.tally[grade] ?? 0)").font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(tint(grade))
                        Text(grade.title).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12).frame(minWidth: 80).card()
                }
            }
            Button("Volver a la materia") { container.review.endSession() }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(.top, 30)
    }

    private func tint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    private func intervalText(_ days: Int?) -> String {
        guard let days else { return "" }
        return days == 1 ? "1 día" : "\(days) días"
    }
}

private struct QuizView: View {
    @Environment(AppContainer.self) private var container
    let course: Course

    var body: some View {
        let color = CoursePalette.color(for: course)
        VStack(spacing: 18) {
            if let session = container.review.quizSession {
                HStack {
                    Button { container.review.endQuiz() } label: { Label("Salir", systemImage: "xmark") }.buttonStyle(.borderless)
                    Spacer()
                    Text(session.isFinished ? "Completado" : "Pregunta \(session.position + 1) de \(session.quiz.questions.count)")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                ProgressView(value: Double(session.position), total: Double(max(session.quiz.questions.count, 1))).tint(color)
                if let question = session.current {
                    ScrollView { questionView(question, session: session, color: color) }
                } else {
                    result(session.score, color: color)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 720).frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Cuestionario · \(course.name)")
    }

    private func questionView(_ question: QuizQuestion, session: QuizSession, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(question.prompt).font(.title3.weight(.semibold)).textSelection(.enabled)
            if question.isAutoGradable {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    Button { container.review.updateQuiz { $0.submit(choice: index) } } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(letter(index)).font(.headline).frame(width: 22)
                            Text(option).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if session.isAnswered, let symbol = optionSymbol(index, question, session) {
                                Image(systemName: symbol.0).foregroundStyle(symbol.1)
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(optionBackground(index, question, session), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isAnswered)
                }
            } else {
                if !question.options.isEmpty {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        Text("\(letter(index)). \(option)").foregroundStyle(.secondary)
                    }
                }
                if !session.isRevealed {
                    Button { container.review.updateQuiz { $0.reveal() } } label: { Label("Mostrar respuesta", systemImage: "eye") }
                        .buttonStyle(.borderedProminent)
                }
            }
            if session.isRevealed {
                if !question.isAutoGradable {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Respuesta de referencia").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
                        Text(question.answer).textSelection(.enabled)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).card()
                    if !session.isAnswered {
                        HStack {
                            Text("¿Su respuesta fue correcta?").foregroundStyle(.secondary)
                            Button { container.review.updateQuiz { $0.selfEvaluate(correct: true) } } label: {
                                Label("Correcta", systemImage: "checkmark")
                            }.tint(.green)
                            Button { container.review.updateQuiz { $0.selfEvaluate(correct: false) } } label: {
                                Label("Incorrecta", systemImage: "xmark")
                            }.tint(.red)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if session.isAnswered {
                    if question.isAutoGradable {
                        Label(session.results[question.id] == true ? "Correcto" : "Incorrecto. Respuesta: \(question.answer)",
                              systemImage: session.results[question.id] == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.headline).foregroundStyle(session.results[question.id] == true ? .green : .red)
                    }
                    if let explanation = question.explanation { Text(explanation).foregroundStyle(.secondary).textSelection(.enabled) }
                    if let source = question.source {
                        Label(source, systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { container.review.updateQuiz { $0.advance() } } label: {
                        Text(session.position + 1 == session.quiz.questions.count ? "Ver resultado" : "Siguiente").frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading).card(tint: color)
        .animation(.snappy, value: session.isRevealed)
    }

    private func result(_ score: QuizScore, color: Color) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(color)
            Text("Cuestionario terminado").font(.title.weight(.bold))
            Text("\(score.correct) de \(score.total) correctas").font(.title2).monospacedDigit()
            Text("\(Int(score.percent.rounded())) %").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(color)
            HStack {
                Button("Repetir") { container.review.startQuiz(courseID: course.id) }
                Button("Volver a la materia") { container.review.endQuiz() }.buttonStyle(.borderedProminent)
            }
            Text("Práctica con material de la materia; no sustituye la evaluación real.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 30)
    }

    private func letter(_ index: Int) -> String { String(UnicodeScalar(UInt8(65 + min(index, 25)))) }

    private func optionSymbol(_ index: Int, _ question: QuizQuestion, _ session: QuizSession) -> (String, Color)? {
        if index == question.correctIndex { return ("checkmark.circle.fill", .green) }
        if index == session.selectedChoice { return ("xmark.circle.fill", .red) }
        return nil
    }

    private func optionBackground(_ index: Int, _ question: QuizQuestion, _ session: QuizSession) -> Color {
        guard session.isAnswered else { return Color.primary.opacity(0.06) }
        if index == question.correctIndex { return Color.green.opacity(0.18) }
        if index == session.selectedChoice { return Color.red.opacity(0.18) }
        return Color.primary.opacity(0.04)
    }
}

/// "Tarjetas para hoy" card for the "Hoy" dashboard.
struct TodayReviewCard: View {
    @Environment(AppContainer.self) private var container
    let today: ReviewDay

    var body: some View {
        let count = container.review.todayCount(today: today)
        Button { container.navigation.sidebar = .review } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tarjetas para hoy").font(.headline)
                    Text(count == 0 ? "Está al día." : "Repase para fijar lo estudiado.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(count)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(count == 0 ? Color.secondary : Color.accentColor)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
