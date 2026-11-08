import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var detector: SoundDetector
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                counterSection
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
                        detector.triggerLabel = label.id
                    } label: {
                        HStack {
                            Image(systemName: label.id == detector.triggerLabel ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(label.id == detector.triggerLabel ? .green : .secondary)
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
            Text("Tire une taffe et regarde quelle étiquette monte. Touche-la pour en faire le déclencheur.")
        }
    }

    // MARK: - Réglages

    private var settingsSection: some View {
        Section("Détection") {
            NavigationLink {
                LabelPickerView()
            } label: {
                LabeledContent("Déclencheur",
                               value: detector.triggerLabel.isEmpty ? "Aucun" : detector.triggerLabel)
            }

            VStack(alignment: .leading) {
                Text("Seuil de confiance : \(Int(detector.threshold * 100)) %")
                Slider(value: $detector.threshold, in: 0.2...0.95, step: 0.05)
            }

            Stepper(value: $detector.cooldown, in: 1...10, step: 1) {
                Text("Pause entre 2 taffes : \(Int(detector.cooldown)) s")
            }
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
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [String] {
        search.isEmpty
            ? detector.knownLabels
            : detector.knownLabels.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(filtered, id: \.self) { label in
            Button {
                detector.triggerLabel = label
                dismiss()
            } label: {
                HStack {
                    Text(label)
                        .foregroundStyle(.primary)
                    Spacer()
                    if label == detector.triggerLabel {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "breathing, hiss…")
        .navigationTitle("Déclencheur")
        .navigationBarTitleDisplayMode(.inline)
    }
}
