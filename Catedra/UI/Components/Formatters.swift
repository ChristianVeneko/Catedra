import Foundation

/// Date formatting pinned to America/Caracas and Spanish.
enum Formatters {
    static let timeZone = TimeZone(identifier: "America/Caracas")!
    static let locale = Locale(identifier: "es_VE")

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = locale
        return c
    }

    private static func style() -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
    }

    /// "viernes, 18 de octubre"
    static func dayHeader(_ date: Date) -> String {
        date.formatted(style().weekday(.wide).day().month(.wide)).capitalizedFirst
    }

    /// "vie 18 oct, 11:59 p. m."
    static func due(_ date: Date) -> String {
        date.formatted(style().weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    static func time(_ date: Date) -> String {
        date.formatted(style().hour().minute())
    }

    static func relative(_ date: Date, to now: Date = .now) -> String {
        date.formatted(.relative(presentation: .named).locale(locale))
    }

    static func greeting(now: Date = .now) -> String {
        switch calendar.component(.hour, from: now) {
        case 5..<12: "Buenos días"
        case 12..<19: "Buenas tardes"
        default: "Buenas noches"
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
