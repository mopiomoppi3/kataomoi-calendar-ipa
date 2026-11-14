import Foundation
import SwiftUI
import ActivityKit

// Shared between the app (KataomoiCalendar) and the widget extension
// (KataomoiWidget). Both targets compile this file.

enum SharedStore {
    static let appGroup = "group.com.moppi.kataomoi"
    static let fileName = "widget-data.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
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
    var updatedAt: String = ""
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
    static let list = [100, 200, 300, 365, 500, 730, 1000, 1095, 1500, 2000, 3000]

    static func label(_ m: Int) -> String {
        m % 365 == 0 && m > 0 ? "\(m / 365)年" : "\(m)日"
    }

    static func nextText(_ days: Int) -> String {
        var next = list.first(where: { $0 > days })
        if next == nil { next = (days / 365 + 1) * 365 }
        guard let n = next else { return "" }
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
