import UIKit
import SwiftUI
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
    var mileDone: Int?

    init(id: String, name: String, since: String, met: String? = nil, color: String,
         rel: String? = "片思い", icon: String? = nil, song: String? = nil,
         mutual: String? = nil, mileDone: Int? = nil) {
        self.id = id; self.name = name; self.since = since; self.met = met
        self.color = color; self.rel = rel; self.icon = icon; self.song = song
        self.mutual = mutual; self.mileDone = mileDone
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, since, met, color, rel, icon, song, mutual, mileDone
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
        mileDone = try c.decodeIfPresent(Int.self, forKey: .mileDone)
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
    var tabNames: [String: String] = [:]
    var tabsShow: [String: Bool] = [:]
    var mileEvent: Bool = true

    private enum CodingKeys: String, CodingKey {
        case icons, celebrate, style, dash, widgets, spId, tabNames, tabsShow, mileEvent
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
        tabNames = try c.decodeIfPresent([String: String].self, forKey: .tabNames) ?? [:]
        tabsShow = try c.decodeIfPresent([String: Bool].self, forKey: .tabsShow) ?? [:]
        mileEvent = try c.decodeIfPresent(Bool.self, forKey: .mileEvent) ?? true
    }
}

struct CalendarData: Codable {
    var persons: [Person] = []
    var entries: [Entry] = []
    var settings: AppSettings = AppSettings()

    private enum CodingKeys: String, CodingKey { case persons, entries, settings }

    init(persons: [Person] = [], entries: [Entry] = [], settings: AppSettings = AppSettings()) {
        self.persons = persons; self.entries = entries; self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        persons = try c.decodeIfPresent([Person].self, forKey: .persons) ?? []
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
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
}

// MARK: - Themes

enum AppThemeKey: String, CaseIterable, Identifiable {
    case pink, lavender, mint, peach, sky, white
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pink: return "ピンク"
        case .lavender: return "ラベンダー"
        case .mint: return "ミント"
        case .peach: return "ピーチ"
        case .sky: return "スカイ"
        case .white: return "ホワイト"
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
        case .white:
            return AppTheme(key: key, rose: Color(hex: "#1c1c1e"), deep: Color(hex: "#000000"),
                            blush: Color(hex: "#d1d1d6"), petal: Color(hex: "#f2f2f7"),
                            cream: Color.white, card: Color.white.opacity(0.96),
                            text: Color(hex: "#1c1c1e"), sub: Color(hex: "#5c5c60"), muted: Color(hex: "#8e8e93"))
        }
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
    @Published var celebration: Celebration?
    @Published var milestoneText: String?
    @Published var calendarPersonID: String?
    @Published var pendingDay: String?

    static let personColors = ["#e8698a", "#9b6fd4", "#3daa88", "#e88a50", "#4a9fd4",
                               "#c0496d", "#7b5ea7", "#2d8a68", "#b06030", "#1860a0"]
    static let relations = ["片思い", "気になる", "友達", "両思い", "恋人", "推し"]
    static let milestones = [100, 200, 300, 365, 500, 730, 1000, 1095, 1500, 2000, 3000]

