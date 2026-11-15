import UIKit
import SwiftUI
import AuthenticationServices
import CryptoKit
import ActivityKit
import WidgetKit
import PhotosUI
import UniformTypeIdentifiers
import CoreLocation

// Native SwiftUI rebuild of Kataomoi Calendar.
// The UIKit scene still starts here, but the whole UI is SwiftUI so the
// tab bar, buttons, sheets and menus use the real iOS design language,
// including Liquid Glass on iOS 26+.

final class MainTabBarController: UIViewController {
    private let store = CalendarStore()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: "#fff5f8")
        let host = UIHostingController(rootView: ContentView().environmentObject(store))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
}

// MARK: - Small helpers

func hexRGB(_ hex: String) -> (CGFloat, CGFloat, CGFloat)? {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    if s.count == 3 { s = s.map { String(repeating: $0, count: 2) }.joined() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    return (CGFloat((v >> 16) & 0xff) / 255,
            CGFloat((v >> 8) & 0xff) / 255,
            CGFloat(v & 0xff) / 255)
}

extension Color {
    init(hex: String) {
        if let c = hexRGB(hex) {
            self.init(red: Double(c.0), green: Double(c.1), blue: Double(c.2))
        } else {
            self = .pink
        }
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

extension UIColor {
    convenience init(hex: String) {
        if let c = hexRGB(hex) {
            self.init(red: c.0, green: c.1, blue: c.2, alpha: 1)
        } else {
            self.init(red: 1, green: 0.42, blue: 0.55, alpha: 1)
        }
    }
}

enum DateKit {
    static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
    static func todayString() -> String { string(from: Date()) }

    static func daysSince(_ string: String) -> Int {
        guard let d = date(from: string) else { return 0 }
        let cal = Calendar.current
        let a = cal.startOfDay(for: d)
        let b = cal.startOfDay(for: Date())
        return max(0, cal.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    static func japanese(_ string: String) -> String {
        guard let d = date(from: string) else { return string }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: d)
    }

    static func japaneseWithWeekday(_ string: String) -> String {
        guard let d = date(from: string) else { return string }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日（E）"
        return f.string(from: d)
    }

    static func key(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

enum ImageData {
    static func uiImage(from dataURL: String?) -> UIImage? {
        guard let dataURL else { return nil }
        let raw: String
        if let comma = dataURL.firstIndex(of: ",") {
            raw = String(dataURL[dataURL.index(after: comma)...])
        } else {
            raw = dataURL
        }
        guard let data = Data(base64Encoded: raw) else { return nil }
        return UIImage(data: data)
    }

    static func dataURL(from image: UIImage, maxPixel: CGFloat, square: Bool) -> String? {
        let rendered: UIImage
        if square {
            let side = min(image.size.width, image.size.height)
            let scale = maxPixel / max(side, 1)
            let size = CGSize(width: maxPixel, height: maxPixel)
            let renderer = UIGraphicsImageRenderer(size: size)
            rendered = renderer.image { _ in
                let origin = CGPoint(x: (side - image.size.width) / 2 * scale,
                                     y: (side - image.size.height) / 2 * scale)
                image.draw(in: CGRect(origin: origin,
                                      size: CGSize(width: image.size.width * scale,
                                                   height: image.size.height * scale)))
            }
        } else {
            let longest = max(image.size.width, image.size.height)
            let scale = min(1, maxPixel / max(longest, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            rendered = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.85) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}

// MARK: - Data model (compatible with the web version's backup JSON)

struct CustomField: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var label: String
    var value: String

    init(id: String, label: String, value: String) {
        self.id = id; self.label = label; self.value = value
    }

    private enum CodingKeys: String, CodingKey { case id, label, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
    }
}

struct Person: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var since: String
    var met: String?
    var color: String
    var rel: String?
    var icon: String?
    var song: String?
    var mutual: String?
    var birthday: String?
    var mileDone: Int?
    var fields: [CustomField] = []

    init(id: String, name: String, since: String, met: String? = nil, color: String,
         rel: String? = "片思い", icon: String? = nil, song: String? = nil,
         mutual: String? = nil, birthday: String? = nil, mileDone: Int? = nil, fields: [CustomField] = []) {
        self.id = id; self.name = name; self.since = since; self.met = met
        self.color = color; self.rel = rel; self.icon = icon; self.song = song
        self.mutual = mutual; self.birthday = birthday; self.mileDone = mileDone; self.fields = fields
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, since, met, color, rel, icon, song, mutual, birthday, mileDone, fields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? String(Int(Date().timeIntervalSince1970 * 1000))
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        since = try c.decodeIfPresent(String.self, forKey: .since) ?? DateKit.todayString()
        met = try c.decodeIfPresent(String.self, forKey: .met)
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#e8698a"
        rel = try c.decodeIfPresent(String.self, forKey: .rel)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        song = try c.decodeIfPresent(String.self, forKey: .song)
        mutual = try c.decodeIfPresent(String.self, forKey: .mutual)
        birthday = try c.decodeIfPresent(String.self, forKey: .birthday)
        mileDone = try c.decodeIfPresent(Int.self, forKey: .mileDone)
        fields = try c.decodeIfPresent([CustomField].self, forKey: .fields) ?? []
    }
}

struct Entry: Identifiable, Codable, Hashable {
    var id: String
    var personId: String
    var date: String
    var mood: String
    var like: Int
    var text: String
    var photo: String?

    init(id: String, personId: String, date: String, mood: String, like: Int, text: String, photo: String? = nil) {
        self.id = id; self.personId = personId; self.date = date
        self.mood = mood; self.like = like; self.text = text; self.photo = photo
    }

    private enum CodingKeys: String, CodingKey {
        case id, personId, date, mood, like, text, photo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? String(Int(Date().timeIntervalSince1970 * 1000))
        personId = try c.decodeIfPresent(String.self, forKey: .personId) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? DateKit.todayString()
        mood = try c.decodeIfPresent(String.self, forKey: .mood) ?? ""
        like = try c.decodeIfPresent(Int.self, forKey: .like) ?? 70
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        photo = try c.decodeIfPresent(String.self, forKey: .photo)
    }
}

struct AppSettings: Codable, Hashable {
    var icons: Bool = true
    var celebrate: Bool = true
    var style: String = "heart"
    var dash: Bool = true
    var widgets: [String] = ["weather", "music"]
    var spId: String = ""
    var aiKey: String = ""
    var tabNames: [String: String] = [:]
    var tabsShow: [String: Bool] = [:]
    var mileEvent: Bool = true
    var mileStep: Int = 100

    private enum CodingKeys: String, CodingKey {
        case icons, celebrate, style, dash, widgets, spId, tabNames, tabsShow, mileEvent, mileStep, aiKey
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        icons = try c.decodeIfPresent(Bool.self, forKey: .icons) ?? true
        celebrate = try c.decodeIfPresent(Bool.self, forKey: .celebrate) ?? true
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "heart"
        dash = try c.decodeIfPresent(Bool.self, forKey: .dash) ?? true
        widgets = try c.decodeIfPresent([String].self, forKey: .widgets) ?? ["weather", "music"]
        spId = try c.decodeIfPresent(String.self, forKey: .spId) ?? ""
        aiKey = try c.decodeIfPresent(String.self, forKey: .aiKey) ?? ""
        tabNames = try c.decodeIfPresent([String: String].self, forKey: .tabNames) ?? [:]
        tabsShow = try c.decodeIfPresent([String: Bool].self, forKey: .tabsShow) ?? [:]
        mileEvent = try c.decodeIfPresent(Bool.self, forKey: .mileEvent) ?? true
        mileStep = try c.decodeIfPresent(Int.self, forKey: .mileStep) ?? 100
    }
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    var done: Bool = false

    private enum CodingKeys: String, CodingKey { case id, text, done }

    init(id: String, text: String, done: Bool = false) {
        self.id = id; self.text = text; self.done = done
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}

struct PhraseItem: Codable, Identifiable, Equatable {
    var id: String
    var text: String

    private enum CodingKeys: String, CodingKey { case id, text }

    init(id: String, text: String) {
        self.id = id; self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

struct CalendarData: Codable {
    var persons: [Person] = []
    var entries: [Entry] = []
    var settings: AppSettings = AppSettings()
    var todos: [TodoItem] = []
    var phrases: [PhraseItem] = []

    private enum CodingKeys: String, CodingKey { case persons, entries, settings, todos, phrases }

    init(persons: [Person] = [], entries: [Entry] = [], settings: AppSettings = AppSettings(), todos: [TodoItem] = [], phrases: [PhraseItem] = []) {
        self.persons = persons; self.entries = entries; self.settings = settings; self.todos = todos; self.phrases = phrases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        persons = try c.decodeIfPresent([Person].self, forKey: .persons) ?? []
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        todos = try c.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
        phrases = try c.decodeIfPresent([PhraseItem].self, forKey: .phrases) ?? []
    }
}

struct BackupFile: Codable {
    var app: String?
    var version: Int?
    var exportedAt: String?
    var theme: String?
    var persons: [Person]
    var entries: [Entry]
    var settings: AppSettings?
    var todos: [TodoItem]?
    var phrases: [PhraseItem]?
}

// MARK: - Themes

enum AppThemeKey: String, CaseIterable, Identifiable {
    case pink, lavender, mint, peach, sky, lemon, coral, grape, ocean, cocoa, berry, white, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pink: return "ピンク"
        case .lavender: return "ラベンダー"
        case .mint: return "ミント"
        case .peach: return "ピーチ"
        case .sky: return "スカイ"
        case .lemon: return "レモン"
        case .coral: return "コーラル"
        case .grape: return "グレープ"
        case .ocean: return "オーシャン"
        case .cocoa: return "ココア"
        case .berry: return "ベリー"
        case .white: return "ホワイト"
        case .custom: return "カスタム"
        }
    }
}

struct AppTheme {
    let key: AppThemeKey
    let rose: Color
    let deep: Color
    let blush: Color
    let petal: Color
    let cream: Color
    let card: Color
    let text: Color
    let sub: Color
    let muted: Color

    static func of(_ key: AppThemeKey) -> AppTheme {
        switch key {
        case .pink:
            return AppTheme(key: key, rose: Color(hex: "#e8698a"), deep: Color(hex: "#c0496d"),
                            blush: Color(hex: "#f2a7c3"), petal: Color(hex: "#fde8f0"),
                            cream: Color(hex: "#fff5f8"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#2d1220"), sub: Color(hex: "#7a4a5e"), muted: Color(hex: "#b088a0"))
        case .lavender:
            return AppTheme(key: key, rose: Color(hex: "#9b6fd4"), deep: Color(hex: "#6e3fa8"),
                            blush: Color(hex: "#c9aaee"), petal: Color(hex: "#ede4fb"),
                            cream: Color(hex: "#f8f4ff"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#1e1030"), sub: Color(hex: "#5a3a8a"), muted: Color(hex: "#9a80c0"))
        case .mint:
            return AppTheme(key: key, rose: Color(hex: "#3daa88"), deep: Color(hex: "#1f7a60"),
                            blush: Color(hex: "#8ed8c0"), petal: Color(hex: "#ddf4ec"),
                            cream: Color(hex: "#f2fcf9"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#082820"), sub: Color(hex: "#1a5a48"), muted: Color(hex: "#70a898"))
        case .peach:
            return AppTheme(key: key, rose: Color(hex: "#e88a50"), deep: Color(hex: "#c05e28"),
                            blush: Color(hex: "#f5c89a"), petal: Color(hex: "#fdeede"),
                            cream: Color(hex: "#fff8f2"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#2d1408"), sub: Color(hex: "#8a4010"), muted: Color(hex: "#c09060"))
        case .sky:
            return AppTheme(key: key, rose: Color(hex: "#4a9fd4"), deep: Color(hex: "#1a72a8"),
                            blush: Color(hex: "#99cff5"), petal: Color(hex: "#ddeeff"),
                            cream: Color(hex: "#f2f8ff"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#08182e"), sub: Color(hex: "#1a4a78"), muted: Color(hex: "#6090c0"))
        case .lemon:
            return AppTheme(key: key, rose: Color(hex: "#d9940d"), deep: Color(hex: "#9c6d00"),
                            blush: Color(hex: "#f7d774"), petal: Color(hex: "#fdf3cd"),
                            cream: Color(hex: "#fffdf0"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#2e2000"), sub: Color(hex: "#7a5a00"), muted: Color(hex: "#bfa050"))
        case .coral:
            return AppTheme(key: key, rose: Color(hex: "#f0654a"), deep: Color(hex: "#c23e22"),
                            blush: Color(hex: "#ffb09d"), petal: Color(hex: "#ffe9e2"),
                            cream: Color(hex: "#fff7f3"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#33100a"), sub: Color(hex: "#8a3020"), muted: Color(hex: "#cf8672"))
        case .grape:
            return AppTheme(key: key, rose: Color(hex: "#b04fd8"), deep: Color(hex: "#7e2ba8"),
                            blush: Color(hex: "#dda5f2"), petal: Color(hex: "#f6e3fc"),
                            cream: Color(hex: "#fdf5ff"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#26083a"), sub: Color(hex: "#63228a"), muted: Color(hex: "#a878c8"))
        case .ocean:
            return AppTheme(key: key, rose: Color(hex: "#17809e"), deep: Color(hex: "#0b5a72"),
                            blush: Color(hex: "#7fcadb"), petal: Color(hex: "#dcf3f8"),
                            cream: Color(hex: "#f2fafc"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#06222e"), sub: Color(hex: "#155e75"), muted: Color(hex: "#6399ab"))
        case .cocoa:
            return AppTheme(key: key, rose: Color(hex: "#a9714b"), deep: Color(hex: "#7c4a26"),
                            blush: Color(hex: "#d9b08c"), petal: Color(hex: "#f3e6d8"),
                            cream: Color(hex: "#fbf6ef"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#2a1808"), sub: Color(hex: "#6e4525"), muted: Color(hex: "#b08d68"))
        case .berry:
            return AppTheme(key: key, rose: Color(hex: "#c2255c"), deep: Color(hex: "#8f1239"),
                            blush: Color(hex: "#f78fb0"), petal: Color(hex: "#fde0ea"),
                            cream: Color(hex: "#fff5f8"), card: Color.white.opacity(0.93),
                            text: Color(hex: "#33060f"), sub: Color(hex: "#8f1239"), muted: Color(hex: "#c2707f"))
        case .white:
            return AppTheme(key: key, rose: Color(hex: "#1c1c1e"), deep: Color(hex: "#000000"),
                            blush: Color(hex: "#d1d1d6"), petal: Color(hex: "#f2f2f7"),
                            cream: Color(hex: "#f2f2f7"), card: Color.white.opacity(0.96),
                            text: Color(hex: "#1c1c1e"), sub: Color(hex: "#5c5c60"), muted: Color(hex: "#8e8e93"))
        case .custom:
            return AppTheme.custom("#e8698a")
        }
    }

    static func custom(_ hex: String) -> AppTheme {
        let base = UIColor(hex: hex)
        func mix(_ other: UIColor, _ amount: CGFloat) -> Color {
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            base.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return Color(red: Double(r1 + (r2 - r1) * amount),
                         green: Double(g1 + (g2 - g1) * amount),
                         blue: Double(b1 + (b2 - b1) * amount))
        }
        return AppTheme(key: .custom,
                        rose: Color(hex: hex),
                        deep: mix(.black, 0.25),
                        blush: mix(.white, 0.45),
                        petal: mix(.white, 0.86),
                        cream: mix(.white, 0.95),
                        card: Color.white.opacity(0.93),
                        text: mix(.black, 0.8),
                        sub: mix(.black, 0.45),
                        muted: mix(UIColor(white: 0.55, alpha: 1), 0.45))
    }
}

// MARK: - Store

struct Celebration: Identifiable {
    let id = UUID()
    var person: Person
    var isPreview: Bool = false
}

@MainActor
final class CalendarStore: ObservableObject {
    @Published var data: CalendarData
    @Published var themeKey: AppThemeKey
    @Published var customColorHex: String
    @Published var celebration: Celebration?
    @Published var milestoneText: String?
    @Published var birthdayText: String?
    @Published var calendarPersonID: String?
    @Published var pendingDay: String?

    static let personColors = ["#e8698a", "#9b6fd4", "#3daa88", "#e88a50", "#4a9fd4",
                               "#c0496d", "#7b5ea7", "#2d8a68", "#b06030", "#1860a0",
                               "#d6336c", "#e3a008", "#17809e", "#5b8c5a", "#8a5a2b", "#5a67d8"]
    static let relations = ["片思い", "気になる", "友達", "両思い", "恋人", "推し"]

    var theme: AppTheme { theme(for: themeKey) }

    func theme(for key: AppThemeKey) -> AppTheme {
        key == .custom ? AppTheme.custom(customColorHex) : AppTheme.of(key)
    }

    func setCustomColor(_ hex: String) {
        customColorHex = hex
        save()
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KataomoiCalendar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    init() {
        var loaded = CalendarData()
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KataomoiCalendar/data.json")
        if let raw = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(CalendarData.self, from: raw) {
            loaded = decoded
        }
        data = loaded
        let savedTheme = UserDefaults.standard.string(forKey: "kataomoi-theme") ?? "pink"
        themeKey = AppThemeKey(rawValue: savedTheme) ?? .pink
        customColorHex = UserDefaults.standard.string(forKey: "kataomoi-theme-custom") ?? "#e8698a"
        calendarPersonID = loaded.persons.first?.id
        var introducedPhrase = false
        if !UserDefaults.standard.bool(forKey: "kataomoi-phrase-introduced") {
            if !data.settings.widgets.contains("phrase") {
                data.settings.widgets.append("phrase")
                introducedPhrase = true
            }
            UserDefaults.standard.set(true, forKey: "kataomoi-phrase-introduced")
        }
        if introducedPhrase { save() } else { writeWidgetSnapshot() }
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: fileURL, options: [.atomic])
        }
        UserDefaults.standard.set(themeKey.rawValue, forKey: "kataomoi-theme")
        UserDefaults.standard.set(customColorHex, forKey: "kataomoi-theme-custom")
        writeWidgetSnapshot()
    }

    private func writeWidgetSnapshot() {
        let snapshot = WidgetSnapshot(
            persons: data.persons.map { .init(name: $0.name, since: $0.since, color: $0.color, rel: $0.rel ?? "片思い", birthday: $0.birthday) },
            todos: data.todos.map { .init(text: $0.text, done: $0.done) },
            phrases: data.phrases.map { $0.text },
            updatedAt: DateKit.todayString(),
            mileStep: data.settings.mileStep
        )
        var wrote = false
        if let encoded = try? JSONEncoder().encode(snapshot) {
            for url in SharedStore.allFileURLs {
                if (try? encoded.write(to: url, options: [.atomic])) != nil { wrote = true }
            }
        }
        UserDefaults.standard.set(wrote ? "ok" : "ng", forKey: "kataomoi-widget-write")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "kataomoi-widget-write-at")
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setTheme(_ key: AppThemeKey) {
        themeKey = key
        save()
    }

    func person(_ id: String?) -> Person? {
        guard let id else { return data.persons.first }
        return data.persons.first(where: { $0.id == id }) ?? data.persons.first
    }

    func entries(for personID: String) -> [Entry] {
        data.entries.filter { $0.personId == personID }.sorted { $0.date < $1.date }
    }

    func entries(for personID: String, on date: String) -> [Entry] {
        data.entries.filter { $0.personId == personID && $0.date == date }
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&data.settings)
        save()
    }

    func updatePerson(_ id: String, _ mutate: (inout Person) -> Void) {
        guard let i = data.persons.firstIndex(where: { $0.id == id }) else { return }
        mutate(&data.persons[i])
        save()
    }

    func addPerson(name: String, since: String, met: String?, color: String, rel: String, birthday: String?, icon: String?, song: String? = nil, fields: [CustomField] = []) {
        guard data.persons.isEmpty else { return }
        let p = Person(id: String(Int(Date().timeIntervalSince1970 * 1000)),
                       name: name, since: since, met: met, color: color, rel: rel, icon: icon, song: song, birthday: birthday, fields: fields)
        data.persons.append(p)
        calendarPersonID = p.id
        save()
    }

    func addTodo(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.todos.append(TodoItem(id: String(Int(Date().timeIntervalSince1970 * 1000)), text: trimmed))
        save()
    }

    func toggleTodo(_ id: String) {
        guard let i = data.todos.firstIndex(where: { $0.id == id }) else { return }
        data.todos[i].done.toggle()
        save()
    }

    func deleteTodo(_ id: String) {
        data.todos.removeAll { $0.id == id }
        save()
    }

    func addPhrase(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.phrases.append(PhraseItem(id: String(Int(Date().timeIntervalSince1970 * 1000)), text: trimmed))
        save()
    }

    func deletePhrase(_ id: String) {
        data.phrases.removeAll { $0.id == id }
        save()
    }

    func deletePerson(_ id: String) {
        data.entries.removeAll { $0.personId == id }
        data.persons.removeAll { $0.id == id }
        if calendarPersonID == id { calendarPersonID = data.persons.first?.id }
        save()
    }

    func addEntry(personID: String, date: String, mood: String, like: Int, text: String, photo: String?) {
        data.entries.append(Entry(id: String(Int(Date().timeIntervalSince1970 * 1000)),
                                  personId: personID, date: date, mood: mood,
                                  like: like, text: text, photo: photo))
        save()
    }

    func deleteEntry(_ id: String) {
        data.entries.removeAll { $0.id == id }
        save()
    }

    func markMutual(_ id: String) {
        updatePerson(id) { person in
            person.rel = "両思い"
            if person.mutual == nil { person.mutual = DateKit.todayString() }
        }
        if data.settings.celebrate, let p = person(id) {
            celebration = Celebration(person: p)
        }
    }

    func previewCelebration() {
        let sample = data.persons.first ?? Person(id: "sample", name: "あの人",
                                                  since: DateKit.todayString(), color: "#e8698a")
        var p = sample
        if p.mutual == nil { p.mutual = DateKit.todayString() }
        celebration = Celebration(person: p, isPreview: true)
    }

    func streak(for personID: String) -> Int {
        let dates = Set(data.entries.filter { $0.personId == personID }.map { $0.date })
        var cursor = Calendar.current.startOfDay(for: Date())
        if !dates.contains(DateKit.string(from: cursor)) {
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var count = 0
        while dates.contains(DateKit.string(from: cursor)) {
            count += 1
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return count
    }

    static func reachedMilestone(_ days: Int, step: Int) -> Int {
        let s = step > 0 ? step : 100
        let byStep = (days / s) * s
        let years = (days / 365) * 365
        return max(byStep, years)
    }

    static func milestoneLabel(_ m: Int) -> String {
        m % 365 == 0 && m > 0 ? "\(m / 365)年" : "\(m)日"
    }

    static func nextMilestoneText(_ days: Int, step: Int) -> String {
        let s = step > 0 ? step : 100
        let byStep = (days / s + 1) * s
        let byYear = (days / 365 + 1) * 365
        let n = min(byStep, byYear)
        return "\(milestoneLabel(n))まであと\(n - days)日"
    }

    func checkMilestones() {
        var events: [String] = []
        var changed = false
        for i in data.persons.indices {
            let reached = Self.reachedMilestone(DateKit.daysSince(data.persons[i].since), step: data.settings.mileStep)
            if data.persons[i].mileDone == nil {
                data.persons[i].mileDone = reached
                changed = true
            } else if reached > (data.persons[i].mileDone ?? 0) {
                data.persons[i].mileDone = reached
                changed = true
                if data.settings.mileEvent {
                    events.append("\(data.persons[i].name) \(Self.milestoneLabel(reached))")
                }
            }
        }
        if changed { save() }
        if !events.isEmpty {
            milestoneText = "好きになってから " + events.joined(separator: "、") + " になりました。"
        }
    }

    static func nextBirthday(from birthday: String) -> Date? {
        guard let b = DateKit.date(from: birthday) else { return nil }
        let cal = Calendar.current
        let bc = cal.dateComponents([.month, .day], from: b)
        let today = cal.startOfDay(for: Date())
        let thisYear = cal.component(.year, from: Date())
        func candidate(_ year: Int) -> Date? {
            var c = DateComponents()
            c.year = year; c.month = bc.month; c.day = bc.day
            guard let d = cal.date(from: c) else { return nil }
            return cal.startOfDay(for: d)
        }
        if let c0 = candidate(thisYear), c0 >= today { return c0 }
        return candidate(thisYear + 1)
    }

    static func birthdayText(_ birthday: String?) -> String? {
        guard let birthday, let next = nextBirthday(from: birthday) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: next).day ?? 0
        if days == 0 { return "今日が誕生日" }
        return "誕生日まであと\(days)日"
    }

    func checkBirthdays() {
        let names = data.persons.compactMap { person -> String? in
            guard let b = person.birthday, let bd = DateKit.date(from: b) else { return nil }
            let bc = Calendar.current.dateComponents([.month, .day], from: bd)
            let tc = Calendar.current.dateComponents([.month, .day], from: Date())
            return (bc.month == tc.month && bc.day == tc.day) ? person.name : nil
        }
        if !names.isEmpty {
            birthdayText = "今日は \(names.joined(separator: "、")) の誕生日です"
        }
    }

    func makeExportFile() throws -> URL {
        let backup = BackupFile(app: "crush-calendar", version: 1,
                                exportedAt: ISO8601DateFormatter().string(from: Date()),
                                theme: themeKey.rawValue,
                                persons: data.persons, entries: data.entries,
                                settings: data.settings, todos: data.todos, phrases: data.phrases)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let raw = try encoder.encode(backup)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kataomoi-backup-\(DateKit.todayString()).json")
        try raw.write(to: url, options: [.atomic])
        UserDefaults.standard.set(DateKit.todayString(), forKey: "kataomoi-last-backup")
        objectWillChange.send()
        return url
    }

    func importBackup(_ backup: BackupFile, replace: Bool) {
        if replace {
            data = CalendarData(persons: backup.persons, entries: backup.entries,
                                settings: backup.settings ?? AppSettings(), todos: backup.todos ?? [], phrases: backup.phrases ?? [])
            if let t = backup.theme, let key = AppThemeKey(rawValue: t) { themeKey = key }
            calendarPersonID = data.persons.first?.id
        } else {
            let personIDs = Set(data.persons.map { $0.id })
            let entryIDs = Set(data.entries.map { $0.id })
            data.persons.append(contentsOf: backup.persons.filter { !personIDs.contains($0.id) })
            data.entries.append(contentsOf: backup.entries.filter { !entryIDs.contains($0.id) })
            let todoIDs = Set(data.todos.map { $0.id })
            data.todos.append(contentsOf: (backup.todos ?? []).filter { !todoIDs.contains($0.id) })
            let phraseIDs = Set(data.phrases.map { $0.id })
            data.phrases.append(contentsOf: (backup.phrases ?? []).filter { !phraseIDs.contains($0.id) })
        }
        save()
    }

    var dataSizeKB: Int {
        let raw = (try? JSONEncoder().encode(data)) ?? Data()
        return max(1, raw.count / 1024)
    }

    var lastBackupDate: String? {
        UserDefaults.standard.string(forKey: "kataomoi-last-backup")
    }
}

// MARK: - Root

struct TabDef {
    let key: String
    let title: String
    let icon: String
}

struct ContentView: View {
    @EnvironmentObject var store: CalendarStore
    @State private var selectedTab = "home"

    static let tabDefs: [TabDef] = [
        TabDef(key: "home", title: "ホーム", icon: "house.fill"),
        TabDef(key: "cal", title: "カレンダー", icon: "calendar"),
        TabDef(key: "stats", title: "統計", icon: "chart.bar.xaxis"),
        TabDef(key: "dash", title: "ウィジェット", icon: "square.grid.2x2.fill"),
        TabDef(key: "advice", title: "相談", icon: "bubble.left.and.bubble.right.fill")
    ]

    func tabShown(_ key: String) -> Bool {
        if key == "dash" { return store.data.settings.dash && store.data.settings.tabsShow["dash"] != false }
        return store.data.settings.tabsShow[key] != false
    }

    func tabTitle(_ def: TabDef) -> String {
        let custom = (store.data.settings.tabNames[def.key] ?? "").trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? def.title : custom
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                if tabShown("home") {
                    HomeView(goCalendar: { selectedTab = "cal" })
                        .tabItem { Label(tabTitle(Self.tabDefs[0]), systemImage: Self.tabDefs[0].icon) }
                        .tag("home")
                }
                if tabShown("cal") {
                    CalendarView()
                        .tabItem { Label(tabTitle(Self.tabDefs[1]), systemImage: Self.tabDefs[1].icon) }
                        .tag("cal")
                }
                if tabShown("stats") {
                    StatsView()
                        .tabItem { Label(tabTitle(Self.tabDefs[2]), systemImage: Self.tabDefs[2].icon) }
                        .tag("stats")
                }
                if tabShown("dash") {
                    DashView(goSettings: { selectedTab = "settings" })
                        .tabItem { Label(tabTitle(Self.tabDefs[3]), systemImage: Self.tabDefs[3].icon) }
                        .tag("dash")
                }
                if tabShown("advice") {
                    AdviceView()
                        .tabItem { Label(tabTitle(Self.tabDefs[4]), systemImage: Self.tabDefs[4].icon) }
                        .tag("advice")
                }
                SettingsView(selectedTab: $selectedTab)
                    .tabItem { Label("設定", systemImage: "gearshape.fill") }
                    .tag("settings")
            }
            .tint(store.theme.deep)
            .fontDesign(.rounded)
            .background(store.theme.cream.ignoresSafeArea())

            if let celebration = store.celebration {
                CelebrationView(celebration: celebration)
                    .environmentObject(store)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .task { store.checkMilestones(); store.checkBirthdays() }
        .alert("記念日おめでとう", isPresented: Binding(
            get: { store.milestoneText != nil },
            set: { if !$0 { store.milestoneText = nil } }
        )) {
            Button("ありがとう") { store.milestoneText = nil }
        } message: {
            Text(store.milestoneText ?? "")
        }
        .alert("お誕生日おめでとう", isPresented: Binding(
            get: { store.birthdayText != nil },
            set: { if !$0 { store.birthdayText = nil } }
        )) {
            Button("ありがとう") { store.birthdayText = nil }
        } message: {
            Text(store.birthdayText ?? "")
        }
        .onChange(of: store.data.settings.tabsShow) { _, _ in ensureSelection() }
        .onChange(of: store.data.settings.dash) { _, _ in ensureSelection() }
    }

    private func ensureSelection() {
        if selectedTab == "settings" { return }
        if !tabShown(selectedTab) {
            selectedTab = Self.tabDefs.first(where: { tabShown($0.key) })?.key ?? "settings"
        }
    }
}

// MARK: - Shared pieces

struct PersonAvatar: View {
    @EnvironmentObject var store: CalendarStore
    let person: Person
    var size: CGFloat = 40

    var body: some View {
        Group {
            if store.data.settings.icons, let image = ImageData.uiImage(from: person.icon) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if store.data.settings.icons {
                ZStack {
                    Circle().fill(Color(hex: person.color))
                    Text(String(person.name.prefix(1)))
                        .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            } else {
                Circle()
                    .fill(Color(hex: person.color))
                    .frame(width: 12, height: 12)
            }
        }
        .frame(width: store.data.settings.icons ? size : 12,
               height: store.data.settings.icons ? size : 12)
        .clipShape(Circle())
    }
}

struct CardStyle: ViewModifier {
    @EnvironmentObject var store: CalendarStore
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(store.theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: store.theme.deep.opacity(0.10), radius: 12, x: 0, y: 5)
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 24) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }
}

struct EmptyState: View {
    @EnvironmentObject var store: CalendarStore
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 999)
                .fill(store.theme.blush)
                .frame(width: 44, height: 4)
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(store.theme.sub)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var store: CalendarStore
    let goCalendar: () -> Void
    @State private var showAdd = false
    @State private var editTarget: Person?
    @State private var deleteTarget: Person?
    @State private var mutualTarget: Person?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.data.persons.isEmpty {
                        EmptyState(message: "片思い中の人がいません\n下から追加してみよう")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(store.data.persons) { person in
                                personCard(person)
                            }
                        }
                    }

                    if store.data.persons.isEmpty {
                        Button {
                            showAdd = true
                        } label: {
                            Text("＋ 新しく追加")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(store.theme.deep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(store.theme.blush, style: StrokeStyle(lineWidth: 1.6, dash: [6, 5]))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .background(store.theme.cream.ignoresSafeArea())
            .sheet(isPresented: $showAdd) {
                PersonEditView(existing: nil)
                    .environmentObject(store)
            }
            .sheet(item: $editTarget) { person in
                PersonEditView(existing: person)
                    .environmentObject(store)
            }
            .confirmationDialog(
                deleteTarget.map { "\($0.name) を削除しますか？" } ?? "",
                isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("削除する", role: .destructive) {
                    if let target = deleteTarget { store.deletePerson(target.id) }
                    deleteTarget = nil
                }
                Button("キャンセル", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("関連する記録もすべて削除されます。")
            }
            .confirmationDialog(
                "両思いになりましたか？",
                isPresented: Binding(get: { mutualTarget != nil }, set: { if !$0 { mutualTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("両思いになった") {
                    if let target = mutualTarget { store.markMutual(target.id) }
                    mutualTarget = nil
                }
                Button("まだ", role: .cancel) { mutualTarget = nil }
            } message: {
                Text(mutualTarget.map { "\($0.name)との関係を「両思い」にします。" } ?? "")
            }
        }
    }

    private func personCard(_ person: Person) -> some View {
        let entries = store.entries(for: person.id)
        let lastLike = entries.last?.like
        let days = DateKit.daysSince(person.since)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                PersonAvatar(person: person, size: 60)
                Spacer()
                Button {
                    editTarget = person
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(store.theme.muted)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("編集")
                Button {
                    deleteTarget = person
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(store.theme.muted)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("削除")
            }

            HStack(alignment: .center, spacing: 8) {
                Text(person.name)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(store.theme.text)
                    .lineLimit(1)
                Text(person.rel ?? "片思い")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(store.theme.rose)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(store.theme.petal, in: Capsule())
            }
            .padding(.top, 10)

            Text("\(DateKit.japanese(person.since))から")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(store.theme.muted)
                .padding(.top, 6)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(days)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(store.theme.deep)
                Text("日間")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(store.theme.sub)
            }
            .padding(.top, 8)

            Text("最新の好き度: \(lastLike.map { "\($0)" } ?? "—")")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(store.theme.muted)
                .padding(.top, 2)

            HStack(spacing: 8) {
                Text(CalendarStore.nextMilestoneText(days, step: store.data.settings.mileStep))
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(store.theme.sub)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(store.theme.petal, in: Capsule())
                if let bText = CalendarStore.birthdayText(person.birthday) {
                    Text(bText)
                        .font(.system(.caption, design: .rounded).weight(bText == "今日が誕生日" ? .bold : .medium))
                        .foregroundStyle(bText == "今日が誕生日" ? .white : store.theme.sub)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(bText == "今日が誕生日" ? store.theme.rose : store.theme.petal, in: Capsule())
                }
            }
            .padding(.top, 10)

            if !person.fields.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(person.fields.filter { !$0.label.isEmpty }) { field in
                        HStack(spacing: 6) {
                            Text(field.label)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(store.theme.sub)
                            Text(field.value)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(store.theme.text)
                        }
                    }
                }
                .padding(.top, 10)
            }

            Button {
                store.calendarPersonID = person.id
                store.pendingDay = DateKit.todayString()
                goCalendar()
            } label: {
                Text("今日を記録")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color(hex: person.color), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            if (person.rel ?? "片思い") == "片思い" {
                Button {
                    mutualTarget = person
                } label: {
                    Text("両思いになった")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(store.theme.rose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().strokeBorder(store.theme.rose, lineWidth: 1.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding(16)
        .cardStyle(cornerRadius: 26)
        .contentShape(Rectangle())
        .onTapGesture {
            store.calendarPersonID = person.id
            goCalendar()
        }
    }

}
// MARK: - Person editor (add + edit)

struct PersonEditView: View {
    @EnvironmentObject var store: CalendarStore
    @Environment(\.dismiss) private var dismiss

    let existing: Person?

    @State private var name: String
    @State private var since: Date
    @State private var hasMet: Bool
    @State private var met: Date
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var rel: String
    @State private var color: String
    @State private var song: String
    @State private var fields: [CustomField]
    @State private var iconItem: PhotosPickerItem?
    @State private var showIconPicker = false
    @State private var iconDataURL: String?
    @State private var alertText: String?

    init(existing: Person?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _since = State(initialValue: DateKit.date(from: existing?.since ?? "") ?? Date())
        _hasMet = State(initialValue: existing?.met != nil)
        _met = State(initialValue: DateKit.date(from: existing?.met ?? "") ?? Date())
        _hasBirthday = State(initialValue: existing?.birthday != nil)
        _birthday = State(initialValue: DateKit.date(from: existing?.birthday ?? "") ?? Date())
        _rel = State(initialValue: existing?.rel ?? "片思い")
        _color = State(initialValue: existing?.color ?? CalendarStore.personColors[0])
        _song = State(initialValue: existing?.song ?? "")
        _fields = State(initialValue: existing?.fields ?? [])
        _iconDataURL = State(initialValue: existing?.icon)
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(hex: color) }, set: { color = $0.hexString })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("呼び名") {
                    TextField("例：Kくん、花ちゃん", text: $name)
                }
                Section("日付") {
                    DatePicker("好きになった日", selection: $since, displayedComponents: .date)
                    Toggle("出会った日を設定", isOn: $hasMet)
                    if hasMet {
                        DatePicker("出会った日", selection: $met, displayedComponents: .date)
                    }
                }
                Section("誕生日（任意）") {
                    Toggle("誕生日を設定", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("誕生日", selection: $birthday, displayedComponents: .date)
                    }
                }
                Section("関係") {
                    Picker("関係", selection: $rel) {
                        ForEach(CalendarStore.relations, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("カラー") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 10)], spacing: 10) {
                        ForEach(CalendarStore.personColors, id: \.self) { c in
                            Button {
                                color = c
                            } label: {
                                Circle()
                                    .fill(Color(hex: c))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle().strokeBorder(Color.primary.opacity(color == c ? 0.65 : 0),
                                                              lineWidth: 2.4)
                                    )
                                    .padding(3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ColorPicker("パレットから選ぶ", selection: colorBinding, supportsOpacity: false)
                }
                Section("カスタム項目") {
                    ForEach($fields) { $field in
                        HStack(spacing: 8) {
                            TextField("項目名（例：好きな色）", text: $field.label)
                                .frame(maxWidth: 130)
                            TextField("内容（例：青）", text: $field.value)
                            Button(role: .destructive) {
                                fields.removeAll { $0.id == $field.wrappedValue.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("＋ 項目を追加") {
                        fields.append(CustomField(id: UUID().uuidString, label: "", value: ""))
                    }
                }
                Section("曲（任意）") {
                    TextField("Spotifyの曲・プレイリストのURL", text: $song)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("アイコン（任意）") {
                    HStack(spacing: 12) {
                        if let image = ImageData.uiImage(from: iconDataURL) {
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        }
                        Button {
                            showIconPicker = true
                        } label: {
                            Text(iconDataURL == nil ? "写真を選ぶ" : "写真を変更")
                        }
                        .buttonStyle(.plain)
                        if iconDataURL != nil {
                            Button("外す", role: .destructive) { iconDataURL = nil; iconItem = nil }
                        }
                    }
                }
            }
            .fontDesign(.rounded)
            .navigationTitle(existing == nil ? "新しく追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "追加する" : "保存する") { save() }
                        .fontWeight(.bold)
                }
            }
            .alert("入力を確認してください", isPresented: Binding(
                get: { alertText != nil }, set: { if !$0 { alertText = nil } }
            )) {
                Button("OK") { alertText = nil }
            } message: {
                Text(alertText ?? "")
            }
            .photosPicker(isPresented: $showIconPicker, selection: $iconItem, matching: .images)
            .onChange(of: iconItem) { _, newItem in
                Task { @MainActor in
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        iconDataURL = ImageData.dataURL(from: image, maxPixel: 240, square: true)
                    }
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { alertText = "呼び名を入力してね"; return }
        let cleanedFields = fields
            .map { CustomField(id: $0.id,
                                label: $0.label.trimmingCharacters(in: .whitespaces),
                                value: $0.value.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.label.isEmpty }
        let songValue = song.trimmingCharacters(in: .whitespaces)
        if let existing {
            store.updatePerson(existing.id) { p in
                p.name = trimmed
                p.since = DateKit.string(from: since)
                p.met = hasMet ? DateKit.string(from: met) : nil
                p.birthday = hasBirthday ? DateKit.string(from: birthday) : nil
                p.rel = rel
                p.color = color
                p.song = songValue.isEmpty ? nil : songValue
                p.icon = iconDataURL
                p.fields = cleanedFields
            }
        } else {
            store.addPerson(name: trimmed,
                            since: DateKit.string(from: since),
                            met: hasMet ? DateKit.string(from: met) : nil,
                            color: color, rel: rel,
                            birthday: hasBirthday ? DateKit.string(from: birthday) : nil,
                            icon: iconDataURL,
                            song: songValue.isEmpty ? nil : songValue,
                            fields: cleanedFields)
        }
        dismiss()
    }
}

// MARK: - Calendar

struct DayRequest: Identifiable {
    let date: String
    var id: String { date }
}

struct CalendarView: View {
    @EnvironmentObject var store: CalendarStore
    @State private var selectedPersonID: String?
    @State private var monthDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var selectedDate = DateKit.todayString()
    @State private var dayRequest: DayRequest?

    private var person: Person? {
        store.person(selectedPersonID ?? store.calendarPersonID)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.data.persons.isEmpty {
                    EmptyState(message: "先に片思い中の人を追加してね")
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 10) {
                        if store.data.persons.count > 1 {
                            personPicker
                        }
                        monthHeader
                        calendarGrid
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    ScrollView {
                        VStack(spacing: 14) {
                            dayPanel
                            if let person, let songURL = spotifyEmbedURL(person.song) {
                                SpotifySongCard(url: songURL)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 28)
                    }
                }
            }
            .background(store.theme.cream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                selectedPersonID = person?.id
                consumePendingDay()
            }
            .onChange(of: store.calendarPersonID) { _, newValue in
                if let newValue { selectedPersonID = newValue }
            }
            .onChange(of: store.pendingDay) { _, _ in consumePendingDay() }
            .sheet(item: $dayRequest) { request in
                if let person {
                    DaySheet(personID: person.id, date: request.date)
                        .environmentObject(store)
                }
            }
        }
    }

    private func consumePendingDay() {
        if let day = store.pendingDay {
            if let p = person { selectedPersonID = p.id }
            if let d = DateKit.date(from: day) {
                monthDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: d)) ?? monthDate
            }
            selectedDate = day
            dayRequest = DayRequest(date: day)
            store.pendingDay = nil
        }
    }

    private var personPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.data.persons) { p in
                    let active = p.id == person?.id
                    Button {
                        selectedPersonID = p.id
                        store.calendarPersonID = p.id
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(active ? Color.white.opacity(0.9) : Color(hex: p.color))
                                .frame(width: 7, height: 7)
                            Text(p.name)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        }
                        .foregroundStyle(active ? Color.white : store.theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(active ? Color(hex: p.color) : store.theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(hex: p.color).opacity(active ? 0 : 0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var monthHeader: some View {
        let comps = Calendar.current.dateComponents([.year, .month], from: monthDate)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("\(comps.year ?? 0)年")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(store.theme.sub)
                Spacer()
                Button {
                    shiftMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("前月")
                Button("今日") { goToday() }
                    .buttonStyle(.glass)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("次月")
            }
            Text("\(comps.month ?? 1)月")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(store.theme.text)
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: monthDate) {
            monthDate = next
            selectDefaultDay()
        }
    }

    private func goToday() {
        monthDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        selectedDate = DateKit.todayString()
    }

    private func selectDefaultDay() {
        let comps = Calendar.current.dateComponents([.year, .month], from: monthDate)
        let prefix = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        let today = DateKit.todayString()
        if today.hasPrefix(prefix) {
            selectedDate = today
        } else {
            selectedDate = DateKit.key(year: comps.year ?? 2026, month: comps.month ?? 1, day: 1)
        }
    }

    private var calendarGrid: some View {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: monthDate)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        let first = DateKit.date(from: DateKit.key(year: year, month: month, day: 1)) ?? monthDate
        let blanks = (cal.component(.weekday, from: first) - 1 + 7) % 7
        let dayCount = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let today = DateKit.todayString()

        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(Array(["日", "月", "火", "水", "木", "金", "土"].enumerated()), id: \.offset) { i, d in
                    Text(d)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(i == 0 ? Color(hex: "#e05575") : i == 6 ? Color(hex: "#4a7fd4") : store.theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<blanks, id: \.self) { _ in
                    Color.clear.frame(height: 52)
                }
                ForEach(1...dayCount, id: \.self) { day in
                    dayCell(year: year, month: month, day: day, today: today)
                }
            }
        }
        .padding(12)
        .cardStyle()
    }

    private func dayCell(year: Int, month: Int, day: Int, today: String) -> some View {
        let ds = DateKit.key(year: year, month: month, day: day)
        let entries = person.map { store.entries(for: $0.id, on: ds) } ?? []
        let isToday = ds == today
        let isSelected = ds == selectedDate
        let isSpecial = person.map { p in
            p.since == ds || p.met == ds || p.mutual == ds ||
            (p.birthday.map { String($0.dropFirst(5)) == String(ds.dropFirst(5)) } ?? false)
        } ?? false
        return Button {
            selectedDate = ds
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isToday {
                        Circle().fill(store.theme.rose).frame(width: 30, height: 30)
                    } else if isSelected {
                        Circle().fill(store.theme.petal).frame(width: 30, height: 30)
                    }
                    Text("\(day)")
                        .font(.system(size: 16, weight: isToday || isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isToday ? Color.white : store.theme.text)
                }
                .frame(height: 30)
                HStack(spacing: 3) {
                    if !entries.isEmpty {
                        Circle().fill(Color(hex: person?.color ?? "#e8698a")).frame(width: 5, height: 5)
                    }
                    if isSpecial {
                        Circle().fill(store.theme.rose).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Selected day panel (below the grid)

    private var selectedEntries: [Entry] {
        person.map { store.entries(for: $0.id, on: selectedDate) } ?? []
    }

    private var panelTitle: String {
        guard let d = DateKit.date(from: selectedDate) else { return selectedDate }
        let cal = Calendar.current
        let m = cal.component(.month, from: d)
        let day = cal.component(.day, from: d)
        let wd = ["日", "月", "火", "水", "木", "金", "土"][cal.component(.weekday, from: d) - 1]
        if selectedDate == DateKit.todayString() { return "\(m)月\(day)日（\(wd)）・今日" }
        return "\(m)月\(day)日（\(wd)）"
    }

    private var dayPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(panelTitle)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(store.theme.text)
                Spacer()
                Button {
                    dayRequest = DayRequest(date: selectedDate)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                        Text("編集")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    }
                }
                .buttonStyle(.glass)
            }

            if let person {
                specialRows(person)
            }

            if selectedEntries.isEmpty {
                Text("この日の記録はまだありません。編集ボタンから記録できます。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.muted)
                    .padding(.vertical, 4)
            } else {
                ForEach(selectedEntries) { entry in
                    entryRow(entry)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    @ViewBuilder
    private func specialRows(_ person: Person) -> some View {
        let ds = selectedDate
        VStack(spacing: 8) {
            if let b = person.birthday, String(b.dropFirst(5)) == String(ds.dropFirst(5)) {
                specialRow(icon: "gift.fill", color: Color(hex: "#e8698a"), text: "\(person.name)の誕生日")
            }
            if person.since == ds {
                specialRow(icon: "heart.fill", color: store.theme.blush, text: "好きになった日")
            }
            if person.met == ds {
                specialRow(icon: "sparkles", color: Color(hex: person.color), text: "出会った日")
            }
            if person.mutual == ds {
                specialRow(icon: "heart.circle.fill", color: Color(hex: "#e8698a"), text: "両思いになった日")
            }
        }
    }

    private func specialRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color, in: Circle())
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(store.theme.text)
            Spacer()
            Text("終日")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(store.theme.muted)
        }
    }

    private func entryRow(_ entry: Entry) -> some View {
        Button {
            dayRequest = DayRequest(date: selectedDate)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(hex: person?.color ?? "#e8698a"))
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if !entry.mood.isEmpty {
                            Text(entry.mood)
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(store.theme.text)
                        }
                        Text("好き度 \(entry.like)")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(store.theme.deep)
                        Spacer()
                    }
                    if !entry.text.isEmpty {
                        Text(entry.text)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(store.theme.sub)
                            .multilineTextAlignment(.leading)
                    }
                    if let photo = entry.photo, let image = ImageData.uiImage(from: photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 170)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func spotifyEmbedURL(_ song: String?) -> URL? {
        guard let song, !song.isEmpty else { return nil }
        return URL(string: song)
    }
}

struct SpotifySongCard: View {
    @EnvironmentObject var store: CalendarStore
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(store.theme.rose, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("この人の曲")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(store.theme.text)
                Text("Spotifyで開きます")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(store.theme.muted)
            }
            Spacer()
            Link(destination: url) {
                Text("開く")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
            }
            .buttonStyle(.glass)
        }
        .padding(12)
        .cardStyle(cornerRadius: 18)
    }
}

// MARK: - Day sheet

struct DaySheet: View {
    @EnvironmentObject var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    let personID: String
    let date: String

    @State private var mood = ""
    @State private var like: Double = 70
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var photoDataURL: String?

    private let moods = ["ときめき", "普通", "切ない", "つらい"]

    private var person: Person? { store.person(personID) }
    private var existing: [Entry] { store.entries(for: personID, on: date) }

    var body: some View {
        NavigationStack {
            Form {
                if let person {
                    Section {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: person.color)).frame(width: 8, height: 8)
                            Text(person.name)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Spacer()
                            if person.since == date { badge("好きになった日") }
                            if person.met == date { badge("出会った日") }
                            if person.mutual == date { badge("両思いになった日") }
                            if let b = person.birthday, String(b.dropFirst(5)) == String(date.dropFirst(5)) { badge("誕生日") }
                        }
                    }
                }

                if !existing.isEmpty {
                    Section("記録済み") {
                        ForEach(existing) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    if !entry.mood.isEmpty {
                                        Text(entry.mood)
                                            .font(.system(.caption, design: .rounded).weight(.semibold))
                                            .foregroundStyle(store.theme.rose)
                                    }
                                    Text("好き度 \(entry.like)/100")
                                        .font(.system(.caption, design: .rounded).weight(.bold))
                                        .foregroundStyle(store.theme.rose)
                                    Spacer()
                                    Button("削除", role: .destructive) {
                                        store.deleteEntry(entry.id)
                                    }
                                    .font(.system(.caption, design: .rounded))
                                }
                                if !entry.text.isEmpty {
                                    Text(entry.text)
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(store.theme.text)
                                }
                                if let image = ImageData.uiImage(from: entry.photo) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("この日に記録を追加") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(moods, id: \.self) { m in
                                Button {
                                    mood = (mood == m) ? "" : m
                                } label: {
                                    Text(m)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(mood == m ? Color.white : store.theme.sub)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(mood == m ? store.theme.rose : store.theme.petal, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("好き度")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(store.theme.muted)
                            Spacer()
                            Text("\(Int(like))")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(store.theme.rose)
                        }
                        Slider(value: $like, in: 1...100, step: 1)
                            .tint(store.theme.rose)
                        HStack {
                            Text("低")
                            Spacer()
                            Text("高")
                        }
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(store.theme.muted)
                    }

                    TextEditor(text: $text)
                        .frame(minHeight: 90)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("今日あったこと、感じた気持ち…")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(store.theme.muted)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }

                    HStack(spacing: 12) {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("写真を選ぶ", systemImage: "photo")
                        }
                        .buttonStyle(.plain)
                        if photoDataURL != nil {
                            Button("写真を外す", role: .destructive) {
                                photoDataURL = nil
                                photoItem = nil
                            }
                        }
                    }
                    if let image = ImageData.uiImage(from: photoDataURL) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .fontDesign(.rounded)
            .navigationTitle(DateKit.japaneseWithWeekday(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存する") {
                        store.addEntry(personID: personID, date: date, mood: mood,
                                       like: Int(like), text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                       photo: photoDataURL)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, newItem in
                Task { @MainActor in
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photoDataURL = ImageData.dataURL(from: image, maxPixel: 900, square: false)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(store.theme.deep)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(store.theme.petal, in: Capsule())
    }
}

// MARK: - Stats

struct StatsView: View {
    @EnvironmentObject var store: CalendarStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if store.data.persons.isEmpty {
                        EmptyState(message: "片思い中の人を追加すると統計が見られます")
                    } else {
                        summaryGrid
                        ForEach(store.data.persons) { person in
                            personStat(person)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(store.theme.cream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var summaryGrid: some View {
        let totalDays = store.data.persons.reduce(0) { $0 + DateKit.daysSince($1.since) }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statCard(value: "\(store.data.persons.count)", label: "登録した人数")
            statCard(value: "\(totalDays)", label: "合計片思い日数")
            statCard(value: "\(store.data.entries.count)", label: "記録の数")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(store.theme.deep)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(store.theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .cardStyle(cornerRadius: 18)
    }

    private func personStat(_ person: Person) -> some View {
        let entries = store.entries(for: person.id)
        let last = entries.last?.like
        let first = entries.first?.like
        let diff: Int? = (last != nil && first != nil) ? (last! - first!) : nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(Color(hex: person.color)).frame(width: 8, height: 8)
                    Text(person.name)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(store.theme.text)
                }
                Spacer()
                if let diff {
                    Text(diff > 0 ? "▲\(diff)" : diff < 0 ? "▼\(abs(diff))" : "変化なし")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(diff > 0 ? store.theme.rose : store.theme.muted)
                }
            }

            Text("好きになってから \(DateKit.daysSince(person.since)) 日間" + (person.met.map { " ／ 出会った日: \(DateKit.japanese($0))" } ?? ""))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(store.theme.muted)
            if let birthday = person.birthday {
                Text("誕生日: \(DateKit.japanese(birthday))" + (CalendarStore.birthdayText(birthday).map { " ／ \($0)" } ?? ""))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(store.theme.muted)
            }

            if let last {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(store.theme.petal)
                        Capsule()
                            .fill(LinearGradient(colors: [store.theme.blush, store.theme.rose], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(last) / 100)
                    }
                }
                .frame(height: 5)
                Text("最新: \(last)/100 ／ 記録 \(entries.count)件")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(store.theme.muted)
            } else {
                Text("まだ記録がありません")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(store.theme.muted)
            }

            Text("連続記録 \(store.streak(for: person.id))日 ／ \(CalendarStore.nextMilestoneText(DateKit.daysSince(person.since), step: store.data.settings.mileStep))")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(store.theme.muted)

            if entries.count > 1 {
                Sparkline(entries: entries, color: Color(hex: person.color))
                    .frame(height: 56)
            }
        }
        .padding(16)
        .cardStyle()
    }
}

struct Sparkline: View {
    let entries: [Entry]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let points = makePoints(size: geo.size)
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .position(point)
                }
            }
        }
    }

    private func makePoints(size: CGSize) -> [CGPoint] {
        guard !entries.isEmpty else { return [] }
        let times = entries.map { DateKit.date(from: $0.date)?.timeIntervalSince1970 ?? 0 }
        let t0 = times.min() ?? 0
        let span = max(1, (times.max() ?? 0) - t0)
        return entries.enumerated().map { i, entry in
            let x: CGFloat
            if entries.count == 1 {
                x = size.width / 2
            } else if span <= 1 {
                x = 6 + CGFloat(i) / CGFloat(entries.count - 1) * (size.width - 12)
            } else {
                x = 6 + CGFloat((times[i] - t0) / span) * (size.width - 12)
            }
            let y = size.height - (CGFloat(entry.like) / 100) * (size.height - 8) - 4
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Dashboard

struct DashView: View {
    @EnvironmentObject var store: CalendarStore
    let goSettings: () -> Void
    @StateObject private var weather = WeatherModel()
    @State private var laActive = false

    private var widgets: [String] { store.data.settings.widgets }
    private var missing: [String] {
        ["weather", "music", "todo", "phrase"].filter { !widgets.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if widgets.isEmpty {
                        EmptyState(message: "ウィジェットがありません\n下から追加できます")
                    }
                    ForEach(widgets, id: \.self) { widget in
                        widgetCard(widget)
                    }
                    liveActivityCard
                    widgetLinkCard
                    if !missing.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(missing, id: \.self) { widget in
                                Button {
                                    store.updateSettings { $0.widgets.append(widget) }
                                } label: {
                                    Text("＋ \(widgetLabel(widget))")
                                }
                                .buttonStyle(.glass)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(store.theme.cream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { weather.loadIfNeeded() }
        }
    }

    private func widgetLabel(_ widget: String) -> String {
        widget == "weather" ? "天気" : widget == "music" ? "ミュージック" : widget == "todo" ? "ToDo" : "言葉"
    }

    private var liveActivityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ライブアクティビティ")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(store.theme.muted)
            if let person = store.data.persons.first {
                HStack(spacing: 10) {
                    PersonAvatar(person: person, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(person.name)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(store.theme.text)
                        Text("好きになって \(DateKit.daysSince(person.since)) 日目")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(store.theme.muted)
                    }
                    Spacer()
                    if laActive {
                        Button("停止") { stopLiveActivity() }
                            .buttonStyle(.glass)
                    } else {
                        Button("開始") { startLiveActivity() }
                            .buttonStyle(.glass)
                    }
                }
                Text("ロック画面とDynamic Islandに日数を表示します。仕様で最大8時間で自動終了します。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(store.theme.muted)
            } else {
                Text("人を登録すると使えます。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.sub)
            }
        }
        .padding(16)
        .cardStyle()
        .onAppear { laActive = !Activity<DaysActivityAttributes>.activities.isEmpty }
    }

    private var widgetLinkCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ウィジェット連携（確認用）")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(store.theme.muted)
            diagRow("付与グループ", SharedStore.provisionedGroupIDs().first ?? "なし")
            diagRow("共有フォルダ", SharedStore.fileURL != nil ? "OK" : "取得できず")
            diagRow("最終書込み", lastWidgetWriteText)
        }
        .padding(16)
        .cardStyle()
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(store.theme.sub)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(store.theme.text)
                .lineLimit(2)
        }
    }

    private var lastWidgetWriteText: String {
        let ud = UserDefaults.standard
        guard let at = ud.object(forKey: "kataomoi-widget-write-at") as? Double else { return "まだ" }
        let ok = ud.string(forKey: "kataomoi-widget-write") ?? "ng"
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm:ss"
        return "\(f.string(from: Date(timeIntervalSince1970: at))) \(ok == "ok" ? "成功" : "失敗")"
    }

    private func startLiveActivity() {
        guard let person = store.data.persons.first else { return }
        let days = DateKit.daysSince(person.since)
        let attributes = DaysActivityAttributes(personName: person.name, colorHex: person.color)
        let content = ActivityContent(
            state: DaysActivityAttributes.ContentState(days: days, milestoneText: CalendarStore.nextMilestoneText(days, step: store.data.settings.mileStep)),
            staleDate: Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 3600)
        )
        do {
            _ = try Activity.request(attributes: attributes, content: content)
            laActive = true
        } catch {
            laActive = false
        }
    }

    private func stopLiveActivity() {
        Task {
            for activity in Activity<DaysActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            laActive = false
        }
    }

    private func widgetCard(_ widget: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(widgetLabel(widget))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(store.theme.muted)
                Spacer()
                Button("削除") {
                    store.updateSettings { settings in
                        settings.widgets.removeAll { $0 == widget }
                    }
                }
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(store.theme.muted)
                .buttonStyle(.plain)
            }
            if widget == "weather" {
                WeatherWidget(model: weather)
            } else if widget == "todo" {
                TodoCard()
            } else if widget == "phrase" {
                PhraseCard()
            } else {
                MusicWidget(goSettings: goSettings)
            }
        }
        .padding(16)
        .cardStyle()
    }
}

struct TodoCard: View {
    @EnvironmentObject var store: CalendarStore
    @State private var newText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.data.todos.isEmpty {
                Text("ToDoはまだありません。下から追加できます。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.sub)
            }
            ForEach(store.data.todos) { todo in
                HStack(spacing: 10) {
                    Button {
                        store.toggleTodo(todo.id)
                    } label: {
                        Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19))
                            .foregroundStyle(todo.done ? store.theme.rose : store.theme.muted)
                    }
                    .buttonStyle(.plain)
                    Text(todo.text)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(todo.done ? store.theme.muted : store.theme.text)
                        .strikethrough(todo.done)
                    Spacer()
                    Button {
                        store.deleteTodo(todo.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(store.theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                TextField("新しいToDo", text: $newText)
                    .font(.system(.subheadline, design: .rounded))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("追加") { add() }
                    .buttonStyle(.glass)
            }
        }
    }

    private func add() {
        store.addTodo(newText)
        newText = ""
    }
}

struct PhraseCard: View {
    @EnvironmentObject var store: CalendarStore
    @State private var newText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.data.phrases.isEmpty {
                Text("言葉はまだありません。下から追加できます。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.sub)
            }
            ForEach(store.data.phrases) { phrase in
                HStack(spacing: 10) {
                    Text("「\(phrase.text)」")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(store.theme.text)
                    Spacer()
                    Button {
                        store.deletePhrase(phrase.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(store.theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                TextField("心に決めたい言葉", text: $newText)
                    .font(.system(.subheadline, design: .rounded))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("追加") { add() }
                    .buttonStyle(.glass)
            }
        }
    }

    private func add() {
        store.addPhrase(newText)
        newText = ""
    }
}

struct WeatherResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
    }
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Double?]?
    }
    let current: Current
    let daily: Daily
}

@MainActor
final class WeatherModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var response: WeatherResponse?
    @Published var place = ""
    @Published var failed = false
    @Published var errorText: String?

    private let manager = CLLocationManager()
    private var started = false
    private var usedFallback = false

    static let symbols: [Int: String] = [
        0: "sun.max.fill", 1: "sun.max.fill", 2: "cloud.sun.fill", 3: "cloud.fill",
        45: "cloud.fog.fill", 48: "cloud.fog.fill",
        51: "cloud.drizzle.fill", 53: "cloud.drizzle.fill", 55: "cloud.drizzle.fill",
        61: "cloud.rain.fill", 63: "cloud.rain.fill", 65: "cloud.heavyrain.fill",
        71: "cloud.snow.fill", 73: "cloud.snow.fill", 75: "cloud.snow.fill", 77: "cloud.snow.fill",
        80: "cloud.drizzle.fill", 81: "cloud.rain.fill", 82: "cloud.heavyrain.fill",
        85: "cloud.snow.fill", 86: "cloud.snow.fill",
        95: "cloud.bolt.rain.fill", 96: "cloud.bolt.rain.fill", 99: "cloud.bolt.rain.fill"
    ]

    static let labels: [Int: String] = [
        0: "快晴", 1: "晴れ", 2: "晴れ時々くもり", 3: "くもり", 45: "霧", 48: "霧",
        51: "小雨", 53: "霧雨", 55: "霧雨", 61: "雨", 63: "雨", 65: "強い雨",
        71: "雪", 73: "雪", 75: "大雪", 77: "雪", 80: "にわか雨", 81: "にわか雨",
        82: "激しいにわか雨", 85: "にわか雪", 86: "にわか雪", 95: "雷雨", 96: "雷雨", 99: "雷雨"
    ]

    func loadIfNeeded() {
        if started { return }
        started = true
        start()
    }

    func reload() {
        response = nil
        failed = false
        errorText = nil
        usedFallback = false
        started = true
        start()
    }

    func requestLocationAccess() {
        manager.delegate = self
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        @unknown default:
            break
        }
    }

    private func start() {
        manager.delegate = self
        // Show Tokyo right away so the widget never sits empty;
        // a real location fix replaces it when it arrives.
        if response == nil { fallback() }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { await fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, place: "現在地") }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Tokyo weather is already on screen as the baseline; nothing to do.
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    private func fallback() {
        if usedFallback { return }
        usedFallback = true
        Task { await fetch(lat: 35.68, lon: 139.76, place: "東京（位置情報なし）") }
    }

    private func fetch(lat: Double, lon: Double, place: String) async {
        let posix = Locale(identifier: "en_US_POSIX")
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(String(format: "%.2f", locale: posix, lat))&longitude=\(String(format: "%.2f", locale: posix, lon))&current=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=5"
        guard let url = URL(string: urlString) else {
            errorText = "URLを作れませんでした"
            if response == nil { failed = true }
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            response = try JSONDecoder().decode(WeatherResponse.self, from: data)
            self.place = place
            failed = false
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            if response == nil { failed = true }
        }
    }
}

struct WeatherWidget: View {
    @EnvironmentObject var store: CalendarStore
    @ObservedObject var model: WeatherModel

    var body: some View {
        Group {
            if let r = model.response {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: WeatherModel.symbols[r.current.weather_code] ?? "cloud.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(Color(hex: "#d7e7f5")))
                        Text("\(Int(r.current.temperature_2m.rounded()))°")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(store.theme.deep)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(WeatherModel.labels[r.current.weather_code] ?? "—")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(store.theme.text)
                            Text(model.place)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(store.theme.muted)
                        }
                    }
                    ForEach(Array(r.daily.time.enumerated()), id: \.offset) { i, day in
                        HStack(spacing: 8) {
                            Text(i == 0 ? "今日" : weekdayLabel(day))
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(store.theme.sub)
                                .frame(width: 34, alignment: .leading)
                            Image(systemName: WeatherModel.symbols[r.daily.weather_code[i]] ?? "cloud.fill")
                                .font(.system(size: 13))
                                .symbolRenderingMode(.multicolor)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color(hex: "#d7e7f5")))
                            Text(WeatherModel.labels[r.daily.weather_code[i]] ?? "—")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(store.theme.text)
                            Spacer()
                            Text(precipText(r, i))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(store.theme.muted)
                            Text("\(Int(r.daily.temperature_2m_max[i].rounded()))° / \(Int(r.daily.temperature_2m_min[i].rounded()))°")
                                .font(.system(.subheadline, design: .rounded))
                                .frame(width: 76, alignment: .trailing)
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) {
                            if i > 0 { Divider() }
                        }
                    }
                    HStack(spacing: 8) {
                        Button("更新") { model.reload() }
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .buttonStyle(.glass)
                        if model.place != "現在地" {
                            Button("現在地を使う") { model.requestLocationAccess() }
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .buttonStyle(.glass)
                        }
                        Spacer()
                        Text("天気データ: Open-Meteo API")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(store.theme.muted)
                    }
                    .padding(.top, 4)
                }
            } else if model.failed {
                VStack(alignment: .leading, spacing: 10) {
                    Text("天気を取得できませんでした。")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(store.theme.sub)
                    if let errorText = model.errorText {
                        Text(errorText)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(store.theme.muted)
                    }
                    Button("再読み込み") { model.reload() }
                        .buttonStyle(.glass)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("取得中…")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(store.theme.sub)
                }
                .onAppear { model.loadIfNeeded() }
            }
        }
        .task { model.loadIfNeeded() }
    }

    private func precipText(_ r: WeatherResponse, _ i: Int) -> String {
        guard let arr = r.daily.precipitation_probability_max, i < arr.count, let v = arr[i] else { return "降水 —" }
        return "降水 \(Int(v.rounded()))%"
    }

    private func weekdayLabel(_ day: String) -> String {
        guard let date = DateKit.date(from: day) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "E"
        return f.string(from: date)
    }
}

// MARK: - Spotify now playing

struct SpotifyNowPlaying: Decodable {
    struct Artist: Decodable { let name: String }
    struct Album: Decodable {
        struct Img: Decodable { let url: String }
        let images: [Img]
    }
    struct Item: Decodable {
        let name: String
        let artists: [Artist]
        let album: Album
        let duration_ms: Int
    }
    let is_playing: Bool
    let progress_ms: Int?
    let item: Item?
}

final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.windows.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}

@MainActor
final class SpotifyModel: ObservableObject {
    @Published var nowPlaying: SpotifyNowPlaying?
    @Published var fetchedAt: Date?
    @Published var loaded = false
    @Published var authError: String?

    var clientID = ""
    private let redirectURI = "kataomoi://callback"
    private var authSession: ASWebAuthenticationSession?
    private let presenter = AuthPresenter()

    var isConnected: Bool { UserDefaults.standard.string(forKey: "spotifyRefresh") != nil }

    private func ud(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    private func setUD(_ key: String, _ value: String?) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    func disconnect() {
        setUD("spotifyAccess", nil)
        setUD("spotifyRefresh", nil)
        UserDefaults.standard.removeObject(forKey: "spotifyExpiry")
        nowPlaying = nil
        loaded = false
    }

    func connect() {
        guard !clientID.isEmpty else { return }
        let verifier = Self.randomString(64)
        setUD("spotifyVerifier", verifier)
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user-read-currently-playing user-read-playback-state"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier))
        ]
        guard let url = comps.url else { return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "kataomoi") { [weak self] callback, error in
            Task { @MainActor in
                guard let self else { return }
                if let callback,
                   let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                       .queryItems?.first(where: { $0.name == "code" })?.value {
                    await self.exchange(code: code)
                } else if let error {
                    self.authError = error.localizedDescription
                }
            }
        }
        session.presentationContextProvider = presenter
        authSession = session
        session.start()
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    private func exchange(code: String) async {
        guard let verifier = ud("spotifyVerifier") else { return }
        let ok = await tokenRequest(body: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ])
        if ok { await refresh() }
    }

    private func tokenRequest(body: [String: String]) async -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            setUD("spotifyAccess", token.access_token)
            if let refresh = token.refresh_token { setUD("spotifyRefresh", refresh) }
            UserDefaults.standard.set(Date().timeIntervalSince1970 + Double(token.expires_in), forKey: "spotifyExpiry")
            return true
        } catch {
            authError = error.localizedDescription
            return false
        }
    }

    private func validToken() async -> String? {
        if let access = ud("spotifyAccess"),
           UserDefaults.standard.double(forKey: "spotifyExpiry") > Date().timeIntervalSince1970 + 30 {
            return access
        }
        guard let refresh = ud("spotifyRefresh") else { return nil }
        let ok = await tokenRequest(body: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID
        ])
        return ok ? ud("spotifyAccess") : nil
    }

    func refresh() async {
        guard isConnected else { loaded = true; return }
        guard let token = await validToken() else { loaded = true; return }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                nowPlaying = try JSONDecoder().decode(SpotifyNowPlaying.self, from: data)
                fetchedAt = Date()
            } else {
                nowPlaying = nil
                fetchedAt = nil
            }
        } catch {
            authError = error.localizedDescription
        }
        loaded = true
    }

    nonisolated static func randomString(_ length: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    nonisolated static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct MusicWidget: View {
    @EnvironmentObject var store: CalendarStore
    let goSettings: () -> Void
    @StateObject private var spotify = SpotifyModel()

    var body: some View {
        let withSongs = store.data.persons.filter { ($0.song ?? "").isEmpty == false }
        VStack(alignment: .leading, spacing: 12) {
            nowPlayingSection
            if !withSongs.isEmpty {
                Divider()
                ForEach(withSongs) { person in
                    HStack(spacing: 12) {
                        PersonAvatar(person: person, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.name)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(store.theme.text)
                            Text("Spotifyの曲")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(store.theme.muted)
                        }
                        Spacer()
                        if let url = URL(string: person.song ?? "") {
                            Link("開く", destination: url)
                                .buttonStyle(.glass)
                        }
                    }
                }
            } else if !store.data.settings.spId.isEmpty {
                Text("曲が設定されている人がいません。設定の「登録した人」からSpotifyのURLを入れられます。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.sub)
                    .lineSpacing(4)
            }
        }
        .task {
            spotify.clientID = store.data.settings.spId
            while !Task.isCancelled {
                await spotify.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func liveProgress(_ np: SpotifyNowPlaying, at now: Date) -> Double {
        let base = Double(np.progress_ms ?? 0)
        guard np.is_playing, let fetchedAt = spotify.fetchedAt else { return base }
        return min(base + now.timeIntervalSince(fetchedAt) * 1000, Double(np.item?.duration_ms ?? 0))
    }

    private func timeText(_ ms: Int) -> String {
        let sec = max(0, ms / 1000)
        return "\(sec / 60):\(String(format: "%02d", sec % 60))"
    }

    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.data.settings.spId.isEmpty {
                Text("Spotifyで再生中の曲を表示するには、設定でClient IDを入れて連携してください。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.sub)
                    .lineSpacing(4)
                Button("設定を開く") { goSettings() }
                    .buttonStyle(.glass)
            } else if !spotify.isConnected {
                Text("Spotifyと連携すると、再生中の曲がここに表示されます。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.sub)
                    .lineSpacing(4)
                Button("Spotifyと連携") {
                    spotify.clientID = store.data.settings.spId
                    spotify.connect()
                }
                .buttonStyle(.glass)
                if let authError = spotify.authError {
                    Text(authError)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(store.theme.muted)
                }
            } else if let np = spotify.nowPlaying, let item = np.item {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: item.album.images.first?.url ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(store.theme.petal)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(store.theme.text)
                            .lineLimit(1)
                        Text(item.artists.map { $0.name }.joined(separator: ", "))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(store.theme.muted)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: np.is_playing ? "play.fill" : "pause.fill")
                                .font(.system(size: 9))
                            Text(np.is_playing ? "再生中" : "一時停止中")
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                        }
                        .foregroundStyle(store.theme.rose)
                    }
                    Spacer()
                }
                if np.progress_ms != nil, item.duration_ms > 0 {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let current = liveProgress(np, at: context.date)
                        VStack(spacing: 3) {
                            ProgressView(value: current, total: Double(item.duration_ms))
                                .tint(store.theme.rose)
                            HStack {
                                Text(timeText(Int(current)))
                                Spacer()
                                Text(timeText(item.duration_ms))
                            }
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(store.theme.muted)
                        }
                    }
                }
            } else if spotify.loaded {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .foregroundStyle(store.theme.muted)
                    Text("今は再生していません")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(store.theme.sub)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("読み込み中…")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(store.theme.sub)
                }
            }
            if spotify.isConnected {
                HStack {
                    Spacer()
                    Button("連携を解除") { spotify.disconnect() }
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(store.theme.muted)
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: CalendarStore
    @Binding var selectedTab: String

    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var pendingBackup: BackupFile?
    @State private var showImportConfirm = false
    @State private var alertText: String?

    var body: some View {
        NavigationStack {
            Form {
                themeSection
                displaySection
                tabBarSection
                milestoneSection
                personsSection
                dashSection
                spotifySection
                aiSection
                dataSection
            }
            .fontDesign(.rounded)
            .scrollContentBackground(.hidden)
            .background(store.theme.cream.ignoresSafeArea())
            .listRowBackground(store.theme.card)
            .toolbar(.hidden, for: .navigationBar)
            .alert("お知らせ", isPresented: Binding(
                get: { alertText != nil }, set: { if !$0 { alertText = nil } }
            )) {
                Button("OK") { alertText = nil }
            } message: {
                Text(alertText ?? "")
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .confirmationDialog(
                "バックアップを読み込みますか？",
                isPresented: $showImportConfirm,
                titleVisibility: .visible
            ) {
                Button("統合") {
                    if let pendingBackup { store.importBackup(pendingBackup, replace: false) }
                    pendingBackup = nil
                }
                Button("置き換え", role: .destructive) {
                    if let pendingBackup { store.importBackup(pendingBackup, replace: true) }
                    pendingBackup = nil
                }
                Button("キャンセル", role: .cancel) { pendingBackup = nil }
            } message: {
                if let pendingBackup {
                    Text("ファイル内：片思い\(pendingBackup.persons.count)人 / 記録\(pendingBackup.entries.count)件。「統合」は今のデータに足し、「置き換え」は今のデータを消してファイルの内容にします。")
                }
            }
        }
    }

    // Theme

    private var themeSection: some View {
        Section("テーマカラー") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(AppThemeKey.allCases) { key in
                    let t = store.theme(for: key)
                    Button {
                        store.setTheme(key)
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(t.rose)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle().strokeBorder(t.deep, lineWidth: store.themeKey == key ? 2.4 : 0)
                                        .padding(-4)
                                )
                            Text(key.label)
                                .font(.system(.caption, design: .rounded).weight(store.themeKey == key ? .bold : .regular))
                                .foregroundStyle(store.theme.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            if store.themeKey == .custom {
                ColorPicker("好きな色を選ぶ", selection: Binding(
                    get: { Color(hex: store.customColorHex) },
                    set: { store.setCustomColor($0.hexString) }
                ), supportsOpacity: false)
            }
        }
    }

    // Display

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.data.settings[keyPath: keyPath] },
            set: { value in store.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Int> {
        Binding(
            get: { store.data.settings[keyPath: keyPath] },
            set: { value in store.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private var displaySection: some View {
        Section("表示") {
            Toggle("人のアイコンを表示", isOn: boolBinding(\.icons))
            Toggle("両思いの演出", isOn: boolBinding(\.celebrate))
            Picker("演出のスタイル", selection: Binding(
                get: { store.data.settings.style },
                set: { value in store.updateSettings { $0.style = value } }
            )) {
                Text("ハート").tag("heart")
                Text("紙吹雪").tag("confetti")
            }
            .pickerStyle(.segmented)
            Button("演出をプレビュー") { store.previewCelebration() }
        }
    }

    // Tab bar

    private func visibleCountAfterHiding(_ key: String) -> Int {
        ContentView.tabDefs.filter { def in
            if def.key == key { return false }
            if def.key == "dash" { return store.data.settings.dash && store.data.settings.tabsShow["dash"] != false }
            return store.data.settings.tabsShow[def.key] != false
        }.count
    }

    private func tabShowBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: {
                if key == "dash" { return store.data.settings.dash && store.data.settings.tabsShow["dash"] != false }
                return store.data.settings.tabsShow[key] != false
            },
            set: { value in
                if value {
                    store.updateSettings { settings in
                        if key == "dash" { settings.dash = true }
                        settings.tabsShow[key] = true
                    }
                } else {
                    guard visibleCountAfterHiding(key) >= 1 else {
                        alertText = "タブは1つ以上表示してください"
                        return
                    }
                    store.updateSettings { settings in
                        if key == "dash" { settings.dash = false }
                        settings.tabsShow[key] = false
                    }
                }
            }
        )
    }

    private var tabBarSection: some View {
        Section {
            ForEach(ContentView.tabDefs, id: \.key) { def in
                HStack {
                    TextField(def.title, text: Binding(
                        get: { store.data.settings.tabNames[def.key] ?? "" },
                        set: { value in
                            store.updateSettings { $0.tabNames[def.key] = String(value.prefix(6)) }
                        }
                    ))
                    .frame(maxWidth: 150)
                    Spacer()
                    Toggle("", isOn: tabShowBinding(def.key))
                        .labelsHidden()
                }
            }
        } header: {
            Text("タブバー（名前と表示）")
        } footer: {
            Text("名前は6文字までです。空にすると元の名前に戻ります。タブバーの色はテーマカラーに連動します。")
        }
    }

    private var milestoneSection: some View {
        Section("記念日") {
            Toggle("記念日のお祝い", isOn: boolBinding(\.mileEvent))
            Picker("日数の刻み", selection: intBinding(\.mileStep)) {
                Text("10日ごと").tag(10)
                Text("30日ごと").tag(30)
                Text("50日ごと").tag(50)
                Text("100日ごと").tag(100)
                Text("200日ごと").tag(200)
                Text("1年ごと").tag(365)
            }
        } footer: {
            Text("次の記念日は、この刻みと1年ごとの節目で数えます。")
        }
    }

    // Persons

    private var personsSection: some View {
        Section("登録した人") {
            if store.data.persons.isEmpty {
                Text("まだ誰も登録されていません")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.muted)
            }
            ForEach(store.data.persons) { person in
                PersonSettingsRow(personID: person.id)
            }
        }
    }

    // Dashboard & Spotify

    private func widgetBinding(_ widget: String) -> Binding<Bool> {
        Binding(
            get: { store.data.settings.widgets.contains(widget) },
            set: { value in
                store.updateSettings { settings in
                    if value {
                        if !settings.widgets.contains(widget) { settings.widgets.append(widget) }
                    } else {
                        settings.widgets.removeAll { $0 == widget }
                    }
                }
            }
        )
    }

    private var dashSection: some View {
        Section("ダッシュボード") {
            Toggle("天気ウィジェット", isOn: widgetBinding("weather"))
            Toggle("ミュージックウィジェット", isOn: widgetBinding("music"))
            Toggle("ToDoウィジェット", isOn: widgetBinding("todo"))
            Toggle("言葉ウィジェット", isOn: widgetBinding("phrase"))
        }
    }

    private var spotifySection: some View {
        Section {
            TextField("Client ID", text: Binding(
                get: { store.data.settings.spId },
                set: { value in store.updateSettings { $0.spId = value.trimmingCharacters(in: .whitespaces) } }
            ))
            .font(.system(.subheadline, design: .rounded))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        } header: {
            Text("Spotify連携")
        } footer: {
            Text("再生中の曲を表示するには、Spotifyの開発者ダッシュボードで、このアプリのリダイレクトURIに「kataomoi://callback」を追加してください。各人の曲のURLは「登録した人」から設定できます。")
        }
    }

    private var aiSection: some View {
        Section {
            TextField("APIキー", text: Binding(
                get: { store.data.settings.aiKey },
                set: { value in store.updateSettings { $0.aiKey = value.trimmingCharacters(in: .whitespaces) } }
            ))
            .font(.system(.subheadline, design: .rounded))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            Link("Google AI Studioで無料キーを取る", destination: URL(string: "https://aistudio.google.com/apikey")!)
                .font(.system(.subheadline, design: .rounded))
        } header: {
            Text("AI相談（Gemini）")
        } footer: {
            Text("「相談」タブの恋愛相談に使います。キーは無料で取得できます。相談の内容はGoogleのサーバーに送られるので、住所などの個人情報は書かないでください。")
        }
    }

    // Data

    private var dataSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("片思い \(store.data.persons.count)人 ／ 記録 \(store.data.entries.count)件 ／ 写真 \(store.data.entries.filter { $0.photo != nil }.count)枚")
                    .font(.system(.subheadline, design: .rounded))
                Text("サイズ 約\(store.dataSizeKB)KB ／ " + (store.lastBackupDate.map { "最後の書き出し \(DateKit.japanese($0))" } ?? "まだ書き出していません"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(store.theme.muted)
            }
            Button {
                do {
                    exportURL = try store.makeExportFile()
                } catch {
                    alertText = "書き出しに失敗しました"
                }
            } label: {
                Label("バックアップを書き出す", systemImage: "square.and.arrow.up")
            }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("書き出したファイルを共有", systemImage: "square.and.arrow.up.on.square")
                }
            }
            Button {
                showImporter = true
            } label: {
                Label("バックアップを読み込む", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("データ")
        } footer: {
            Text("データはこの端末の中にだけ保存されています。機種変更やアプリ削除に備えて、ときどき書き出しておくと安心です。")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let raw = try Data(contentsOf: url)
            let backup = try JSONDecoder().decode(BackupFile.self, from: raw)
            pendingBackup = backup
            showImportConfirm = true
        } catch {
            alertText = "片思いカレンダーのバックアップではありません"
        }
    }
}

struct PersonSettingsRow: View {
    @EnvironmentObject var store: CalendarStore
    let personID: String

    @State private var iconItem: PhotosPickerItem?
    @State private var showIconPicker = false
    @State private var songDraft: String?
    @State private var showMutualConfirm = false
    @State private var showEdit = false

    private var person: Person? { store.person(personID) }

    var body: some View {
        Group {
            if let person {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        PersonAvatar(person: person, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(store.theme.text)
                            if let mutual = person.mutual {
                                Text("両思いになった日 \(DateKit.japanese(mutual))")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(store.theme.muted)
                            }
                        }
                        Spacer()
                        Picker("関係", selection: Binding(
                            get: { person.rel ?? "片思い" },
                            set: { value in store.updatePerson(person.id) { $0.rel = value } }
                        )) {
                            ForEach(CalendarStore.relations, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }

                    HStack(spacing: 6) {
                        Text("カラー")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(store.theme.sub)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(CalendarStore.personColors, id: \.self) { c in
                                    Button {
                                        store.updatePerson(person.id) { $0.color = c }
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: c))
                                            .frame(width: 22, height: 22)
                                            .overlay(Circle().strokeBorder(Color.primary.opacity(person.color == c ? 0.6 : 0), lineWidth: 2))
                                    }
                                    .buttonStyle(.plain)
                                }
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: person.color) },
                                    set: { newColor in store.updatePerson(person.id) { $0.color = newColor.hexString } }
                                ), supportsOpacity: false)
                                .labelsHidden()
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            showIconPicker = true
                        } label: {
                            Text("アイコンを選ぶ")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(store.theme.petal, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        if person.icon != nil {
                            Button("アイコンを外す") {
                                store.updatePerson(person.id) { $0.icon = nil }
                            }
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .buttonStyle(.glass)
                        }
                        Button("編集") { showEdit = true }
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .buttonStyle(.glass)
                        if (person.rel ?? "片思い") == "片思い" {
                            Button("両思いになった") { showMutualConfirm = true }
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(store.theme.rose)
                                .buttonStyle(.glass)
                        }
                    }

                    TextField("Spotifyの曲・プレイリストのURL", text: Binding(
                        get: { songDraft ?? person.song ?? "" },
                        set: { songDraft = $0 }
                    ))
                    .font(.system(.subheadline, design: .rounded))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        let value = (songDraft ?? "").trimmingCharacters(in: .whitespaces)
                        store.updatePerson(person.id) { $0.song = value.isEmpty ? nil : value }
                    }

                    HStack {
                        Text("誕生日")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(store.theme.sub)
                        Spacer()
                        if person.birthday != nil {
                            DatePicker("", selection: Binding(
                                get: { DateKit.date(from: person.birthday ?? "") ?? Date() },
                                set: { newDate in store.updatePerson(person.id) { $0.birthday = DateKit.string(from: newDate) } }
                            ), displayedComponents: .date)
                            .labelsHidden()
                            Button("外す") {
                                store.updatePerson(person.id) { $0.birthday = nil }
                            }
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                        } else {
                            Button("設定する") {
                                store.updatePerson(person.id) { $0.birthday = DateKit.todayString() }
                            }
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .buttonStyle(.glass)
                        }
                    }
                }
                .padding(.vertical, 4)
                .onAppear { if songDraft == nil { songDraft = person.song ?? "" } }
                .photosPicker(isPresented: $showIconPicker, selection: $iconItem, matching: .images)
                .onChange(of: iconItem) { _, newItem in
                    Task { @MainActor in
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data),
                           let url = ImageData.dataURL(from: image, maxPixel: 240, square: true) {
                            store.updatePerson(person.id) { $0.icon = url }
                        }
                    }
                }
                .sheet(isPresented: $showEdit) {
                    PersonEditView(existing: person)
                        .environmentObject(store)
                }
                .confirmationDialog(
                    "両思いになりましたか？",
                    isPresented: $showMutualConfirm,
                    titleVisibility: .visible
                ) {
                    Button("両思いになった") { store.markMutual(person.id) }
                    Button("まだ", role: .cancel) {}
                } message: {
                    Text("\(person.name)との関係を「両思い」にします。")
                }
            }
        }
    }
}

// MARK: - Celebration

struct CelebrationView: View {
    @EnvironmentObject var store: CalendarStore
    let celebration: Celebration

    @State private var exploded = false
    @State private var fallen = false
    @State private var ringsOut = false
    @State private var shown = false
    @State private var pulse = false

    private let palette = ["#e8698a", "#f2a7c3", "#ff8fab", "#c9aaee", "#ffd36e", "#8ed8c0"]

    private var days: Int {
        let from = DateKit.date(from: celebration.person.since) ?? Date()
        let to = DateKit.date(from: celebration.person.mutual ?? DateKit.todayString()) ?? Date()
        return max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: from),
                                                      to: Calendar.current.startOfDay(for: to)).day ?? 0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                Circle()
                    .fill(store.theme.blush.opacity(0.5))
                    .frame(width: 300, height: 300)
                    .blur(radius: 70)
                    .offset(x: -110, y: -200)
                Circle()
                    .fill(store.theme.rose.opacity(0.4))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: 120, y: 220)

                fallingPieces(width: geo.size.width)
                burstPieces

                VStack(spacing: 12) {
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .strokeBorder(store.theme.rose.opacity(0.45), lineWidth: 2)
                                .frame(width: 96, height: 96)
                                .scaleEffect(ringsOut ? 2.1 : 0.55)
                                .opacity(ringsOut ? 0 : 0.55)
                                .animation(.easeOut(duration: 1.9).delay(Double(i) * 0.28), value: ringsOut)
                        }
                        Image(systemName: "heart.fill")
                            .font(.system(size: 66))
                            .foregroundStyle(store.theme.blush.opacity(0.6))
                            .blur(radius: 16)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 62))
                            .foregroundStyle(LinearGradient(colors: [Color(hex: "#ff8fab"), Color(hex: "#e8698a")],
                                                           startPoint: .top, endPoint: .bottom))
                            .scaleEffect(pulse ? 1.1 : 0.94)
                            .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: pulse)
                    }
                    .frame(height: 112)

                    Text("両思いおめでとう")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(store.theme.deep)
                    Text("\(celebration.person.name)への想いが届きました\n片思いの期間は \(days)日")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(store.theme.sub)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            Image(systemName: "heart.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(store.theme.blush)
                        }
                    }
                    Button("とじる") {
                        store.celebration = nil
                    }
                    .buttonStyle(.glassProminent)
                    .tint(store.theme.rose)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .padding(.top, 4)
                }
                .padding(28)
                .frame(maxWidth: 330)
                .cardStyle(cornerRadius: 30)
                .padding(.horizontal, 24)
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
            }
        }
        .onAppear {
            exploded = true
            fallen = true
            pulse = true
            ringsOut = true
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { shown = true }
        }
    }

    private var burstPieces: some View {
        ZStack {
            ForEach(0..<34, id: \.self) { i in
                let angle = Double(i) * 137.5 * Double.pi / 180
                let radius = 110 + Double((i * 37) % 150)
                let dx = cos(angle) * radius
                let dy = sin(angle) * radius - 40
                pieceShape(i: i)
                    .offset(x: exploded ? dx : 0, y: exploded ? dy + 240 : 0)
                    .opacity(exploded ? 0 : 1)
                    .animation(.easeOut(duration: 1.9).delay(Double(i) * 0.012), value: exploded)
            }
        }
    }

    private func fallingPieces(width: CGFloat) -> some View {
        ZStack {
            ForEach(0..<22, id: \.self) { i in
                let span = max(Int(width) - 24, 1)
                let x = CGFloat((i * 83) % span) - width / 2 + 12
                let delay = Double(i % 11) * 0.16
                let duration = 2.4 + Double(i % 5) * 0.35
                pieceShape(i: i)
                    .rotationEffect(.degrees(fallen ? Double((i * 71) % 260) - 130 : 0))
                    .offset(x: x, y: fallen ? 560 : -500)
                    .animation(.easeIn(duration: duration).delay(delay), value: fallen)
            }
        }
    }

    private func pieceShape(i: Int) -> some View {
        let color = Color(hex: palette[i % palette.count])
        let size = CGFloat(9 + (i % 4) * 3)
        return Group {
            if store.data.settings.style == "heart" || i % 3 == 0 {
                Image(systemName: "heart.fill")
                    .font(.system(size: size))
                    .foregroundStyle(color)
            } else if i % 3 == 1 {
                Image(systemName: "star.fill")
                    .font(.system(size: size))
                    .foregroundStyle(color)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: size, height: size * 0.55)
                    .rotationEffect(.degrees(Double((i * 53) % 360)))
            }
        }
    }
}

// MARK: - AI love advice (Gemini free tier)

struct AdviceMessage: Identifiable {
    let id = UUID()
    var role: String
    var text: String
}

struct AdviceView: View {
    @EnvironmentObject var store: CalendarStore
    @State private var messages: [AdviceMessage] = []
    @State private var input = ""
    @State private var sending = false
    @State private var errorText: String?
    @State private var keyDraft = ""

    private var apiKey: String { store.data.settings.aiKey }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if apiKey.isEmpty {
                    setupView
                } else {
                    messageList
                    if let errorText {
                        Text(errorText)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    inputBar
                }
            }
            .background(store.theme.cream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("AI恋愛相談")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(store.theme.text)
                Text("GoogleのGemini（無料枠）を使って、登録した人の情報を踏まえた恋愛相談ができます。まず無料のAPIキーを入れてください。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.sub)
                Link("Google AI Studioで無料キーを取る", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                TextField("APIキーを貼り付け", text: $keyDraft)
                    .font(.system(.subheadline, design: .rounded))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(store.theme.card, in: RoundedRectangle(cornerRadius: 10))
                Button("保存") {
                    store.updateSettings { $0.aiKey = keyDraft.trimmingCharacters(in: .whitespaces) }
                }
                .buttonStyle(.glass)
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("相談の内容はGoogleのサーバーに送られます。住所などの個人情報は書かないでください。キーは設定タブからも変更できます。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(store.theme.muted)
            }
            .padding(16)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if messages.isEmpty {
                        bubble(role: "model", text: greetingText)
                    }
                    ForEach(messages) { message in
                        bubble(role: message.role, text: message.text)
                            .id(message.id)
                    }
                    if sending {
                        HStack {
                            Text("考え中…")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(store.theme.muted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(store.theme.card, in: RoundedRectangle(cornerRadius: 14))
                            Spacer()
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var greetingText: String {
        if let person = store.data.persons.first {
            return "こんにちは。\(person.name)のこと、片思い中のもやもや、なんでも話してね。最近の記録も踏まえて一緒に考えるよ。"
        }
        return "こんにちは。恋愛のこと、なんでも話してね。"
    }

    private func bubble(role: String, text: String) -> some View {
        HStack {
            if role == "user" { Spacer(minLength: 40) }
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(role == "user" ? Color.white : store.theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(role == "user" ? store.theme.deep : store.theme.card, in: RoundedRectangle(cornerRadius: 16))
            if role != "user" { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("相談してみる", text: $input, axis: .vertical)
                .font(.system(.subheadline, design: .rounded))
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(store.theme.card, in: RoundedRectangle(cornerRadius: 18))
            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(store.theme.deep, in: Circle())
            }
            .disabled(sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !messages.isEmpty {
                Button {
                    messages = []
                    errorText = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(store.theme.muted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        input = ""
        errorText = nil
        messages.append(AdviceMessage(role: "user", text: text))
        sending = true
        let history = messages
        let key = apiKey
        let system = systemPrompt()
        Task {
            do {
                let reply = try await GeminiClient.send(apiKey: key, system: system, history: history)
                messages.append(AdviceMessage(role: "model", text: reply))
            } catch {
                errorText = "送信できませんでした: \(error.localizedDescription)"
            }
            sending = false
        }
    }

    private func systemPrompt() -> String {
        var context = "相手はまだ登録されていません。一般的な恋愛相談として乗ってください。"
        if let person = store.data.persons.first {
            var lines = [
                "相手の名前: \(person.name)",
                "好きになってから: \(DateKit.daysSince(person.since))日",
                "関係: \(person.rel ?? "片思い")"
            ]
            let es = store.entries(for: person.id)
            if let last = es.last { lines.append("最新の好き度（100点満点）: \(last.like)") }
            let diaries = es.suffix(3).map { $0.text }.filter { !$0.isEmpty }
            if !diaries.isEmpty { lines.append("最近の日記: " + diaries.joined(separator: " / ")) }
            for field in person.fields where !field.value.isEmpty {
                lines.append("\(field.label): \(field.value)")
            }
            if let b = person.birthday { lines.append("相手の誕生日: \(b)") }
            context = lines.joined(separator: "\n")
        }
        return """
        あなたは恋愛相談に乗る、やさしくて聞き上手な相談相手です。ユーザーの気持ちをまず受け止めて、決めつけずに一緒に考えてください。相手の気持ちを断定しないでください。返事は長くしすぎず、会話のキャッチボールを大切にしてください。日本語で、やわらかい口調で話してください。

        【ユーザーの状況】
        \(context)
        """
    }
}

enum GeminiClient {
    static func send(apiKey: String, system: String, history: [AdviceMessage]) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let contents: [[String: Any]] = history.map { ["role": $0.role, "parts": [["text": $0.text]]] }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": contents,
            "generationConfig": ["temperature": 0.85, "maxOutputTokens": 1200]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let candidates = obj?["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.compactMap({ $0["text"] as? String }).first, !text.isEmpty {
            return text
        }
        if let err = obj?["error"] as? [String: Any], let msg = err["message"] as? String {
            throw NSError(domain: "Gemini", code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        throw NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: "応答を読み取れませんでした"])
    }
}
