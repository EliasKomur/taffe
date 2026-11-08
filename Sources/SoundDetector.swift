import Foundation
import AVFoundation
import SoundAnalysis
import UIKit
import UserNotifications
import WidgetKit

struct LabelScore: Identifiable, Equatable {
    let id: String
    let confidence: Double
}

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let message: String
}

enum ListenState {
    case off
    case active
    case reconnecting
    case quiet
}

enum TaffeError: LocalizedError {
    case noMicrophone

    var errorDescription: String? {
        "Aucun micro disponible."
    }
}

/// Compteur de position audio, utilisé uniquement sur la file d'analyse.
private final class FrameCounter {
    var position: AVAudioFramePosition = 0
}

/// Indique si le classifieur d'Apple doit recevoir le son (seulement app ouverte).
/// Utilisé uniquement sur la file d'analyse.
private final class FeedGate {
    var classifierEnabled = true
}

/// Reçoit les résultats d'une session d'analyse. Les résultats d'une ancienne
/// session (après un redémarrage) sont ignorés grâce au numéro de génération.
private final class AnalysisObserver: NSObject, SNResultsObserving {
    let generation: Int
    weak var detector: SoundDetector?

    init(generation: Int, detector: SoundDetector) {
        self.generation = generation
        self.detector = detector
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        var scores: [String: Double] = [:]
        for classification in result.classifications {
            scores[classification.identifier] = classification.confidence
        }
        let top = result.classifications.prefix(8).map {
            LabelScore(id: $0.identifier, confidence: $0.confidence)
        }
        let generation = self.generation
        let detector = self.detector
        DispatchQueue.main.async {
            detector?.handle(top: top, scores: scores, generation: generation)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        let message = error.localizedDescription
        let generation = self.generation
        let detector = self.detector
        DispatchQueue.main.async {
            detector?.handleFailure(message: message, generation: generation)
        }
    }

    func requestDidComplete(_ request: SNRequest) {}
}

final class SoundDetector: NSObject, ObservableObject {

    // MARK: - État publié

    @Published private(set) var wantsListening = false
    @Published private(set) var engineRunning = false
    @Published private(set) var isInBackground = false
    @Published private(set) var topLabels: [LabelScore] = []
    @Published private(set) var puffs: [Date] = []
    @Published private(set) var lastDetection: Date?
    @Published private(set) var currentScore: Double = 0
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var restartCount = 0
    @Published private(set) var fallbackLearned = 0
    @Published private(set) var fallbackSimilarity: Double = 0
    @Published private(set) var fallbackLevel: Double = 0
    @Published private(set) var clipTaffes = 0
    @Published private(set) var clipFond = 0
    @Published var errorMessage: String?

    @Published private(set) var triggerLabels: Set<String> {
        didSet { UserDefaults.standard.set(Array(triggerLabels), forKey: Keys.triggers) }
    }

    @Published var threshold: Double {
        didSet { UserDefaults.standard.set(threshold, forKey: Keys.threshold) }
    }

    @Published var cooldown: Double {
        didSet { UserDefaults.standard.set(cooldown, forKey: Keys.cooldown) }
    }

    @Published var quietEnabled: Bool {
        didSet { UserDefaults.standard.set(quietEnabled, forKey: Keys.quietEnabled) }
    }

    @Published var quietStart: Int {
        didSet { UserDefaults.standard.set(quietStart, forKey: Keys.quietStart) }
    }

    @Published var quietEnd: Int {
        didSet { UserDefaults.standard.set(quietEnd, forKey: Keys.quietEnd) }
    }

    @Published var dailyLimit: Int {
        didSet {
            TaffeShared.defaults.set(dailyLimit, forKey: SharedKeys.dailyLimit)
            reloadWidgets()
        }
    }

    @Published var limitAlert: Bool {
        didSet {
            UserDefaults.standard.set(limitAlert, forKey: Keys.limitAlert)
            if limitAlert {
                requestNotificationPermission()
            }
        }
    }

    /// Ressemblance minimale avec l'empreinte de ta vape (détecteur d'arrière-plan).
    @Published var fallbackThreshold: Double {
        didSet {
            UserDefaults.standard.set(fallbackThreshold, forKey: Keys.fallbackThreshold)
            let value = fallbackThreshold
            let fallback = self.fallback
            analysisQueue.async { fallback.similarityThreshold = value }
        }
    }