    var theme: AppTheme { AppTheme.of(themeKey) }

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
        calendarPersonID = loaded.persons.first?.id
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: fileURL, options: [.atomic])
        }
        UserDefaults.standard.set(themeKey.rawValue, forKey: "kataomoi-theme")
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

    func addPerson(name: String, since: String, met: String?, color: String, rel: String, icon: String?) {
        let p = Person(id: String(Int(Date().timeIntervalSince1970 * 1000)),
                       name: name, since: since, met: met, color: color, rel: rel, icon: icon)
        data.persons.append(p)
        calendarPersonID = p.id
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

    static func reachedMilestone(_ days: Int) -> Int {
        var best = milestones.filter { $0 <= days }.max() ?? 0
        let years = (days / 365) * 365
        if years > best { best = years }
        return best
    }

    static func milestoneLabel(_ m: Int) -> String {
        m % 365 == 0 && m > 0 ? "\(m / 365)年" : "\(m)日"
    }

    static func nextMilestoneText(_ days: Int) -> String {
        var next = milestones.first(where: { $0 > days })
        if next == nil { next = (days / 365 + 1) * 365 }
        guard let n = next else { return "" }
        return "\(milestoneLabel(n))まであと\(n - days)日"
    }

    func checkMilestones() {
        var events: [String] = []
        var changed = false
        for i in data.persons.indices {
            let reached = Self.reachedMilestone(DateKit.daysSince(data.persons[i].since))
            if data.persons[i].mileDone == nil {
                data.persons[i].mileDone = reached
                changed = true
            } else if reached > (data.persons[i].mileDone ?? 0) {
                data.persons[i].mileDone = reached
                changed = true
                if data.settings.mileEvent {
                    events.append("\(data.persons[i].name)さん \(Self.milestoneLabel(reached))")
                }
            }
        }
        if changed { save() }
        if !events.isEmpty {
            milestoneText = "好きになってから " + events.joined(separator: "、") + " になりました。"
        }
    }

    func makeExportFile() throws -> URL {
        let backup = BackupFile(app: "crush-calendar", version: 1,
                                exportedAt: ISO8601DateFormatter().string(from: Date()),
                                theme: themeKey.rawValue,
                                persons: data.persons, entries: data.entries,
                                settings: data.settings)
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
                                settings: backup.settings ?? AppSettings())
            if let t = backup.theme, let key = AppThemeKey(rawValue: t) { themeKey = key }
            calendarPersonID = data.persons.first?.id
        } else {
            let personIDs = Set(data.persons.map { $0.id })
            let entryIDs = Set(data.entries.map { $0.id })
            data.persons.append(contentsOf: backup.persons.filter { !personIDs.contains($0.id) })
            data.entries.append(contentsOf: backup.entries.filter { !entryIDs.contains($0.id) })
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
        TabDef(key: "dash", title: "ウィジェット", icon: "square.grid.2x2.fill")
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
        .task { store.checkMilestones() }
        .alert("記念日おめでとう", isPresented: Binding(
            get: { store.milestoneText != nil },
            set: { if !$0 { store.milestoneText = nil } }
        )) {
            Button("ありがとう") { store.milestoneText = nil }
        } message: {
            Text(store.milestoneText ?? "")
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
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
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

                    Button {
                        showAdd = true
                    } label: {
                        Text("＋ 新しい片思いを追加する")
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
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .background(store.theme.cream.ignoresSafeArea())
            .navigationTitle("片思いカレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAdd) {
                AddPersonView()
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
                Text(mutualTarget.map { "\($0.name)さんとの関係を「両思い」にします。" } ?? "")
            }
        }
    }

    private func personCard(_ person: Person) -> some View {
        let entries = store.entries(for: person.id)
        let lastLike = entries.last?.like
        let days = DateKit.daysSince(person.since)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PersonAvatar(person: person, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(person.name)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(store.theme.text)
                            .lineLimit(1)
                        Text(person.rel ?? "片思い")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(store.theme.rose)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(store.theme.petal, in: Capsule())
                    }
                    Text("\(DateKit.japanese(person.since))から")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(store.theme.muted)
                }
                Spacer()
                Button {
                    deleteTarget = person
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(store.theme.muted)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("削除")
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(days)")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(store.theme.deep)
                    Text("日間")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(store.theme.sub)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("最新の好き度: \(lastLike.map { "\($0)/100" } ?? "—")")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(store.theme.muted)
                    Text(CalendarStore.nextMilestoneText(days))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(store.theme.muted)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    store.calendarPersonID = person.id
                    store.pendingDay = DateKit.todayString()
                    goCalendar()
                } label: {
                    Text("今日を記録")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(hex: person.color), in: Capsule())
                }
                .buttonStyle(.plain)

                if (person.rel ?? "片思い") == "片思い" {
                    Button {
                        mutualTarget = person
                    } label: {
                        Text("両思いになった")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(store.theme.rose)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().strokeBorder(store.theme.rose, lineWidth: 1.4)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .cardStyle()
        .contentShape(Rectangle())
        .onTapGesture {
            store.calendarPersonID = person.id
            goCalendar()
        }
    }

}

// MARK: - Add person

