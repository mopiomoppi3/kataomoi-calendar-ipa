import WidgetKit
import SwiftUI
import ActivityKit

@main
struct KataomoiWidgetBundle: WidgetBundle {
    var body: some Widget {
        DaysWidget()
        DaysLiveActivity()
    }
}

// MARK: - Timeline

struct DaysEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct DaysProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaysEntry {
        DaysEntry(date: Date(), snapshot: sampleSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (DaysEntry) -> Void) {
        completion(DaysEntry(date: Date(), snapshot: context.isPreview ? sampleSnapshot() : loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DaysEntry>) -> Void) {
        let now = Date()
        let snapshot = loadSnapshot()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 3600)
        let entries = [
            DaysEntry(date: now, snapshot: snapshot),
            DaysEntry(date: midnight, snapshot: snapshot)
        ]
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func loadSnapshot() -> WidgetSnapshot {
        guard let url = SharedStore.fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return WidgetSnapshot() }
        return snapshot
    }

    private func sampleSnapshot() -> WidgetSnapshot {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let since = f.string(from: Calendar.current.date(byAdding: .day, value: -502, to: Date()) ?? Date())
        return WidgetSnapshot(
            persons: [.init(name: "佐久間", since: since, color: "#4a9fd4", rel: "片思い", birthday: nil)],
            todos: [.init(text: "今日の記録をつける", done: false),
                    .init(text: "プレゼントを考える", done: false)],
            updatedAt: ""
        )
    }
}

// MARK: - Widget

struct DaysWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaysWidget", provider: DaysProvider()) { entry in
            DaysWidgetView(entry: entry)
        }
        .configurationDisplayName("恋ログ")
        .description("好きになってからの日数と記念日、ToDoを表示します")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DaysWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DaysEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var person: WidgetSnapshot.Person? { snapshot.persons.first }
    private var days: Int {
        person.map { WidgetDateKit.daysSince($0.since, on: entry.date) } ?? 0
    }
    private var openTodos: [WidgetSnapshot.Todo] { snapshot.todos.filter { !$0.done } }

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        case .accessoryInline:
            accessoryInline
        default:
            systemView
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 1.0, green: 0.96, blue: 0.97),
                                            Color(red: 0.87, green: 0.93, blue: 1.0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
    }

    // System families (Home Screen / StandBy)

    private var systemView: some View {
        Group {
            if let person {
                switch family {
                case .systemMedium:
                    mediumContent(person)
                case .systemLarge:
                    largeContent(person)
                default:
                    smallContent(person)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.pink)
                    Text("アプリで人を登録してね")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func smallContent(_ person: WidgetSnapshot.Person) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(colorFromHex(person.color))
                Text("\(person.name)さん")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(days)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(colorFromHex(person.color))
                Text("日間")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(WidgetMilestones.nextText(days))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let b = WidgetMilestones.birthdayText(person.birthday, on: entry.date) {
                Text(b)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(colorFromHex(person.color))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func mediumContent(_ person: WidgetSnapshot.Person) -> some View {
        HStack(alignment: .top, spacing: 14) {
            smallContent(person)
            if !openTodos.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("ToDo")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(openTodos.prefix(3).enumerated()), id: \.offset) { _, todo in
                        HStack(spacing: 4) {
                            Image(systemName: "circle")
                                .font(.system(size: 8))
                            Text(todo.text)
                                .font(.system(.caption, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func largeContent(_ person: WidgetSnapshot.Person) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(snapshot.persons.prefix(3).enumerated()), id: \.offset) { _, p in
                let d = WidgetDateKit.daysSince(p.since, on: entry.date)
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(colorFromHex(p.color))
                    Text("\(p.name)さん")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(d)日間")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(colorFromHex(p.color))
                    Text(WidgetMilestones.nextText(d))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !openTodos.isEmpty {
                Divider()
                Text("ToDo")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
                ForEach(Array(openTodos.prefix(4).enumerated()), id: \.offset) { _, todo in
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.system(size: 9))
                        Text(todo.text)
                            .font(.system(.subheadline, design: .rounded))
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // Accessory families (Lock Screen)

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(days)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("日間")
                    .font(.system(size: 8, design: .rounded))
            }
        }
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let person {
                Text("\(person.name)さん \(days)日間")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                Text(WidgetMilestones.nextText(days))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("恋ログ")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessoryInline: some View {
        Group {
            if let person {
                Text("\(person.name)さん あと\(WidgetMilestones.nextText(days).components(separatedBy: "あと").last ?? "")")
            } else {
                Text("恋ログ")
            }
        }
    }
}

// MARK: - Live Activity

struct DaysLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DaysActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(colorFromHex(context.attributes.colorHex))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.attributes.personName)さん")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                    Text(context.state.milestoneText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(context.state.days)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(colorFromHex(context.attributes.colorHex))
                    Text("日間")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 1.0, green: 0.97, blue: 0.98))
            .activitySystemActionForegroundColor(Color.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(colorFromHex(context.attributes.colorHex))
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.days)日間")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(colorFromHex(context.attributes.colorHex))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.personName)さん ・ \(context.state.milestoneText)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(colorFromHex(context.attributes.colorHex))
            } compactTrailing: {
                Text("\(context.state.days)日")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(colorFromHex(context.attributes.colorHex))
            } minimal: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(colorFromHex(context.attributes.colorHex))
            }
        }
    }
}
