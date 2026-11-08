import SwiftUI

// MARK: - Racine

struct RootView: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            LiveView()
                .tabItem { Label("LIVE", systemImage: "waveform") }
            StatsView()
                .tabItem { Label("STATS", systemImage: "chart.bar.xaxis") }
            SystemView()
                .tabItem { Label("SYSTÈME", systemImage: "cpu") }
        }
        .tint(theme.primary)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                detector.appBecameActive()
            }
        }
        .alert("ERREUR SYSTÈME", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(detector.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { detector.errorMessage != nil },
            set: { if !$0 { detector.errorMessage = nil } }
        )
    }
}

// MARK: - Onglet LIVE

struct LiveView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CyberHeader(title: "TAFFE_", subtitle: theme.name)
                StatusStrip()
                CounterPanel()
                ScorePanel()
                LivePanel()
            }
            .padding(16)
        }
        .modifier(CyberScreen())
    }
}

struct StatusStrip: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme
    @State private var blink = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color, radius: 6)
                .opacity(blink ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: blink)
            Text(text)
                .font(.mono(13, .bold))
                .foregroundStyle(color)
                .tracking(1.5)
            Spacer()
            if detector.restartCount > 0 {
                Text("RELANCES \(detector.restartCount)")
                    .font(.mono(10))
                    .foregroundStyle(theme.dim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CutCornerShape(cut: 8).fill(theme.surface))
        .overlay(CutCornerShape(cut: 8).stroke(color.opacity(0.5), lineWidth: 1))
        .onAppear { blink = true }
    }

    private var color: Color {
        switch detector.listenState {
        case .active: return theme.primary
        case .reconnecting: return theme.alert
        case .quiet: return theme.secondary
        case .off: return theme.dim
        }
    }

    private var text: String {
        switch detector.listenState {
        case .active: return "ÉCOUTE ACTIVE"
        case .reconnecting: return "RECONNEXION…"
        case .quiet: return "PAUSE NUIT"
        case .off: return "HORS LIGNE"
        }
    }
}

