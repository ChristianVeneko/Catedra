import SwiftUI

/// Stable per-course accent colors and symbols, derived from the course number.
enum CoursePalette {
    static let colors: [Color] = [
        Color(red: 0.36, green: 0.42, blue: 0.96), // indigo
        Color(red: 0.12, green: 0.66, blue: 0.62), // teal
        Color(red: 0.93, green: 0.45, blue: 0.22), // orange
        Color(red: 0.85, green: 0.30, blue: 0.52), // pink
        Color(red: 0.30, green: 0.69, blue: 0.31), // green
        Color(red: 0.62, green: 0.38, blue: 0.90), // purple
        Color(red: 0.90, green: 0.68, blue: 0.10), // amber
        Color(red: 0.16, green: 0.60, blue: 0.90), // sky
        Color(red: 0.82, green: 0.28, blue: 0.30), // red
    ]

    static func color(for course: Course?) -> Color {
        guard let course else { return .secondary }
        return colors[(course.number - 1 + colors.count * 4) % colors.count]
    }

    static func symbol(for course: Course?) -> String {
        guard let name = course?.name.lowercased() else { return "book.closed" }
        let table: [(String, String)] = [
            ("automata", "point.3.connected.trianglepath.dotted"), ("software", "chevron.left.forwardslash.chevron.right"),
            ("sistemas operativos", "cpu"), ("laboratorio", "testtube.2"), ("circuitos", "bolt.horizontal"),
            ("electronica", "waveform.path.ecg"), ("control", "slider.horizontal.3"), ("comunitario", "person.2"),
        ]
        return table.first { name.contains($0.0) }?.1 ?? "book.closed"
    }
}
