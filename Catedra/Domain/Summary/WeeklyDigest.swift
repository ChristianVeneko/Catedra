import Foundation

/// Schedule of the weekly summary: once per ISO week, from Monday 07:00 (America/Caracas).
enum WeeklySchedule {
    static let timeZone = TimeZone(identifier: "America/Caracas") ?? .gmt
    static let startHour = 7

    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "es")
        return c
    }

    /// "2026-W41".
    static func weekKey(for date: Date) -> String {
        let c = calendar
        let parts = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    /// Monday 00:00 of the week containing `date`.
    static func weekStart(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func weekInterval(of date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 86400)
    }

    /// Monday 07:00 of the week containing `date`.
    static func trigger(of date: Date) -> Date {
        calendar.date(byAdding: .hour, value: startHour, to: weekStart(of: date)) ?? weekStart(of: date)
    }

    static func isDue(now: Date, lastWeekKey: String?, enabled: Bool) -> Bool {
        enabled && now >= trigger(of: now) && lastWeekKey != weekKey(for: now)
    }
}

struct GradeEntry: Equatable, Sendable {
    let name: String
    let courseName: String
    let grade: String
    let gradedAt: Date?
}

struct WeeklyDigest: Equatable, Sendable {
    struct Delivery: Equatable, Sendable { let name: String; let courseName: String; let due: Date }
    struct Block: Equatable, Sendable { let title: String; let start: Date; let end: Date; let done: Bool }

    let weekKey: String
    let weekStart: Date
    var deliveries: [Delivery]
    var grades: [GradeEntry]
    var blocks: [Block]
    var cardsDue: Int

    var isEmpty: Bool { deliveries.isEmpty && grades.isEmpty && blocks.isEmpty && cardsDue == 0 }

    /// Plain Markdown digest; also the fallback shown when no agent is available.
    var markdown: String {
        var lines = ["# Semana \(weekKey)", ""]
        lines += ["## Entregas de la semana", ""]
        lines += deliveries.isEmpty ? ["- Sin entregas pendientes con fecha esta semana."]
            : deliveries.map { "- \(Self.dayTime($0.due)) · \($0.courseName) · \($0.name)" }
        lines += ["", "## Notas nuevas (desde la semana pasada)", ""]
        lines += grades.isEmpty ? ["- Sin notas nuevas."] : grades.map { "- \($0.courseName) · \($0.name): \($0.grade)" }
        lines += ["", "## Bloques de estudio", ""]
        lines += blocks.isEmpty ? ["- Sin bloques planificados."]
            : blocks.map { "- \(Self.dayTime($0.start))–\(Self.time($0.end)) · \($0.title)\($0.done ? " (hecho)" : "")" }
        lines += ["", "## Tarjetas de repaso", "", cardsDue == 0 ? "- Sin tarjetas para repasar hoy."
                  : "- \(cardsDue) \(cardsDue == 1 ? "tarjeta" : "tarjetas") para repasar."]
        return lines.joined(separator: "\n") + "\n"
    }

    static func dayTime(_ date: Date) -> String { format(date, "EEE d MMM HH:mm") }
    static func time(_ date: Date) -> String { format(date, "HH:mm") }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.timeZone = WeeklySchedule.timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

enum WeeklyDigestBuilder {
    static func build(now: Date, activities: [Activity], isOpen: (Activity) -> Bool, grades: [GradeEntry],
                      studyBlocks: [StudyBlock], cardsDue: Int) -> WeeklyDigest {
        let week = WeeklySchedule.weekInterval(of: now)
        let gradeSince = week.start.addingTimeInterval(-7 * 86400)

        let deliveries = activities.compactMap { a -> WeeklyDigest.Delivery? in
            guard let due = a.due, due >= week.start, due < week.end, isOpen(a) else { return nil }
            return WeeklyDigest.Delivery(name: a.name, courseName: a.courseName, due: due)
        }.sorted { ($0.due, $0.name) < ($1.due, $1.name) }

        var seen = Set<String>()
        let newGrades = grades.filter { entry in
            guard let at = entry.gradedAt, at >= gradeSince, at <= now else { return false }
            return seen.insert(entry.courseName + "|" + entry.name).inserted
        }.sorted { ($0.gradedAt ?? .distantPast, $0.name) < ($1.gradedAt ?? .distantPast, $1.name) }

        let blocks = studyBlocks.filter { $0.start >= week.start && $0.start < week.end }
            .sorted { $0.start < $1.start }
            .map { WeeklyDigest.Block(title: $0.title, start: $0.start, end: $0.end, done: $0.done) }

        return WeeklyDigest(weekKey: WeeklySchedule.weekKey(for: now), weekStart: week.start, deliveries: deliveries,
                            grades: newGrades, blocks: blocks, cardsDue: cardsDue)
    }
}

enum WeeklySummaryPrompt {
    /// Spanish prompt for the agent; the data is inline so the agent needs no access to the workspace.
    static func make(digest: WeeklyDigest, outputFile: String) -> String {
        """
        Eres el asistente de estudio del estudiante. Con los datos locales de abajo, redacta un resumen breve y claro \
        de su semana académica (\(digest.weekKey)) en español, con tono neutro: qué entrega primero y qué es más \
        urgente, qué notas nuevas aparecieron, cómo se reparten los bloques de estudio y cuántas tarjetas hay por repasar. \
        Cierra con dos o tres sugerencias concretas de priorización. No inventes datos que no estén abajo.

        Escribe el resultado en formato Markdown únicamente en el archivo `\(outputFile)` de la carpeta actual; no \
        crees ni modifiques otros archivos. Responde también con el mismo texto.

        Datos de la semana:

        \(digest.markdown)
        """
    }
}

/// What the app remembers about weekly summaries.
struct WeeklySummaryState: Codable, Equatable, Sendable {
    struct Record: Codable, Equatable, Sendable {
        var weekKey: String
        var generatedAt: Date
        /// False when the summary is the plain local digest (no agent available or the run failed).
        var usedAgent: Bool
    }

    /// Week whose summary was already attempted (once per ISO week, even if it fell back to the local digest).
    var lastWeekKey: String?
    var latest: Record?
    var dismissedWeekKey: String?
}