struct AddPersonView: View {
    @EnvironmentObject var store: CalendarStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var since = Date()
    @State private var hasMet = false
    @State private var met = Date()
    @State private var rel = "片思い"
    @State private var color = CalendarStore.personColors[0]
    @State private var iconItem: PhotosPickerItem?
    @State private var iconDataURL: String?
    @State private var alertText: String?

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
                }
                Section("アイコン（任意）") {
                    HStack(spacing: 12) {
                        if let image = ImageData.uiImage(from: iconDataURL) {
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        }
                        PhotosPicker(selection: $iconItem, matching: .images) {
                            Text(iconDataURL == nil ? "写真を選ぶ" : "写真を変更")
                        }
                        if iconDataURL != nil {
                            Button("外す", role: .destructive) { iconDataURL = nil; iconItem = nil }
                        }
                    }
                }
            }
            .fontDesign(.rounded)
            .navigationTitle("新しい片思いを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加する") { save() }
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
        store.addPerson(name: trimmed,
                        since: DateKit.string(from: since),
                        met: hasMet ? DateKit.string(from: met) : nil,
                        color: color, rel: rel, icon: iconDataURL)
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
    @State private var dayRequest: DayRequest?

    private var person: Person? {
        store.person(selectedPersonID ?? store.calendarPersonID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if store.data.persons.isEmpty {
                        EmptyState(message: "先に片思い中の人を追加してね")
                    } else {
                        personPicker
                        if let person, let songURL = spotifyEmbedURL(person.song) {
                            SpotifySongCard(url: songURL)
                        }
                        monthHeader
                        calendarGrid
                        legend
                        monthSummary
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(store.theme.cream.ignoresSafeArea())
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
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
        return HStack(spacing: 10) {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("前月")

            Text("\(comps.year ?? 0)年 \(comps.month ?? 1)月")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(store.theme.text)
                .frame(maxWidth: .infinity)

            Button("今日") { goToday() }
                .buttonStyle(.glass)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("次月")
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: monthDate) {
            monthDate = next
        }
    }

    private func goToday() {
        monthDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
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

        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(["日", "月", "火", "水", "木", "金", "土"].enumerated()), id: \.offset) { i, d in
                    Text(d)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(i == 0 ? Color(hex: "#e05575") : i == 6 ? Color(hex: "#4a7fd4") : store.theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<blanks, id: \.self) { _ in
                    Color.clear.frame(height: 62)
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
        let last = entries.last
        let isToday = ds == today
        return Button {
            dayRequest = DayRequest(date: ds)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text("\(day)")
                        .font(.system(.caption, design: .rounded).weight(isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? store.theme.rose : store.theme.text)
                    if let person {
                        if person.met == ds {
                            mark("会", color: Color(hex: person.color))
                        } else if person.since == ds {
                            mark("好", color: store.theme.blush)
                        }
                        if person.mutual == ds {
                            mark("両", color: Color(hex: "#e8698a"))
                        }
                    }
                    Spacer()
                }
                if let photo = last?.photo, let image = ImageData.uiImage(from: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 30)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else if let last {
                    if !last.mood.isEmpty {
                        Text(last.mood)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(store.theme.sub)
                            .lineLimit(1)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(store.theme.petal)
                            Capsule()
                                .fill(store.theme.rose)
                                .frame(width: geo.size.width * CGFloat(min(max(last.like, 0), 100)) / 100)
                        }
                    }
                    .frame(height: 3)
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(height: 62)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isToday ? store.theme.petal : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isToday ? store.theme.rose : Color.clear, lineWidth: 1.4)
            )
        }
        .buttonStyle(.plain)
    }

    private func mark(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 13, height: 13)
            .background(color, in: Circle())
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: store.theme.rose, text: "記録あり")
            if let person {
                legendItem(color: store.theme.blush, text: "好きになった日")
                if person.met != nil {
                    legendItem(color: Color(hex: person.color), text: "出会った日")
                }
            }
            Spacer()
        }
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(store.theme.muted)
        .padding(.horizontal, 4)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }

    private var monthSummary: some View {
        let comps = Calendar.current.dateComponents([.year, .month], from: monthDate)
        let prefix = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        let monthEntries = person.map { p in store.data.entries.filter { $0.personId == p.id && $0.date.hasPrefix(prefix) } } ?? []
        let recordedDays = Set(monthEntries.map { $0.date }).count
        let photos = monthEntries.filter { $0.photo != nil }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                summaryStat(value: "\(recordedDays)", label: "記録した日")
                Divider().frame(height: 30)
                summaryStat(value: "\(monthEntries.count)", label: "記録の数")
                Divider().frame(height: 30)
                summaryStat(value: "\(photos.count)", label: "写真")
            }
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { entry in
                            if let image = ImageData.uiImage(from: entry.photo) {
                                Button {
                                    dayRequest = DayRequest(date: entry.date)
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 84, height: 84)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func summaryStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(store.theme.deep)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(store.theme.muted)
        }
        .frame(maxWidth: .infinity)
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
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("写真を選ぶ", systemImage: "photo")
                        }
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
            .navigationTitle("統計")
            .navigationBarTitleDisplayMode(.inline)
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

            Text("連続記録 \(store.streak(for: person.id))日 ／ \(CalendarStore.nextMilestoneText(DateKit.daysSince(person.since)))")
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

    private var widgets: [String] { store.data.settings.widgets }
    private var missing: [String] {
        ["weather", "music"].filter { !widgets.contains($0) }
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
                    if !missing.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(missing, id: \.self) { widget in
                                Button {
                                    store.updateSettings { $0.widgets.append(widget) }
                                } label: {
                                    Text("＋ \(widget == "weather" ? "天気" : "ミュージック")")
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
            .navigationTitle("ウィジェット")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func widgetCard(_ widget: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(widget == "weather" ? "天気" : "ミュージック")
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
            } else {
                MusicWidget(goSettings: goSettings)
            }
        }
        .padding(16)
        .cardStyle()
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
        let precipitation_probability_max: [Double?]
    }
    let current: Current
    let daily: Daily
}

