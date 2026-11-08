import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    CyberHeader(title: "STATS_", subtitle: "Analyse de consommation")
                    tiles
                    weekChart
                    hourChart
                    recentPanel
                }
                .padding(16)
            }
            .modifier(CyberScreen())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showHistory) {
                HistoryView()
            }
        }
    }

    // MARK: - Tuiles

    private var tiles: some View {
        let week = PuffStore.dailyCounts(in: detector.puffs, days: 7)
        let weekTotal = week.reduce(0) { $0 + $1.count }
        let average = Double(weekTotal) / 7.0
        let averageText = average.formatted(.number.precision(.fractionLength(1)))
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                         spacing: 10) {
            StatTile(title: "AUJOURD'HUI", value: "\(detector.todayCount)", color: theme.primary)
            StatTile(title: "HIER", value: "\(detector.yesterdayCount)", color: theme.secondary)
            StatTile(title: "MOY. 7 JOURS", value: averageText, color: theme.text)
            StatTile(title: "TOTAL", value: "\(detector.puffs.count)", color: theme.dim)
        }
    }

    // MARK: - Graphiques

    private var weekChart: some View {
        let days = PuffStore.dailyCounts(in: detector.puffs, days: 7)
        let limit = detector.dailyLimit
        return CyberPanel("7 derniers jours") {
            Chart {
                ForEach(days) { day in
                    BarMark(
                        x: .value("Jour", day.day, unit: .day),
                        y: .value("Taffes", day.count)
                    )
                    .foregroundStyle(theme.primary.gradient)
                    .annotation(position: .top) {
                        if day.count > 0 {
                            Text("\(day.count)")
                                .font(.mono(10))
                                .foregroundStyle(theme.dim)
                        }
                    }
                }
                if limit > 0 {
                    RuleMark(y: .value("Limite", limit))
                        .foregroundStyle(theme.alert)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .frame(height: 180)
        }
    }

    private var hourChart: some View {
        let hours = PuffStore.hourlyCounts(in: detector.puffs)
        return CyberPanel("Aujourd'hui par heure", accent: theme.secondary) {
            Chart(hours) { item in
                BarMark(
                    x: .value("Heure", item.hour),
                    y: .value("Taffes", item.count)
                )
                .foregroundStyle(theme.secondary.gradient)
            }
            .chartXScale(domain: -1...24)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text("\(hour)h")
                        }
                    }
                }
            }
            .frame(height: 140)
        }
    }

    // MARK: - Dernières taffes

    private var recentPanel: some View {
        let recent = Array(detector.puffs.suffix(8).reversed())
        return CyberPanel("Dernières taffes") {
            VStack(spacing: 8) {
                if recent.isEmpty {
                    Text("Aucune taffe enregistrée.")
                        .font(.mono(12))
                        .foregroundStyle(theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(recent, id: \.self) { date in
                    HStack {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.mono(12))
                            .foregroundStyle(theme.dim)
                        Spacer()
                        Text(date.formatted(date: .omitted, time: .standard))
                            .font(.mono(13, .bold))
                            .foregroundStyle(theme.text)
                    }
                }
                Button {
                    showHistory = true
                } label: {
                    Label("HISTORIQUE COMPLET", systemImage: "list.bullet")
                }
                .buttonStyle(CyberButtonStyle(color: theme.primary))
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Historique complet

struct HistoryView: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme

    var body: some View {
        let items = Array(detector.puffs.suffix(500).reversed())
        List {
            Section {
                ForEach(items, id: \.self) { date in
                    HStack {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.mono(13))
                            .foregroundStyle(theme.dim)
                        Spacer()
                        Text(date.formatted(date: .omitted, time: .standard))
                            .font(.mono(14, .bold))
                            .foregroundStyle(theme.text)
                    }
                    .listRowBackground(theme.surface)
                }
                .onDelete { offsets in
                    let dates = offsets.map { items[$0] }
                    for date in dates {
                        detector.remove(date)
                    }
                }
            } footer: {
                Text("Glisse une ligne vers la gauche pour supprimer une fausse détection.")
                    .font(.mono(11))
                    .foregroundStyle(theme.dim)
            }
        }
        .modifier(CyberScreen())
        .navigationTitle("HISTORIQUE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