    /// Volume minimal au-dessus du bruit ambiant, en dB (détecteur d'arrière-plan).
    @Published var fallbackMargin: Double {
        didSet {
            UserDefaults.standard.set(fallbackMargin, forKey: Keys.fallbackMargin)
            let value = fallbackMargin
            let fallback = self.fallback
            analysisQueue.async { fallback.marginDB = value }
        }
    }

    private(set) var knownLabels: [String] = []

    // MARK: - Valeurs calculées

    var todayCount: Int {
        PuffStore.count(in: puffs)
    }

    var yesterdayCount: Int {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return PuffStore.count(in: puffs, on: yesterday)
    }

    var isAboveThreshold: Bool {
        !triggerLabels.isEmpty && currentScore >= threshold
    }

    var fallbackReady: Bool {
        fallbackLearned >= FallbackDetector.requiredFrames
    }

    var isQuietNow: Bool {
        guard quietEnabled, quietStart != quietEnd else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        if quietStart < quietEnd {
            return hour >= quietStart && hour < quietEnd
        }
        return hour >= quietStart || hour < quietEnd
    }

    var listenState: ListenState {
        if !wantsListening { return .off }
        if !engineRunning { return .reconnecting }
        if isQuietNow { return .quiet }
        return .active
    }

    var logText: String {
        log.map { entry in
            "\(entry.date.formatted(date: .numeric, time: .standard))  \(entry.message)"
        }
        .joined(separator: "\n")
    }

    // MARK: - Audio

    private let engine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private var observer: AnalysisObserver?
    private let analysisQueue = DispatchQueue(label: "com.eliaskomur.taffe.analysis")
    private let fallback = FallbackDetector()
    private let clips = ClipCollector()
    private let gate = FeedGate()
    private var generation = 0
    private var lastResultDate = Date.distantPast
    private var lastDetectionDate = Date.distantPast
    private var watchdog: Timer?
    private var restartTimes: [Date] = []
    private var pendingRestart = false
    private var consecutiveFailures = 0
    private var stoppedAlertSent = false
    private var interruptedAt: Date?

    private enum Keys {
        static let triggers = "triggerLabels"
        static let legacyTrigger = "triggerLabel"
        static let threshold = "threshold"
        static let cooldown = "cooldown"
        static let quietEnabled = "quietEnabled"
        static let quietStart = "quietStart"
        static let quietEnd = "quietEnd"
        static let limitAlert = "limitAlert"
        static let lastLimitAlert = "lastLimitAlertDay"
        static let wantsListening = "wantsListening"
        static let log = "eventLog"
        static let fallbackThreshold = "fallbackThreshold"
        static let fallbackMargin = "fallbackMargin"
    }

    // MARK: - Init

    override init() {
        let defaults = UserDefaults.standard

        var triggers = Set(defaults.stringArray(forKey: Keys.triggers) ?? [])
        if triggers.isEmpty, let legacy = defaults.string(forKey: Keys.legacyTrigger), !legacy.isEmpty {
            triggers.insert(legacy)
        }
        _triggerLabels = Published(initialValue: triggers)

        let savedThreshold = defaults.double(forKey: Keys.threshold)
        _threshold = Published(initialValue: savedThreshold > 0 ? savedThreshold : 0.4)

        let savedCooldown = defaults.double(forKey: Keys.cooldown)
        _cooldown = Published(initialValue: savedCooldown > 0 ? savedCooldown : 3)

        _quietEnabled = Published(initialValue: defaults.bool(forKey: Keys.quietEnabled))
        _quietStart = Published(initialValue: defaults.object(forKey: Keys.quietStart) as? Int ?? 23)
        _quietEnd = Published(initialValue: defaults.object(forKey: Keys.quietEnd) as? Int ?? 7)
        _dailyLimit = Published(initialValue: PuffStore.dailyLimit)
        _limitAlert = Published(initialValue: defaults.bool(forKey: Keys.limitAlert))

        let savedFallbackThreshold = defaults.double(forKey: Keys.fallbackThreshold)
        _fallbackThreshold = Published(initialValue: savedFallbackThreshold > 0 ? savedFallbackThreshold : 0.85)
        let savedFallbackMargin = defaults.double(forKey: Keys.fallbackMargin)
        _fallbackMargin = Published(initialValue: savedFallbackMargin > 0 ? savedFallbackMargin : 8)

        _puffs = Published(initialValue: PuffStore.load())
        _log = Published(initialValue: SoundDetector.loadLog())

        super.init()

        if let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
            knownLabels = request.knownClassifications.sorted()
        }