@MainActor
final class WeatherModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var response: WeatherResponse?
    @Published var place = ""
    @Published var failed = false

    private let manager = CLLocationManager()
    private var started = false
    private var usedFallback = false
    private var fallbackWork: DispatchWorkItem?

    static let labels: [Int: String] = [
        0: "快晴", 1: "晴れ", 2: "晴れ時々くもり", 3: "くもり", 45: "霧", 48: "霧",
        51: "小雨", 53: "霧雨", 55: "霧雨", 61: "雨", 63: "雨", 65: "強い雨",
        71: "雪", 73: "雪", 75: "大雪", 77: "雪", 80: "にわか雨", 81: "にわか雨",
        82: "激しいにわか雨", 85: "にわか雪", 86: "にわか雪", 95: "雷雨", 96: "雷雨", 99: "雷雨"
    ]

    func loadIfNeeded() {
        if started { return }
        started = true
        manager.delegate = self
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            scheduleFallback()
        case .denied, .restricted:
            fallback()
        default:
            manager.requestLocation()
            scheduleFallback()
        }
    }

    func reload() {
        response = nil
        failed = false
        usedFallback = false
        started = true
        manager.delegate = self
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            scheduleFallback()
        case .denied, .restricted:
            fallback()
        default:
            manager.requestLocation()
            scheduleFallback()
        }
    }

    private func scheduleFallback() {
        fallbackWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.response == nil else { return }
                self.fallback()
            }
        }
        fallbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        fallbackWork?.cancel()
        guard let loc = locations.last else { return }
        Task { await fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, place: "現在地") }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // While the permission prompt is still up, errors can arrive early;
        // the authorization callback and the timeout fallback cover that case.
        if manager.authorizationStatus != .notDetermined {
            fallback()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            fallback()
        default:
            break
        }
    }

    private func fallback() {
        if usedFallback { return }
        usedFallback = true
        Task { await fetch(lat: 35.68, lon: 139.76, place: "東京（位置情報なし）") }
    }

    private func fetch(lat: Double, lon: Double, place: String) async {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(String(format: "%.2f", lat))&longitude=\(String(format: "%.2f", lon))&current=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=5"
        guard let url = URL(string: urlString) else { failed = true; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            response = try JSONDecoder().decode(WeatherResponse.self, from: data)
            self.place = place
            failed = false
        } catch {
            failed = true
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
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
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
                            Text(WeatherModel.labels[r.daily.weather_code[i]] ?? "—")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(store.theme.text)
                            Spacer()
                            Text("降水 " + (r.daily.precipitation_probability_max[i].map { "\(Int($0))%" } ?? "—"))
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
                    Button("更新") { model.reload() }
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .buttonStyle(.glass)
                        .padding(.top, 4)
                }
            } else if model.failed {
                VStack(alignment: .leading, spacing: 10) {
                    Text("天気を取得できませんでした。")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(store.theme.sub)
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
    }

    private func weekdayLabel(_ day: String) -> String {
        guard let date = DateKit.date(from: day) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "E"
        return f.string(from: date)
    }
}

struct MusicWidget: View {
    @EnvironmentObject var store: CalendarStore
    let goSettings: () -> Void