struct CounterPanel: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme
    @State private var glitch = false

    var body: some View {
        CyberPanel("Compteur") {
            VStack(spacing: 14) {
                counter
                Text("TAFFES AUJOURD'HUI")
                    .font(.mono(12, .semibold))
                    .foregroundStyle(theme.dim)
                    .tracking(2)
                if detector.dailyLimit > 0 {
                    limitBar
                }
                infoRow
                listenButton
                HStack(spacing: 10) {
                    Button {
                        detector.addPuff()
                    } label: {
                        Label("+1", systemImage: "plus")
                    }
                    .buttonStyle(CyberButtonStyle(color: theme.secondary))

                    Button {
                        detector.removeLastPuff()
                    } label: {
                        Label("ANNULER", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(CyberButtonStyle(color: theme.dim))
                    .disabled(detector.puffs.isEmpty)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: detector.todayCount) { oldValue, newValue in
            guard newValue > oldValue else { return }
            glitch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                glitch = false
            }
        }
    }

    private var counter: some View {
        let value = "\(detector.todayCount)"
        return ZStack {
            Text(value)
                .foregroundStyle(theme.secondary)
                .offset(x: glitch ? -5 : 0, y: glitch ? 2 : 0)
                .opacity(glitch ? 0.9 : 0)
            Text(value)
                .foregroundStyle(theme.alert)
                .offset(x: glitch ? 5 : 0, y: glitch ? -2 : 0)
                .opacity(glitch ? 0.9 : 0)
            Text(value)
                .foregroundStyle(theme.text)
                .shadow(color: theme.primary.opacity(0.9), radius: 14)
        }
        .font(.system(size: 96, weight: .black, design: .monospaced))
        .contentTransition(.numericText())
        .animation(.snappy(duration: 0.2), value: detector.todayCount)
    }

    private var limitBar: some View {
        let limit = detector.dailyLimit
        let today = detector.todayCount
        let ratio = Double(today) / Double(max(limit, 1))
        let color = today >= limit ? theme.alert : theme.primary
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LIMITE")
                    .font(.mono(11, .bold))
                    .foregroundStyle(theme.dim)
                Spacer()
                Text("\(today)/\(limit)")
                    .font(.mono(11, .bold))
                    .foregroundStyle(color)
            }
            NeonBar(value: ratio, color: color)
        }
    }

    private var infoRow: some View {
        HStack {
            Text("HIER \(detector.yesterdayCount)")
            Spacer()
            if let last = detector.lastDetection ?? detector.puffs.last {
                Text("DERNIÈRE \(last.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.mono(11, .bold))
        .foregroundStyle(theme.dim)
    }

    private var listenButton: some View {
        Button {
            if detector.wantsListening {
                detector.stop()
            } else {
                detector.start()
            }
        } label: {
            Label(detector.wantsListening ? "ARRÊTER L'ÉCOUTE" : "LANCER L'ÉCOUTE",
                  systemImage: detector.wantsListening ? "stop.fill" : "waveform")
        }
        .buttonStyle(CyberButtonStyle(color: detector.wantsListening ? theme.alert : theme.primary,
                                      filled: true,
                                      textColor: theme.background))
    }
}

struct ScorePanel: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme

    var body: some View {
        let active = detector.isAboveThreshold
        CyberPanel("Score taffe", accent: active ? theme.secondary : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(Int(detector.currentScore * 100)) %")
                        .font(.mono(28, .heavy))
                        .foregroundStyle(active ? theme.secondary : theme.text)
                    Spacer()
                    Text("SEUIL \(Int(detector.threshold * 100)) %")
                        .font(.mono(12, .bold))
                        .foregroundStyle(theme.alert)
                }
                NeonBar(value: detector.currentScore,
                        color: active ? theme.secondary : theme.primary,
                        marker: detector.threshold,
                        markerColor: theme.alert,
                        height: 12)
                    .animation(.easeOut(duration: 0.15), value: detector.currentScore)
                if detector.triggerLabels.isEmpty {
                    Text("Aucun son coché : touche un son dans EN DIRECT.")
                        .font(.mono(11))
                        .foregroundStyle(theme.alert)
                }
            }
        }
    }
}

struct LivePanel: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme

    var body: some View {
        CyberPanel("En direct") {
            VStack(alignment: .leading, spacing: 8) {
                if detector.topLabels.isEmpty {
                    Text(detector.wantsListening ? "Analyse en cours…" : "Lance l'écoute pour voir ce que le micro entend.")
                        .font(.mono(12))
                        .foregroundStyle(theme.dim)
                } else {
                    ForEach(detector.topLabels) { label in
                        LabelRow(label: label)
                    }
                }
                Text("Touche un son pour le cocher. Les sons cochés s'additionnent dans le score.")
                    .font(.mono(10))
                    .foregroundStyle(theme.dim)
                    .padding(.top, 4)
            }
        }
    }
}

struct LabelRow: View {
    @EnvironmentObject private var detector: SoundDetector
    @Environment(\.theme) private var theme
    let label: LabelScore

    var body: some View {
        let selected = detector.isTrigger(label.id)
        Button {
            detector.toggleTrigger(label.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? theme.primary : theme.dim)
                Text(label.id)
                    .font(.mono(13, selected ? .bold : .regular))
                    .foregroundStyle(selected ? theme.text : theme.dim)
                    .lineLimit(1)
                Spacer(minLength: 8)
                NeonBar(value: label.confidence,
                        color: selected ? theme.primary : theme.dim,
                        height: 6)
                    .frame(width: 70)
                Text("\(Int(label.confidence * 100))%")
                    .font(.mono(12))
                    .foregroundStyle(theme.dim)
                    .frame(width: 40, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
