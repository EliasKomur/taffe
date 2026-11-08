import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var detector: SoundDetector
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                counterSection
                scoreSection
                liveSection
                settingsSection
                historySection
            }
            .navigationTitle("Taffe")
            .alert("Oups", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(detector.errorMessage ?? "")
            }
            .confirmationDialog("Effacer tout l'historique ?",
                                isPresented: $showClearConfirm,
                                titleVisibility: .visible) {
                Button("Tout effacer", role: .destructive) { detector.clearAll() }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    // MARK: - Compteur

    private var counterSection: some View {
        Section {
            VStack(spacing: 12) {
                Text("\(detector.todayCount)")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: detector.todayCount)

                Text("taffes aujourd'hui")
                    .foregroundStyle(.secondary)

                Button {
                    detector.isListening ? detector.stop() : detector.start()
                } label: {
                    Label(detector.isListening ? "Arrêter l'écoute" : "Lancer l'écoute",
                          systemImage: detector.isListening ? "stop.fill" : "ear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(detector.isListening ? .red : .green)
                .controlSize(.large)

                HStack {
                    Button {
                        detector.addPuff()
                    } label: {
                        Label("+1", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        detector.removeLastPuff()
                    } label: {
                        Label("Annuler", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(detector.puffs.isEmpty)
                }

                if let last = detector.lastDetection {
                    Text("Dernière taffe détectée : \(last.formatted(date: .omitted, time: .standard))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Score taffe

    private var scoreSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Score taffe")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(detector.currentScore * 100)) %")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(detector.isAboveThreshold ? .green : .primary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                        Capsule()
                            .fill(detector.isAboveThreshold ? Color.green : Color.blue)
                            .frame(width: geo.size.width * detector.currentScore)
                            .animation(.easeOut(duration: 0.15), value: detector.currentScore)
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 3)
                            .offset(x: geo.size.width * detector.threshold - 1.5)
                    }
                }
                .frame(height: 14)

                Text("Trait orange = seuil (\(Int(detector.threshold * 100)) %)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } footer: {
            if detector.triggerLabels.isEmpty {
                Text("Coche au moins un son ci-dessous pour activer le comptage.")
            } else {
                Text("Regarde le score au repos, puis pendant une taffe, et place le seuil entre les deux.")
            }
        }
    }

    // MARK: - En direct

    private var liveSection: some View {
        Section {
            if !detector.isListening {
                Text("Lance l'écoute pour voir ce que l'iPhone entend.")
                    .foregroundStyle(.secondary)
            } else if detector.topLabels.isEmpty {
                Text("Écoute en cours…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detector.topLabels) { label in
                    Button {
                        detector.toggleTrigger(label.id)
                    } label: {
                        HStack {
                            Image(systemName: detector.isTrigger(label.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(detector.isTrigger(label.id) ? .green : .secondary)
                            Text(label.id)
                                .foregroundStyle(.primary)
                            Spacer()
                            ProgressView(value: label.confidence)
                                .frame(width: 80)
                            Text("\(Int(label.confidence * 100)) %")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }
        } header: {
            Text("En direct")
        } footer: {
            Text("Touche un son pour le cocher ou le décocher. Tous les sons cochés s'additionnent dans le score taffe.")
        }
    }

    // MARK: - Réglages

    private var settingsSection: some View {
        Section("Détection") {
            NavigationLink {
                LabelPickerView()
            } label: {
                LabeledContent("Déclencheurs", value: triggerSummary)
            }

            VStack(alignment: .leading) {
                Text("Seuil : \(Int(detector.threshold * 100)) %")
                Slider(value: $detector.threshold, in: 0.05...0.95, step: 0.01)
            }

            Stepper(value: $detector.cooldown, in: 1...10, step: 1) {
                Text("Pause entre 2 taffes : \(Int(detector.cooldown)) s")
            }
        }
    }

    private var triggerSummary: String {
        switch detector.triggerLabels.count {
        case 0: return "Aucun"
        case 1: return detector.triggerLabels.first ?? ""
        default: return "\(detector.triggerLabels.count) sons"
        }
    }

    // MARK: - Historique

    private var historySection: some View {
        Section("Historique") {
            if detector.puffs.isEmpty {
                Text("Aucune taffe enregistrée.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(detector.puffs.suffix(50).reversed()), id: \.self) { date in
                    Text(date.formatted(date: .abbreviated, time: .standard))
                }
                Button("Effacer tout l'historique", role: .destructive) {
                    showClearConfirm = true
                }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { detector.errorMessage != nil },
            set: { if !$0 { detector.errorMessage = nil } }
        )
    }
}

struct LabelPickerView: View {
    @EnvironmentObject private var detector: SoundDetector
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
                Section("Cochés") {
                    ForEach(selected, id: \.self) { label in
                        row(label)
                    }
                }
            }

            Section(search.isEmpty ? "Tous les sons" : "Résultats") {
                ForEach(filtered, id: \.self) { label in
                    row(label)
                }
            }
        }
        .searchable(text: $search, prompt: "snoring, breathing…")
        .navigationTitle("Déclencheurs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String) -> some View {
        Button {
            detector.toggleTrigger(label)
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if detector.isTrigger(label) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}