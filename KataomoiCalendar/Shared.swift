import Foundation
import SwiftUI
import ActivityKit

// Shared between the app (KataomoiCalendar) and the widget extension
// (KataomoiWidget). Both targets compile this file.

enum SharedStore {
    static let fallbackGroupID = "group.com.moppi.kataomoi"
    static let fileName = "widget-data.json"

    /// App groups actually granted to THIS bundle, read from its embedded
    /// provisioning profile. Sideload signers may grant the group under the
    /// requested ID, a rewritten ID, or not at all - so never trust the
    /// hardcoded ID alone.
    static func provisionedGroupIDs() -> [String] {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex) else { return [] }
        let xml = String(text[start.lowerBound..<end.upperBound])
        guard let xmlData = xml.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: xmlData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else { return [] }
        return groups
    }

    private static var candidateIDs: [String] {
        var ids = provisionedGroupIDs()
        if !ids.contains(fallbackGroupID) { ids.append(fallbackGroupID) }
        return ids
    }

    static var groupID: String { candidateIDs.first ?? fallbackGroupID }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }

    static var allFileURLs: [URL] {
        candidateIDs.compactMap {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)?
                .appendingPathComponent(fileName)
        }
    }

    enum LoadStatus {
        case ok           // snapshot file read and decoded
        case noGroup      // provisioning profile grants no app group
        case noContainer  // group named but its container is unavailable
        case noFile       // container reachable but no snapshot written yet
        case decodeError  // snapshot file exists but cannot be decoded

        var message: String {
            switch self {
            case .ok: return "アプリで人を登録してね"
            case .noGroup: return "連携エラー: グループ未付与"
            case .noContainer: return "連携エラー: 共有フォルダ不可"
            case .noFile: return "アプリを開いてね"
            case .decodeError: return "連携エラー: データ読込"
            }
        }
    }

    static func loadSnapshot() -> (snapshot: WidgetSnapshot, status: LoadStatus) {
        var sawContainer = false
        for url in allFileURLs {
            sawContainer = true
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
            else { return (WidgetSnapshot(), .decodeError) }
            return (snapshot, .ok)
        }
        if !sawContainer {
            return (WidgetSnapshot(), provisionedGroupIDs().isEmpty ? .noGroup : .noContainer)
        }
        return (WidgetSnapshot(), .noFile)
    }
}

struct WidgetSnapshot: Codable {
    struct Person: Codable {
        var name: String
        var since: String
        var color: String
        var rel: String
        var birthday: String?
    }
    struct Todo: Codable {
        var text: String
        var done: Bool
    }
    var persons: [Person] = []
    var todos: [Todo] = []
    var phrases: [String] = []
    var updatedAt: String = ""
    var mileStep: Int = 100

    init(persons: [Person] = [], todos: [Todo] = [], phrases: [String] = [], updatedAt: String = "", mileStep: Int = 100) {
        self.persons = persons
        self.todos = todos
        self.phrases = phrases
        self.updatedAt = updatedAt
        self.mileStep = mileStep
    }

    private enum CodingKeys: String, CodingKey { case persons, todos, phrases, updatedAt, mileStep }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        persons = try c.decodeIfPresent([Person].self, forKey: .persons) ?? []
        todos = try c.decodeIfPresent([Todo].self, forKey: .todos) ?? []
        phrases = try c.decodeIfPresent([String].self, forKey: .phrases) ?? []
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        mileStep = try c.decodeIfPresent(Int.self, forKey: .mileStep) ?? 100
    }
}

// MARK: - Live Activity attributes

struct DaysActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var days: Int
        public var milestoneText: String

        public init(days: Int, milestoneText: String) {
            self.days = days
            self.milestoneText = milestoneText
        }
    }

    public var personName: String
    public var colorHex: String

    public init(personName: String, colorHex: String) {
        self.personName = personName
        self.colorHex = colorHex
    }
}

// MARK: - Helpers (mirror the app's DateKit / CalendarStore logic)

func colorFromHex(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return .pink }
    return Color(red: Double((v >> 16) & 0xFF) / 255,
                 green: Double((v >> 8) & 0xFF) / 255,
                 blue: Double(v & 0xFF) / 255)
}

enum WidgetDateKit {
    static func date(from string: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)
    }

    static func daysSince(_ string: String, on reference: Date = Date()) -> Int {
        guard let d = date(from: string) else { return 0 }
        let cal = Calendar.current
        let a = cal.startOfDay(for: d)
        let b = cal.startOfDay(for: reference)
        return max(0, cal.dateComponents([.day], from: a, to: b).day ?? 0)
    }
}

enum WidgetMilestones {
    static func label(_ m: Int) -> String {
        m % 365 == 0 && m > 0 ? "\(m / 365)年" : "\(m)日"
    }

    /// Next milestone: the configured day step, with year marks (multiples
    /// of 365) always counting as milestones too.
    static func nextText(_ days: Int, step: Int) -> String {
        let s = step > 0 ? step : 100
        let byStep = (days / s + 1) * s
        let byYear = (days / 365 + 1) * 365
        let n = min(byStep, byYear)
        return "\(label(n))まであと\(n - days)日"
    }

    static func birthdayText(_ birthday: String?, on reference: Date = Date()) -> String? {
        guard let birthday, let b = WidgetDateKit.date(from: birthday) else { return nil }
        let cal = Calendar.current
        let bc = cal.dateComponents([.month, .day], from: b)
        let today = cal.startOfDay(for: reference)
        let year = cal.component(.year, from: reference)
        func candidate(_ y: Int) -> Date? {
            var c = DateComponents()
            c.year = y; c.month = bc.month; c.day = bc.day
            guard let d = cal.date(from: c) else { return nil }
            return cal.startOfDay(for: d)
        }
        let next = (candidate(year).flatMap { $0 >= today ? $0 : nil }) ?? candidate(year + 1)
        guard let next else { return nil }
        let days = cal.dateComponents([.day], from: today, to: next).day ?? 0
        if days == 0 { return "今日が誕生日" }
        return "誕生日まであと\(days)日"
    }
}