        // Détecteur d'arrière-plan
        fallback.similarityThreshold = fallbackThreshold
        fallback.marginDB = fallbackMargin
        fallback.onPuff = { [weak self] in
            DispatchQueue.main.async {
                self?.registerBackgroundDetection()
            }
        }
        fallback.onStatus = { [weak self] similarity, level in
            DispatchQueue.main.async {
                guard let self, !self.isInBackground else { return }
                self.fallbackSimilarity = similarity
                self.fallbackLevel = level
            }
        }
        fallback.onLearned = { [weak self] frames in
            DispatchQueue.main.async {
                self?.fallbackLearned = frames
            }
        }
        fallbackLearned = fallback.learnedFrames
        refreshClipCounts()

        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: session)
        center.addObserver(self, selector: #selector(handleRouteChange(_:)),
                           name: AVAudioSession.routeChangeNotification, object: session)
        center.addObserver(self, selector: #selector(handleMediaReset(_:)),
                           name: AVAudioSession.mediaServicesWereResetNotification, object: session)
        center.addObserver(self, selector: #selector(handleConfigurationChange(_:)),
                           name: .AVAudioEngineConfigurationChange, object: engine)
        center.addObserver(self, selector: #selector(handlePuffsChanged(_:)),
                           name: TaffeShared.puffsChanged, object: nil)
        center.addObserver(self, selector: #selector(appDidEnterBackground(_:)),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillEnterForeground(_:)),
                           name: UIApplication.willEnterForegroundNotification, object: nil)

