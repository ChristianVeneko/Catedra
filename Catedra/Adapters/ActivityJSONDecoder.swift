import Foundation

/// Decodes `_sistema/data/activities.json` into domain activities.
enum ActivityJSONDecoder {
    private struct Record: Decodable {
        let course: String
        let type: String
        let name: String
        let due: Int?
        let status: String?
        let grade: String?
        let url: String?
        let folder: String
        let opens: Int?
        let cutoff: Int?
        let gradeRaw: Double?
        let gradeMax: Double?
        let feedback: String?
        let gradedAt: Int?
        let cmid: Int?
    }

    private static func date(_ seconds: Int?) -> Date? {
        guard let seconds, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func decode(_ data: Data) throws -> [Activity] {
        try JSONDecoder().decode([Record].self, from: data).map { r in
            // Some teachers set only the cut-off date; it is then the effective deadline.
            let explicitDue = date(r.due)
            let cutoff = date(r.cutoff)
            return Activity(
                courseName: r.course,
                kind: ActivityKind(rawType: r.type),
                name: r.name,
                due: explicitDue ?? cutoff,
                rawStatus: r.status ?? "",
                grade: r.grade ?? "",
                url: (r.url?.isEmpty == false) ? URL(string: r.url!) : nil,
                folder: r.folder,
                opens: date(r.opens),
                cutoff: cutoff,
                gradeRaw: r.gradeRaw,
                gradeMax: r.gradeMax,
                feedback: r.feedback ?? "",
                gradedAt: date(r.gradedAt),
                cmid: r.cmid,
                dueIsCutoff: explicitDue == nil && cutoff != nil
            )
        }
    }
}
