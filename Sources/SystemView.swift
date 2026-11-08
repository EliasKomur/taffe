import SwiftUI

struct SystemView: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme
    @AppStorage(SharedKeys.theme, store: TaffeShared.defaults) private var themeID = "neon"
    @State private var showClearConfirm = false
    @State private var exportURL: URL?
    @State private var showExport = false
    @State private var shareItems: [URL] = []
    @State private var showClipShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    CyberHeader(title: "SYSTÈME_", subtitle: "Configuration")
                    themePanel
                    detectionPanel
                    backgroundPanel
                    quietPanel
                    limitPanel
                    dataPanel
                    infoPanel
                }
                .padding(16)
            }
            .modifier(CyberScreen())
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog("Effacer tout l'historique ?",
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button("Tout effacer", role: .destructive) {
                detector.clearAll()
            }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $showExport) {
            if let exportURL {
                ActivityView(items: [exportURL])
            }
        }
        .sheet(isPresented: $showClipShare) {
            ActivityView(items: shareItems)
        }
    }

    // MARK: - Thème

    private var themePanel: some View {
        CyberPanel("Thème") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(TaffeTheme.all) { item in
                    ThemeCard(item: item, selected: item.id == theme.id) {
                        themeID = item.id
                        detector.reloadWidgets()
                    }
                }
            }
        }
    }

    // MARK: - Détection

    private var detectionPanel: some View {
        CyberPanel("Détection") {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink {
                    LabelPickerView()
                } label: {
                    SettingRow(title: "SONS DÉCLENCHEURS", value: triggerSummary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text("SEUIL : \(Int(detector.threshold * 100)) %")
                        .font(.mono(12, .bold))
                        .foregroundStyle(theme.text)
                    Slider(value: $detector.threshold, in: 0.05...0.95, step: 0.01)
                        .tint(theme.primary)
                }

                Stepper(value: $detector.cooldown, in: 1...10, step: 1) {
                    Text("PAUSE ENTRE 2 TAFFES : \(Int(detector.cooldown)) s")
                        .font(.mono(12, .bold))
                        .foregroundStyle(theme.text)
                }
            }
        }
    }

    private var triggerSummary: String {
        switch detector.triggerLabels.count {
        case 0: return "AUCUN"
        case 1: return detector.triggerLabels.first ?? ""
        default: return "\(detector.triggerLabels.count) SONS"
        }
    }

    // MARK: - Écran verrouillé

    private var backgroundPanel: some View {
        CyberPanel("Écran verrouillé", accent: theme.secondary) {
            VStack(alignment: .leading, spacing: 16) {
                InfoLine(key: "APPRENTISSAGE",
                         value: detector.fallbackReady
                            ? "PRÊT (\(detector.fallbackLearned) blocs)"
                            : "\(detector.fallbackLearned)/\(FallbackDetector.requiredFrames)")

                VStack(alignment: .leading, spacing: 6) {
                    Text("RESSEMBLANCE MINI : \(Int(detector.fallbackThreshold * 100)) %")
                        .font(.mono(12, .bold))
                        .foregroundStyle(theme.text)
                    Slider(value: $detector.fallbackThreshold, in: 0.6...0.98, step: 0.01)
                        .tint(theme.secondary)
                    Text("Plus haut = moins de fausses taffes, mais risque d'en rater.")
                        .font(.mono(10))
                        .foregroundStyle(theme.dim)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("VOLUME MINI : +\(Int(detector.fallbackMargin)) dB")
                        .font(.mono(12, .bold))
                        .foregroundStyle(theme.text)
                    Slider(value: $detector.fallbackMargin, in: 3...20, step: 1)
                        .tint(theme.secondary)
                    Text("Au-dessus du bruit ambiant. Plus haut = ignore les sons faibles.")
                        .font(.mono(10))
                        .foregroundStyle(theme.dim)
                }

                Button {
                    detector.resetFallbackLearning()
                } label: {
                    Label("REFAIRE L'APPRENTISSAGE", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(CyberButtonStyle(color: theme.alert))
            }
        }
    }

    // MARK: - Pause nuit

    private var quietPanel: some View {
        CyberPanel("Pause nuit", accent: theme.secondary) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $detector.quietEnabled) {
                    Text("IGNORER LES SONS LA NUIT")
                        .font(.mono(12, .bold))
                        .foregroundStyle(theme.text)
                }
                .tint(theme.primary)

                if detector.quietEnabled {
                    Stepper(value: $detector.quietStart, in: 0...23) {
                        Text("DE \(detector.quietStart) H")
                            .font(.mono(12, .bold))
                            .foregroundStyle(theme.text)
                    }
                    Stepper(value: $detector.quietEnd, in: 0...23) {
                        Text("À \(detector.quietEnd) H")
                            .font(.mono(12, .bold))
                            .foregroundStyle(theme.text)
                    }
                }

                Text("Pendant ces heures, l'écoute reste active mais rien n'est compté (ronflements…).")
                    .font(.mono(10))
                    .foregroundStyle(theme.dim)
            }
        }
    }

    // MARK: - Limite

    private var limitPanel: some View {
        CyberPanel("Limite quotidienne", accent: theme.alert) {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(value: $detector.dailyLimit, in: 0...300, step: 5) {
                    Text(detector.dailyLimit == 0 ? "LIMITE : AUCUNE" : "LIMITE : \(detector.dailyLimit) / JOUR")
                        .font(.mono(12, .bold))
                        .foregroundStyle(theme.text)
                }

                Toggle(isOn: $detector.limitAlert) {
                    Text("NOTIFICATION QUAND ATTEINTE")
                        .font(.mono(12, .bold))
                        .foregroundStyle(theme.text)
                }
                .tint(theme.primary)
                .disabled(detector.dailyLimit == 0)
            }
        }
    }

    // MARK: - Données

    private var dataPanel: some View {
        CyberPanel("Données") {
            VStack(spacing: 10) {
                Button {
                    exportURL = detector.makeCSV()
                    showExport = exportURL != nil
                } label: {
                    Label("EXPORTER EN CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(CyberButtonStyle(color: theme.secondary))

                NavigationLink {
                    LogView()
                } label: {
                    Label("JOURNAL SYSTÈME", systemImage: "terminal")
                }
                .buttonStyle(CyberButtonStyle(color: theme.primary))

                InfoLine(key: "ÉCHANTILLONS AUDIO",
                         value: "\(detector.clipTaffes) taffes · \(detector.clipFond) fond")
                    .padding(.top, 4)

                Button {
                    let files = detector.clipFiles()
                    if !files.isEmpty {
                        shareItems = files
                        showClipShare = true
                    }
                } label: {
                    Label("EXPORTER LES ÉCHANTILLONS", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(CyberButtonStyle(color: theme.secondary))
                .disabled(detector.clipTaffes + detector.clipFond == 0)

                Button {
                    showClearConfirm = true
                } label: {
                    Label("EFFACER L'HISTORIQUE", systemImage: "trash")
                }
                .buttonStyle(CyberButtonStyle(color: theme.alert))
            }
        }
    }

    // MARK: - Diagnostic

    private var infoPanel: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return CyberPanel("Diagnostic", accent: theme.dim) {
            VStack(alignment: .leading, spacing: 8) {
                InfoLine(key: "VERSION", value: version)
                InfoLine(key: "WIDGET", value: TaffeShared.hasGroupContainer ? "SYNCHRO OK" : "PAS DE GROUPE PARTAGÉ")
                InfoLine(key: "RELANCES AUTO", value: "\(detector.restartCount)")
                InfoLine(key: "TAFFES ENREGISTRÉES", value: "\(detector.puffs.count)")
            }
        }
    }
}

// MARK: - Carte de thème

struct ThemeCard: View {
    let item: TaffeTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(item.primary).frame(width: 10, height: 10)
                    Circle().fill(item.secondary).frame(width: 10, height: 10)
                    Circle().fill(item.alert).frame(width: 10, height: 10)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(item.primary)
                    }
                }
                Text(item.name)
                    .font(.mono(12, .heavy))
                    .foregroundStyle(item.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(item.tagline)
                    .font(.mono(9))
                    .foregroundStyle(item.dim)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(CutCornerShape(cut: 10).fill(item.background))
            .overlay(CutCornerShape(cut: 10).stroke(selected ? item.primary : item.dim.opacity(0.35),
                                                    lineWidth: selected ? 2 : 1))
            .shadow(color: selected ? item.primary.opacity(0.5) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Choix des sons

struct LabelPickerView: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme
    @State private var search = ""

    private var selected: [String] {
        detector.knownLabels.filter { detector.isTrigger($0) }
    }

    private var filtered: [String] {
        search.isEmpty
            ? detector.knownLabels
            : detector.knownLabels.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if !selected.isEmpty && search.isEmpty {
                Section {
                    ForEach(selected, id: \.self) { label in
                        row(label)
                    }
                } header: {
                    Text("COCHÉS")
                        .font(.mono(11, .bold))
                        .foregroundStyle(theme.primary)
                }
            }

            Section {
                ForEach(filtered, id: \.self) { label in
                    row(label)
                }
            } header: {
                Text(search.isEmpty ? "TOUS LES SONS" : "RÉSULTATS")
                    .font(.mono(11, .bold))
                    .foregroundStyle(theme.dim)
            }
        }
        .searchable(text: $search, prompt: "snoring, breathing…")
        .modifier(CyberScreen())
        .navigationTitle("DÉCLENCHEURS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func row(_ label: String) -> some View {
        Button {
            detector.toggleTrigger(label)
        } label: {
            HStack {
                Text(label)
                    .font(.mono(14))
                    .foregroundStyle(theme.text)
                Spacer()
                if detector.isTrigger(label) {
                    Image(systemName: "checkmark.square.fill")
                        .foregroundStyle(theme.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .listRowBackground(theme.surface)
    }
}

// MARK: - Journal

struct LogView: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme
    @State private var showShare = false

    var body: some View {
        let entries = Array(detector.log.reversed())
        List {
            if entries.isEmpty {
                Text("Journal vide.")
                    .font(.mono(12))
                    .foregroundStyle(theme.dim)
                    .listRowBackground(theme.surface)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date.formatted(date: .abbreviated, time: .standard))
                        .font(.mono(10))
                        .foregroundStyle(theme.dim)
                    Text(entry.message)
                        .font(.mono(13))
                        .foregroundStyle(theme.text)
                }
                .listRowBackground(theme.surface)
            }
        }
        .modifier(CyberScreen())
        .navigationTitle("JOURNAL")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Vider") {
                    detector.clearLog()
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: [detector.logText])
        }
    }
}
