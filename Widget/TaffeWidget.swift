import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Données

struct PuffEntry: TimelineEntry {
    let date: Date
    let today: Int
    let yesterday: Int
    let limit: Int
    let week: [DayCount]
    let theme: TaffeTheme

    static var sample: PuffEntry {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let values = [42, 37, 51, 29, 33, 40, 18]
        var week: [DayCount] = []
        for (index, value) in values.enumerated() {
            let offset = values.count - 1 - index
            let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) ?? now
            week.append(DayCount(day: day, count: value))
        }
        return PuffEntry(date: now, today: 18, yesterday: 40, limit: 50, week: week, theme: .neon)
    }
}

struct PuffProvider: TimelineProvider {
    func placeholder(in context: Context) -> PuffEntry {
        PuffEntry.sample
    }

    func getSnapshot(in context: Context, completion: @escaping (PuffEntry) -> Void) {
        completion(context.isPreview ? PuffEntry.sample : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PuffEntry>) -> Void) {
        let entry = makeEntry()
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(3600)
        let refresh = min(tomorrow, now.addingTimeInterval(15 * 60))
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> PuffEntry {
        let puffs = PuffStore.load()
        let now = Date()
        let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        return PuffEntry(
            date: now,
            today: PuffStore.count(in: puffs, on: now),
            yesterday: PuffStore.count(in: puffs, on: yesterdayDate),
            limit: PuffStore.dailyLimit,
            week: PuffStore.dailyCounts(in: puffs, days: 7, endingOn: now),
            theme: TaffeTheme.current
        )
    }
}

// MARK: - Vues

struct TaffeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PuffEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isAccessory {
                    Color.clear
                } else {
                    LinearGradient(colors: [entry.theme.background, entry.theme.surface],
                                   startPoint: .top,
                                   endPoint: .bottom)
                }
            }
    }

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            MediumTaffeView(entry: entry)
        case .accessoryCircular:
            CircularTaffeView(entry: entry)
        case .accessoryRectangular:
            RectangularTaffeView(entry: entry)
        case .accessoryInline:
            Text("\(entry.today) taffes aujourd'hui")
        default:
            SmallTaffeView(entry: entry)
        }
    }
}

struct AddPuffButton: View {
    let theme: TaffeTheme

    var body: some View {
        Button(intent: AddPuffIntent()) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(theme.background)
                .frame(width: 28, height: 28)
                .background(CutCornerShape(cut: 7).fill(theme.primary))
        }
        .buttonStyle(.plain)
    }
}

struct WidgetLimitBar: View {
    let today: Int
    let limit: Int
    let theme: TaffeTheme

    var body: some View {
        let ratio = CGFloat(min(Double(today) / Double(max(limit, 1)), 1))
        let color = today >= limit ? theme.alert : theme.primary
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(color.opacity(0.18))
                    Rectangle().fill(color).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 5)
            Text("\(today)/\(limit)")
                .font(.mono(9, .bold))
                .foregroundStyle(color)
        }
    }
}

struct SmallTaffeView: View {
    let entry: PuffEntry

    var body: some View {
        let theme = entry.theme
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text("// TAFFE")
                    .font(.mono(11, .bold))
                    .foregroundStyle(theme.primary)
                Spacer()
                AddPuffButton(theme: theme)
            }
            Spacer(minLength: 0)
            Text("\(entry.today)")
                .font(.system(size: 50, weight: .black, design: .monospaced))
                .foregroundStyle(theme.text)
                .shadow(color: theme.primary.opacity(0.8), radius: 8)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("AUJOURD'HUI")
                .font(.mono(9, .semibold))
                .foregroundStyle(theme.dim)
            if entry.limit > 0 {
                WidgetLimitBar(today: entry.today, limit: entry.limit, theme: theme)
                    .padding(.top, 4)
            } else {
                Text("HIER \(entry.yesterday)")
                    .font(.mono(10, .bold))
                    .foregroundStyle(theme.secondary)
                    .padding(.top, 4)
            }
        }
    }
}

struct WeekBars: View {
    let week: [DayCount]
    let theme: TaffeTheme

    var body: some View {
        let maxCount = max(week.map { $0.count }.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(week) { day in
                let isToday = Calendar.current.isDateInToday(day.day)
                let height = max(3, CGFloat(day.count) / CGFloat(maxCount) * 64)
                VStack(spacing: 3) {
                    Rectangle()
                        .fill(isToday ? theme.primary : theme.secondary.opacity(0.55))
                        .frame(height: height)
                    Text(day.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.mono(9, .bold))
                        .foregroundStyle(isToday ? theme.primary : theme.dim)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct MediumTaffeView: View {
    let entry: PuffEntry

    var body: some View {
        let theme = entry.theme
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("// TAFFE")
                    .font(.mono(11, .bold))
                    .foregroundStyle(theme.primary)
                Spacer(minLength: 0)
                Text("\(entry.today)")
                    .font(.system(size: 48, weight: .black, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .shadow(color: theme.primary.opacity(0.8), radius: 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("AUJOURD'HUI")
                    .font(.mono(9, .semibold))
                    .foregroundStyle(theme.dim)
                Text("HIER \(entry.yesterday)")
                    .font(.mono(10, .bold))
                    .foregroundStyle(theme.secondary)
            }
            .frame(width: 110, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                AddPuffButton(theme: theme)
                Spacer(minLength: 0)
                WeekBars(week: entry.week, theme: theme)
            }
        }
    }
}

struct CircularTaffeView: View {
    let entry: PuffEntry

    var body: some View {
        if entry.limit > 0 {
            Gauge(value: Double(min(entry.today, entry.limit)), in: 0...Double(entry.limit)) {
                Text("T")
            } currentValueLabel: {
                Text("\(entry.today)")
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.today)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.5)
                    Text("TAF")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
            }
        }
    }
}

struct RectangularTaffeView: View {
    let entry: PuffEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("TAFFE")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
            Text("\(entry.today) aujourd'hui")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
            Text(entry.limit > 0 ? "limite \(entry.limit) · hier \(entry.yesterday)" : "hier \(entry.yesterday)")
                .font(.system(size: 11, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Déclaration

struct TaffeWidget: Widget {
    let kind = "TaffeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PuffProvider()) { entry in
            TaffeWidgetView(entry: entry)
        }
        .configurationDisplayName("Taffe")
        .description("Ton compteur de taffes du jour.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct TaffeWidgetBundle: WidgetBundle {
    var body: some Widget {
        TaffeWidget()
    }
}
