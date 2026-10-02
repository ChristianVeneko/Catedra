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
    }

    static func decode(_ data: Data) throws -> [Activity] {
        try JSONDecoder().decode([Record].self, from: data).map { r in
            Activity(
                courseName: r.course,
                kind: ActivityKind(rawType: r.type),
                name: r.name,
                due: (r.due ?? 0) > 0 ? Date(timeIntervalSince1970: TimeInterval(r.due!)) : nil,
                rawStatus: r.status ?? "",
                grade: r.grade ?? "",
                url: (r.url?.isEmpty == false) ? URL(string: r.url!) : nil,
                folder: r.folder
            )
        }
    }
}
