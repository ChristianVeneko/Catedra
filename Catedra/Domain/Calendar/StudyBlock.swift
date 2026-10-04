import Foundation

/// A block of study time planned by the user. App-owned data (Application Support), never written to the workspace.
struct StudyBlock: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date
    /// Linked activity (`Activity.id`) and course folder, when the block is about one.
    var activityID: String?
    var courseFolder: String?
    var notes: String
    var done: Bool

    static let defaultTitle = "Bloque de estudio"
    static let defaultDuration: TimeInterval = 3600

    init(id: UUID = UUID(), title: String, start: Date, end: Date, activityID: String? = nil, courseFolder: String? = nil,
         notes: String = "", done: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.activityID = activityID
        self.courseFolder = courseFolder
        self.notes = notes
        self.done = done
    }

    /// Lenient decoding: unknown keys are ignored, a missing id/title/end gets a default, a missing start fails.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let start = try c.decode(Date.self, forKey: .start)
        let end = try? c.decodeIfPresent(Date.self, forKey: .end)
        let title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        self.init(
            id: (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultTitle : title,
            start: start,
            end: (end.flatMap { $0 > start ? $0 : nil }) ?? start.addingTimeInterval(Self.defaultDuration),
            activityID: try? c.decodeIfPresent(String.self, forKey: .activityID),
            courseFolder: try? c.decodeIfPresent(String.self, forKey: .courseFolder),
            notes: (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? "",
            done: (try? c.decodeIfPresent(Bool.self, forKey: .done)) ?? false)
    }

    private enum Keys: String, CodingKey { case id, title, start, end, activityID, courseFolder, notes, done }
}
