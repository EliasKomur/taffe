import Foundation
import AVFoundation
import SoundAnalysis

struct LabelScore: Identifiable, Equatable {
    let id: String
    let confidence: Double
}

enum TaffeError: LocalizedError {
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .noMicrophone:
            return "Aucun micro disponible."
        }
    }
}

final class SoundDetector: NSObject, ObservableObject {

    // MARK: - État publié

    @Published private(set) var isListening = false
    @Published private(set) var topLabels: [LabelScore] = []
    @Published private(set) var puffs: [Date] = []
    @Published private(set) var lastDetection: Date?
    @Published var errorMessage: String?

    @Published var triggerLabel: String {
        didSet { UserDefaults.standard.set(triggerLabel, forKey: Keys.trigger) }
    }

    @Published var threshold: Double {
        didSet { UserDefaults.standard.set(threshold, forKey: Keys.threshold) }
    }

    @Published var cooldown: Double {
        didSet { UserDefaults.standard.set(cooldown, forKey: Keys.cooldown) }
    }

    private(set) var knownLabels: [String] = []

    var todayCount: Int {
        puffs.filter { Calendar.current.isDateInToday($0) }.count
    }

    // MARK: - Audio

    private let engine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.eliaskomur.taffe.analysis")
    private var lastDetectionDate: Date = .distantPast
    private var shouldBeListening = false

    private enum Keys {
        static let trigger = "triggerLabel"
        static let threshold = "threshold"
        static let cooldown = "cooldown"
        static let puffs = "puffs"
    }

    // MARK: - Init

    override init() {
        let defaults = UserDefaults.standard

        _triggerLabel = Published(initialValue: defaults.string(forKey: Keys.trigger) ?? "")

        let savedThreshold = defaults.double(forKey: Keys.threshold)
        _threshold = Published(initialValue: savedThreshold > 0 ? savedThreshold : 0.6)

        let savedCooldown = defaults.double(forKey: Keys.cooldown)
        _cooldown = Published(initialValue: savedCooldown > 0 ? savedCooldown : 3)

        let savedPuffs = defaults.array(forKey: Keys.puffs) as? [Double] ?? []
        _puffs = Published(initialValue: savedPuffs.map { Date(timeIntervalSince1970: $0) })

        super.init()

        if let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
            knownLabels = request.knownClassifications.sorted()
        }

        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: session)
        center.addObserver(self, selector: #selector(handleRouteChange(_:)),
                           name: AVAudioSession.routeChangeNotification, object: session)
        center.addObserver(self, selector: #selector(handleMediaReset(_:)),
                           name: AVAudioSession.mediaServicesWereResetNotification, object: session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Écoute

    func start() {
        errorMessage = nil
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.shouldBeListening = true
                    self.startEngine()
                } else {
                    self.errorMessage = "Accès au micro refusé. Active-le dans Réglages → Taffe → Micro."
                }
            }
        }
    }

    func stop() {
        shouldBeListening = false
        stopEngine()
    }

    private func startEngine() {
        guard !engine.isRunning else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw TaffeError.noMicrophone
            }

            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.overlapFactor = 0.5

            let newAnalyzer = SNAudioStreamAnalyzer(format: format)
            try newAnalyzer.add(request, withObserver: self)
            analyzer = newAnalyzer

            let queue = analysisQueue
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 8192, format: format) { buffer, time in
                queue.async {
                    newAnalyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }

            engine.prepare()
            try engine.start()
            isListening = true
        } catch {
            stopEngine()
            errorMessage = "Impossible de démarrer l'écoute : \(error.localizedDescription)"
        }
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        analyzer?.removeAllRequests()
        analyzer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
        topLabels = []
    }

    private func restartIfNeeded() {
        guard shouldBeListening else { return }
        stopEngine()
        startEngine()
    }

    // MARK: - Interruptions (appel, Siri, casque…)

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        DispatchQueue.main.async {
            switch type {
            case .began:
                self.stopEngine()
            case .ended:
                if self.shouldBeListening {
                    self.startEngine()
                }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            DispatchQueue.main.async { self.restartIfNeeded() }
        default:
            break
        }
    }

    @objc private func handleMediaReset(_ notification: Notification) {
        DispatchQueue.main.async { self.restartIfNeeded() }
    }

    // MARK: - Taffes

    private func registerDetection() {
        let now = Date()
        // Une taffe = un bloc de son continu : on ne compte que si le son
        // s'était arrêté depuis au moins `cooldown` secondes.
        if now.timeIntervalSince(lastDetectionDate) >= cooldown {
            addPuff(at: now)
            lastDetection = now
        }
        lastDetectionDate = now
    }

    func addPuff(at date: Date = Date()) {
        puffs.append(date)
        savePuffs()
    }

    func removeLastPuff() {
        guard !puffs.isEmpty else { return }
        puffs.removeLast()
        savePuffs()
    }

    func clearAll() {
        puffs.removeAll()
        savePuffs()
    }

    private func savePuffs() {
        UserDefaults.standard.set(puffs.map { $0.timeIntervalSince1970 }, forKey: Keys.puffs)
    }
}

// MARK: - Résultats de l'analyse

extension SoundDetector: SNResultsObserving {

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }

        let top = result.classifications.prefix(5).map {
            LabelScore(id: $0.identifier, confidence: $0.confidence)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.topLabels = top

            guard !self.triggerLabel.isEmpty else { return }
            let confidence = result.classification(forIdentifier: self.triggerLabel)?.confidence ?? 0
            if confidence >= self.threshold {
                self.registerDetection()
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.errorMessage = "Erreur d'analyse : \(error.localizedDescription)"
            self.stop()
        }
    }

    func requestDidComplete(_ request: SNRequest) {}
}