        // Reprise automatique si l'écoute était active à la dernière fermeture.
        if defaults.bool(forKey: Keys.wantsListening) {
            DispatchQueue.main.async { [weak self] in
                self?.start(auto: true)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Déclencheurs

    func toggleTrigger(_ label: String) {
        if triggerLabels.contains(label) {
            triggerLabels.remove(label)
        } else {
            triggerLabels.insert(label)
        }
    }

    func isTrigger(_ label: String) -> Bool {
        triggerLabels.contains(label)
    }

    // MARK: - Écoute

    func start() {
        start(auto: false)
    }

    private func start(auto: Bool) {
        if !auto {
            errorMessage = nil
        }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.setWantsListening(false)
                    if !auto {
                        self.errorMessage = "Accès au micro refusé. Active-le dans Réglages → Taffe → Micro."
                    }
                    return
                }
                self.setWantsListening(true)
                self.requestNotificationPermission()
                self.startWatchdog()
                if self.startEngine() {
                    self.addLog(auto ? "Écoute reprise automatiquement" : "Écoute démarrée")
                } else {
                    self.addLog("Échec du démarrage, nouvel essai automatique")
                }
            }
        }
    }

    func stop() {
        setWantsListening(false)
        stopWatchdog()
        pendingRestart = false
        teardownEngine(deactivateSession: true)
        topLabels = []
        currentScore = 0
        addLog("Écoute arrêtée")
    }

    /// Appelé quand l'app revient au premier plan.
    func appBecameActive() {
        reloadPuffs()
        refreshClipCounts()
        if wantsListening && !engine.isRunning && !pendingRestart {
            scheduleRestart(reason: "retour dans l'app", delay: 0.2)
        }
    }

    private func setWantsListening(_ value: Bool) {
        wantsListening = value
        UserDefaults.standard.set(value, forKey: Keys.wantsListening)
    }

    @discardableResult
    private func startEngine() -> Bool {
        if engine.isRunning {
            engineRunning = true
            return true
        }

        generation += 1
        let currentGeneration = generation

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
            let newObserver = AnalysisObserver(generation: currentGeneration, detector: self)
            try newAnalyzer.add(request, withObserver: newObserver)
            analyzer = newAnalyzer
            observer = newObserver

            let queue = analysisQueue
            let counter = FrameCounter()
            let fallback = self.fallback
            let clips = self.clips
            let gate = self.gate
            let sampleRate = format.sampleRate
            let background = isInBackground
            queue.async {
                fallback.configure(sampleRate: sampleRate)
                clips.configure(sampleRate: sampleRate)
                gate.classifierEnabled = !background
                fallback.countingEnabled = background
            }

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 8192, format: format) { buffer, _ in
                queue.async {
                    if gate.classifierEnabled {
                        newAnalyzer.analyze(buffer, atAudioFramePosition: counter.position)
                        counter.position += AVAudioFramePosition(buffer.frameLength)
                    }
                    fallback.process(buffer)
                    clips.append(buffer)
                }
            }

            engine.prepare()
            try engine.start()
            engineRunning = true
            lastResultDate = Date()
            return true
        } catch {
            addLog("Démarrage impossible : \(error.localizedDescription)")
            teardownEngine(deactivateSession: false)
            return false
        }
    }

    private func teardownEngine(deactivateSession: Bool) {
        generation += 1
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        analyzer?.removeAllRequests()
        analyzer = nil
        observer = nil
        engineRunning = false
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Relance l'écoute après un problème, sans jamais l'abandonner.
    private func scheduleRestart(reason: String, delay: TimeInterval = 0.5) {
        guard wantsListening, !pendingRestart else { return }
        pendingRestart = true

        let now = Date()
        restartTimes = restartTimes.filter { now.timeIntervalSince($0) < 60 }
        restartTimes.append(now)
        let effectiveDelay: TimeInterval = restartTimes.count > 6 ? 15 : delay

        addLog("Relance de l'écoute (\(reason))")
        teardownEngine(deactivateSession: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay) { [weak self] in
            guard let self else { return }
            self.pendingRestart = false
            guard self.wantsListening else { return }
            if self.startEngine() {
                self.restartCount += 1
                self.consecutiveFailures = 0
                self.stoppedAlertSent = false
                self.addLog("Écoute relancée")
            } else {
                self.consecutiveFailures += 1
                if self.consecutiveFailures >= 3 && self.interruptedAt == nil {
                    self.notifyListeningStopped()
                }
            }
        }
    }

    // MARK: - Premier plan / arrière-plan

    @objc private func appDidEnterBackground(_ notification: Notification) {
        isInBackground = true
        applyBackgroundMode(true)
        guard wantsListening else { return }
        if fallbackReady {
            addLog("Arrière-plan : détecteur maison actif")
        } else {
            addLog("Arrière-plan : détecteur maison pas encore entraîné (\(fallbackLearned)/\(FallbackDetector.requiredFrames))")
        }
    }

    @objc private func appWillEnterForeground(_ notification: Notification) {
        isInBackground = false
        applyBackgroundMode(false)
    }

    private func applyBackgroundMode(_ background: Bool) {
        let fallback = self.fallback
        let gate = self.gate
        analysisQueue.async {
            gate.classifierEnabled = !background
            fallback.countingEnabled = background
        }
        lastResultDate = Date()
        if background {
            topLabels = []
            currentScore = 0
        }
    }

    // MARK: - Surveillance

    private func startWatchdog() {
        stopWatchdog()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    private func watchdogTick() {
        guard wantsListening, !pendingRestart else { return }
        if let interruptedAt {
            // Pendant un appel, on attend (5 min max) la fin de l'interruption.
            if Date().timeIntervalSince(interruptedAt) < 300 {
                return
            }
            self.interruptedAt = nil
        }
        if !engine.isRunning {
            scheduleRestart(reason: "moteur audio arrêté")
        } else if !isInBackground && Date().timeIntervalSince(lastResultDate) > 20 {
            scheduleRestart(reason: "plus aucun résultat")
        }
    }

    // MARK: - Événements audio

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        DispatchQueue.main.async {
            switch type {
            case .began:
                self.interruptedAt = Date()
                self.engineRunning = false
                self.addLog("Micro interrompu (appel, Siri…)")
            case .ended:
                self.interruptedAt = nil
                self.scheduleRestart(reason: "fin d'interruption", delay: 0.5)
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
            DispatchQueue.main.async {
                self.scheduleRestart(reason: "changement d'appareil audio")
            }
        default:
            break
        }
    }

    @objc private func handleConfigurationChange(_ notification: Notification) {
        DispatchQueue.main.async {
            self.scheduleRestart(reason: "configuration audio modifiée")
        }
    }

    @objc private func handleMediaReset(_ notification: Notification) {
        DispatchQueue.main.async {
            self.scheduleRestart(reason: "services audio réinitialisés")
        }
    }

    @objc private func handlePuffsChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            self.reloadPuffs()
        }
    }

    // MARK: - Résultats du classifieur d'Apple (app ouverte)

    func handle(top: [LabelScore], scores: [String: Double], generation: Int) {
        guard generation == self.generation, !isInBackground else { return }
        lastResultDate = Date()
        consecutiveFailures = 0
        topLabels = top

        var total = 0.0
        for label in triggerLabels {
            total += scores[label] ?? 0
        }
        currentScore = min(total, 1)

        if isAboveThreshold && !isQuietNow {
            let fallback = self.fallback
            analysisQueue.async {
                fallback.learnFromRecent()
            }
            registerDetection(fromBackground: false)
        }
    }

    func handleFailure(message: String, generation: Int) {
        guard generation == self.generation else { return }
        // En arrière-plan, iOS bloque le classifieur d'Apple : c'est normal,
        // le détecteur maison prend le relais.
        guard !isInBackground else { return }
        addLog("Erreur d'analyse : \(message)")
        scheduleRestart(reason: "erreur d'analyse")
    }

    // MARK: - Taffes

    private func registerDetection(fromBackground: Bool) {
        let now = Date()
        // Une taffe = un bloc de son continu : on ne compte que si le son
        // s'était arrêté depuis au moins `cooldown` secondes.
        if now.timeIntervalSince(lastDetectionDate) >= cooldown {
            puffs = PuffStore.add(at: now)
            lastDetection = now
            reloadWidgets()
            checkDailyLimit()

            let clips = self.clips
            analysisQueue.async {
                clips.lastPuffDate = now
            }

            if fromBackground {
                addLog("Taffe détectée en arrière-plan")
            } else {
                analysisQueue.asyncAfter(deadline: .now() + 1.2) {
                    clips.saveClip(kind: "taffe")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    self?.refreshClipCounts()
                }
                if UIApplication.shared.applicationState == .active {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }
        lastDetectionDate = now
    }

    private func registerBackgroundDetection() {
        guard isInBackground, wantsListening, !isQuietNow else { return }
        registerDetection(fromBackground: true)
    }

    func addPuff() {
        puffs = PuffStore.add()
        addLog("Taffe ajoutée à la main")
        reloadWidgets()
        checkDailyLimit()
    }

    func removeLastPuff() {
        puffs = PuffStore.removeLast()
        addLog("Dernière taffe annulée")
        reloadWidgets()
    }

    func remove(_ date: Date) {
        puffs = PuffStore.remove(date)
        reloadWidgets()
    }

    func clearAll() {
        PuffStore.clear()
        puffs = []
        addLog("Historique effacé")
        reloadWidgets()
    }

    func reloadPuffs() {
        puffs = PuffStore.load()
    }

    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Détecteur d'arrière-plan

    func resetFallbackLearning() {
        let fallback = self.fallback
        analysisQueue.async {
            fallback.resetLearning()
        }
        addLog("Apprentissage d'arrière-plan réinitialisé")
    }

    // MARK: - Échantillons

    func refreshClipCounts() {
        clipTaffes = ClipCollector.count("taffe")
        clipFond = ClipCollector.count("fond")
    }

    func clipFiles() -> [URL] {
        ClipCollector.files("taffe") + ClipCollector.files("fond")
    }

    func deleteClips() {
        ClipCollector.deleteAll()
        refreshClipCounts()
        addLog("Échantillons supprimés")
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkDailyLimit() {
        guard limitAlert, dailyLimit > 0, todayCount == dailyLimit else { return }
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: Keys.lastLimitAlert) != today else { return }
        UserDefaults.standard.set(today, forKey: Keys.lastLimitAlert)
        sendNotification(title: "LIMITE ATTEINTE", body: "\(dailyLimit) taffes aujourd'hui. Tu tiens le coup ?")
    }

    private func notifyListeningStopped() {
        guard !stoppedAlertSent else { return }
        stoppedAlertSent = true
        addLog("Impossible de relancer le micro")
        sendNotification(title: "TAFFE // HORS LIGNE", body: "Le micro s'est arrêté. Ouvre Taffe pour relancer l'écoute.")
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Journal

    func addLog(_ message: String) {
        log.append(LogEntry(id: UUID(), date: Date(), message: message))
        if log.count > 300 {
            log.removeFirst(log.count - 300)
        }
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: Keys.log)
        }
    }

    func clearLog() {
        log = []
        UserDefaults.standard.removeObject(forKey: Keys.log)
    }

    private static func loadLog() -> [LogEntry] {
        guard let data = UserDefaults.standard.data(forKey: Keys.log),
              let entries = try? JSONDecoder().decode([LogEntry].self, from: data) else {
            return []
        }
        return entries
    }

    // MARK: - Export

    func makeCSV() -> URL? {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        var lines = ["date;heure"]
        for puff in puffs {
            lines.append("\(dayFormatter.string(from: puff));\(timeFormatter.string(from: puff))")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("taffes.csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
