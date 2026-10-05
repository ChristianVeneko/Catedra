import Foundation

enum RequirementStatus: Equatable, Sendable {
    case cumple, parcial, falta
    /// Any value the reviewer wrote that is not one of the three known ones.
    case unknown
}

enum RequirementSource: Equatable, Sendable {
    case enunciado, rubrica, normasUFT
    case unknown
}

struct ReviewRequirement: Identifiable, Equatable, Sendable {
    let id: String
    let requirement: String
    let status: RequirementStatus
    let evidence: String
    let suggestion: String?
    let source: RequirementSource
}

struct ReviewCounts: Equatable, Sendable {
    var cumple = 0
    var parcial = 0
    var falta = 0
    var unknown = 0

    var total: Int { cumple + parcial + falta + unknown }
}

/// Structured result a `review-draft` agent run leaves in the activity folder.
struct DraftReview: Equatable, Sendable {
    let generatedAt: Date?
    let summary: String
    let requirements: [ReviewRequirement]

    var counts: ReviewCounts {
        var counts = ReviewCounts()
        for requirement in requirements {
            switch requirement.status {
            case .cumple: counts.cumple += 1
            case .parcial: counts.parcial += 1
            case .falta: counts.falta += 1
            case .unknown: counts.unknown += 1
            }
        }
        return counts
    }
}

enum DraftReviewError: Error, Equatable, Sendable {
    case notJSON
    case notAnObject
}

extension DraftReviewError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notJSON: "El archivo de revisión no es un JSON válido."
        case .notAnObject: "El archivo de revisión no tiene el formato esperado."
        }
    }
}

/// Tolerant reader: only a non-JSON or non-object document is an error; missing or odd fields degrade gracefully.
enum DraftReviewParser {
    static func parse(_ data: Data) throws -> DraftReview {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { throw DraftReviewError.notJSON }
        guard let root = object as? [String: Any] else { throw DraftReviewError.notAnObject }

        let entries = root["requirements"] as? [Any] ?? []
        var requirements: [ReviewRequirement] = []
        for (index, entry) in entries.enumerated() {
            guard let dict = entry as? [String: Any], let text = string(dict["requirement"]) else { continue }
            requirements.append(ReviewRequirement(
                id: string(dict["id"]) ?? "req-\(index + 1)",
                requirement: text,
                status: status(string(dict["status"])),
                evidence: string(dict["evidence"]) ?? "",
                suggestion: string(dict["suggestion"]),
                source: source(string(dict["source"]))))
        }
        return DraftReview(generatedAt: string(root["generatedAt"]).flatMap(date),
                           summary: string(root["summary"]) ?? "", requirements: requirements)
    }

    /// A non-empty trimmed string, or nil.
    private static func string(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func status(_ raw: String?) -> RequirementStatus {
        switch raw?.lowercased() {
        case "cumple": .cumple
        case "parcial": .parcial
        case "falta": .falta
        default: .unknown
        }
    }

    private static func source(_ raw: String?) -> RequirementSource {
        switch raw?.lowercased() {
        case "enunciado": .enunciado
        case "rubrica", "rúbrica": .rubrica
        case "normas-uft": .normasUFT
        default: .unknown
        }
    }

    private static func date(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return plain.date(from: text) ?? fractional.date(from: text) ?? dateOnly.date(from: text)
    }
}

enum DraftReviewLoadState: Equatable, Sendable {
    case missing
    case loaded(DraftReview)
    case invalid(String)
}

enum DraftReviewFile {
    /// Inside `apuntes/`: the folder the agent preamble already allows writing to, never touched by the sync and never
    /// uploaded (unlike `entrega/`). Hidden so it does not show up in the file lists.
    static let relativePath = "apuntes/.revision.json"

    static func load(in activityFolder: URL) -> DraftReviewLoadState {
        let url = activityFolder.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return .missing }
        do { return .loaded(try DraftReviewParser.parse(data)) } catch {
            return .invalid(error.localizedDescription)
        }
    }
}
