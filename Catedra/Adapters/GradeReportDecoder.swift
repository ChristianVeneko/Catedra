import Foundation

/// Decodes `grades_<courseid>.json`. Every field except `courseid` is optional.
enum GradeReportDecoder {
    private struct ItemRecord: Decodable {
        let itemname: String?
        let itemtype: String?
        let itemmodule: String?
        let cmid: Int?
        let graderaw: Double?
        let gradeformatted: String?
        let grademin: Double?
        let grademax: Double?
        let weightraw: Double?
        let percentageformatted: String?
        let feedback: String?
        let gradedatesubmitted: Int?
        let gradedategraded: Int?

        var item: GradeItem {
            GradeItem(name: itemname ?? "", itemType: itemtype ?? "", itemModule: itemmodule ?? "", cmid: cmid,
                      gradeRaw: graderaw, gradeFormatted: gradeformatted ?? "", gradeMin: grademin, gradeMax: grademax,
                      weight: weightraw, percentage: percentageformatted ?? "", feedback: feedback ?? "",
                      submittedAt: Self.date(gradedatesubmitted), gradedAt: Self.date(gradedategraded))
        }

        private static func date(_ seconds: Int?) -> Date? {
            guard let seconds, seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
    }

    private struct Record: Decodable {
        let courseid: Int
        let items: [ItemRecord]?
        let total: ItemRecord?
    }

    static func decode(_ data: Data) throws -> GradeReport {
        let r = try JSONDecoder().decode(Record.self, from: data)
        return GradeReport(courseId: r.courseid, items: (r.items ?? []).map(\.item), total: r.total?.item)
    }
}