    var body: some View {
        let withSongs = store.data.persons.filter { ($0.song ?? "").isEmpty == false }
        VStack(alignment: .leading, spacing: 10) {
            if store.data.settings.spId.isEmpty && withSongs.isEmpty {
                Text("設定でSpotifyのClient IDを入れるか、各人に曲のURLを設定すると、ここから開けます。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.sub)
                    .lineSpacing(4)
                Button("設定を開く") { goSettings() }
                    .buttonStyle(.glass)
            } else if withSongs.isEmpty {
                Text("曲が設定されている人がいません。設定の「登録した人」からSpotifyのURLを入れられます。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.sub)
                    .lineSpacing(4)
            } else {
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
                dataSection
            }
            .fontDesign(.rounded)
            .scrollContentBackground(.hidden)
            .background(store.theme.cream.ignoresSafeArea())
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
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
                    let t = AppTheme.of(key)
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
        }
    }

    // Display

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
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
            Toggle("記念日のお祝い（100日・200日・1年など）", isOn: boolBinding(\.mileEvent))
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
            Text("各人の曲のURLは「登録した人」から設定でき、カレンダーとウィジェットからSpotifyで開けます。")
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
    @State private var songDraft: String?
    @State private var showMutualConfirm = false

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

                    HStack(spacing: 8) {
                        PhotosPicker(selection: $iconItem, matching: .images) {
                            Text("アイコンを選ぶ")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(store.theme.petal, in: Capsule())
                        }
                        if person.icon != nil {
                            Button("アイコンを外す") {
                                store.updatePerson(person.id) { $0.icon = nil }
                            }
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .buttonStyle(.glass)
                        }
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
                }
                .padding(.vertical, 4)
                .onAppear { if songDraft == nil { songDraft = person.song ?? "" } }
                .onChange(of: iconItem) { _, newItem in
                    Task { @MainActor in
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data),
                           let url = ImageData.dataURL(from: image, maxPixel: 240, square: true) {
                            store.updatePerson(person.id) { $0.icon = url }
                        }
                    }
                }
                .confirmationDialog(
                    "両思いになりましたか？",
                    isPresented: $showMutualConfirm,
                    titleVisibility: .visible
                ) {
                    Button("両思いになった") { store.markMutual(person.id) }
                    Button("まだ", role: .cancel) {}
                } message: {
                    Text("\(person.name)さんとの関係を「両思い」にします。")
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
    @State private var pulse = false

    private let palette = ["#e8698a", "#f2a7c3", "#ff8fab", "#c9aaee", "#ffd36e", "#8ed8c0"]

    private var days: Int {
        let from = DateKit.date(from: celebration.person.since) ?? Date()
        let to = DateKit.date(from: celebration.person.mutual ?? DateKit.todayString()) ?? Date()
        return max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: from),
                                                      to: Calendar.current.startOfDay(for: to)).day ?? 0)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            pieces

            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(Color(hex: "#e8698a"))
                    .scaleEffect(pulse ? 1.1 : 0.94)
                    .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: pulse)
                Text("両思いおめでとう")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(store.theme.deep)
                Text("\(celebration.person.name)さんへの想いが届きました\n片思いの期間は \(days)日")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.theme.sub)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                Button("とじる") {
                    store.celebration = nil
                }
                .buttonStyle(.glassProminent)
                .tint(store.theme.rose)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 320)
            .cardStyle(cornerRadius: 28)
            .padding(.horizontal, 24)
        }
        .onAppear {
            exploded = true
            pulse = true
        }
    }

    private var pieces: some View {
        ZStack {
            ForEach(0..<26, id: \.self) { i in
                let angle = Double(i) * 137.5 * Double.pi / 180
                let radius = 100 + Double((i * 37) % 130)
                let dx = cos(angle) * radius
                let dy = sin(angle) * radius - 40
                piece(i: i)
                    .offset(x: exploded ? dx : 0, y: exploded ? dy + 230 : 0)
                    .opacity(exploded ? 0 : 1)
                    .animation(.easeOut(duration: 1.7).delay(Double(i) * 0.014), value: exploded)
            }
        }
    }

    private func piece(i: Int) -> some View {
        let color = Color(hex: palette[i % palette.count])
        let size = CGFloat(9 + (i % 4) * 3)
        return Group {
            if store.data.settings.style == "heart" {
                Image(systemName: "heart.fill")
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
