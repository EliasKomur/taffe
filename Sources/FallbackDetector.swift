import Foundation
import Accelerate
import AVFoundation

/// Détecteur maison (FFT sur processeur) utilisé quand l'app est en arrière-plan :
/// depuis iOS 18, le classifieur d'Apple ne peut plus tourner hors de l'écran.
/// Il apprend « l'empreinte » de ta vape pendant que l'app est ouverte,
/// à partir des taffes détectées par Apple.
/// Toutes les méthodes sont appelées sur la file d'analyse.
final class FallbackDetector {
    static let bandCount = 24
    static let fftSize = 2048
    static let requiredFrames = 40

    private struct FrameInfo {
        let time: TimeInterval
        let shape: [Double]
        let flatness: Double
        let level: Double
        var learned: Bool
    }

    private enum Keys {
        static let template = "fallbackTemplate"
        static let flatness = "fallbackFlatness"
        static let frames = "fallbackFrames"
    }

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var pending: [Float] = []
    private var bandEdges: [Int] = []
    private var frameDuration: Double = Double(FallbackDetector.fftSize) / 48000

    private var template: [Double]
    private var templateFlatness: Double
    private(set) var learnedFrames: Int

    private var noiseFloor: Double = -60
    private var recent: [FrameInfo] = []
    private var activeRun = 0
    private var silentRun = 0
    private var inEvent = false
    private var statusTick = 0

    var similarityThreshold: Double = 0.85
    var marginDB: Double = 8
    var countingEnabled = false

    var onPuff: (() -> Void)?
    var onStatus: ((_ similarity: Double, _ levelAboveFloor: Double) -> Void)?
    var onLearned: ((_ frames: Int) -> Void)?

    var isReady: Bool {
        learnedFrames >= FallbackDetector.requiredFrames && template.count == FallbackDetector.bandCount
    }

    init() {
        let size = FallbackDetector.fftSize
        let log2nValue = vDSP_Length(log2(Double(size)))
        log2n = log2nValue
        fftSetup = vDSP_create_fftsetup(log2nValue, FFTRadix(kFFTRadix2))!

        var hann = [Float](repeating: 0, count: size)
        vDSP_hann_window(&hann, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        window = hann

        let defaults = UserDefaults.standard
        var loadedTemplate = defaults.array(forKey: Keys.template) as? [Double] ?? []
        var loadedFrames = defaults.integer(forKey: Keys.frames)
        if loadedTemplate.count != FallbackDetector.bandCount {
            loadedTemplate = []
            loadedFrames = 0
        }
        template = loadedTemplate
        templateFlatness = defaults.double(forKey: Keys.flatness)
        learnedFrames = loadedFrames
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Configuration

    func configure(sampleRate: Double) {
        pending.removeAll()
        recent.removeAll()
        activeRun = 0
        silentRun = 0
        inEvent = false
        frameDuration = Double(FallbackDetector.fftSize) / sampleRate

        let binWidth = sampleRate / Double(FallbackDetector.fftSize)
        let low = 150.0
        let high = min(8000.0, sampleRate / 2 * 0.95)
        let maxBin = FallbackDetector.fftSize / 2 - 1
        var edges: [Int] = []
        for index in 0...FallbackDetector.bandCount {
            let frequency = low * pow(high / low, Double(index) / Double(FallbackDetector.bandCount))
            var bin = Int(frequency / binWidth)
            if let last = edges.last, bin <= last {
                bin = last + 1
            }
            edges.append(min(bin, maxBin))
        }
        bandEdges = edges
    }

    func resetLearning() {
        template = []
        templateFlatness = 0
        learnedFrames = 0
        save()
        onLearned?(0)
    }

    // MARK: - Traitement audio

    func process(_ buffer: AVAudioPCMBuffer) {
        guard !bandEdges.isEmpty, let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        pending.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        let size = FallbackDetector.fftSize
        while pending.count >= size {
            let frame = Array(pending[0..<size])
            pending.removeFirst(size)
            analyze(frame)
        }
    }

    private func analyze(_ frame: [Float]) {
        let n = FallbackDetector.fftSize
        let half = n / 2

        // Volume du bloc
        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(n))
        let level = 20 * log10(Double(max(rms, 1e-7)))

        // Bruit de fond : descend tout de suite, remonte lentement
        if level < noiseFloor {
            noiseFloor = level
        } else {
            noiseFloor += min(0.03, level - noiseFloor)
        }

        // Spectre
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(n))
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        let setup = fftSetup
        let log2n = self.log2n
        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { windowedPointer in
                    windowedPointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }

        // Énergie par bande (en dB), puis « forme » indépendante du volume
        var bands = [Double](repeating: 0, count: FallbackDetector.bandCount)
        for band in 0..<FallbackDetector.bandCount {
            let start = bandEdges[band]
            let end = max(bandEdges[band + 1], start + 1)
            var sum: Float = 0
            for bin in start..<end {
                sum += power[bin]
            }
            bands[band] = 10 * log10(Double(sum) / Double(end - start) + 1e-12)
        }
        let mean = bands.reduce(0, +) / Double(bands.count)
        var shape = bands.map { $0 - mean }
        let norm = sqrt(shape.reduce(0) { $0 + $1 * $1 })
        if norm > 1e-9 {
            shape = shape.map { $0 / norm }
        }

        // Platitude spectrale : élevée pour un souffle, basse pour la voix
        let first = bandEdges[0]
        let last = bandEdges[FallbackDetector.bandCount]
        var logSum = 0.0
        var linearSum = 0.0
        for bin in first..<last {
            let value = Double(power[bin]) + 1e-12
            logSum += log(value)
            linearSum += value
        }
        let binCount = Double(max(last - first, 1))
        let flatness = exp(logSum / binCount) / (linearSum / binCount)

        let above = level - noiseFloor
        recent.append(FrameInfo(time: Date().timeIntervalSince1970,
                                shape: shape,
                                flatness: flatness,
                                level: above,
                                learned: false))
        if recent.count > 80 {
            recent.removeFirst(recent.count - 80)
        }

        let similarity = isReady ? cosine(shape, template) : 0

        statusTick += 1
        if statusTick >= 6 {
            statusTick = 0
            onStatus?(similarity, above)
        }

        guard countingEnabled, isReady else {
            activeRun = 0
            silentRun = 0
            inEvent = false
            return
        }

        let active = above >= marginDB
            && similarity >= similarityThreshold
            && flatness >= templateFlatness * 0.5

        let minActiveFrames = max(2, Int((0.35 / frameDuration).rounded(.up)))
        let resetFrames = max(2, Int((0.3 / frameDuration).rounded(.up)))

        if active {
            activeRun += 1
            silentRun = 0
        } else {
            silentRun += 1
            if silentRun >= resetFrames {
                activeRun = 0
                inEvent = false
            }
        }

        if !inEvent && activeRun >= minActiveFrames {
            inEvent = true
            onPuff?()
        }
    }

    // MARK: - Apprentissage

    /// Appelé quand Apple confirme une taffe (app ouverte) : on mémorise
    /// l'empreinte des derniers blocs bruyants.
    func learnFromRecent() {
        let now = Date().timeIntervalSince1970
        var changed = false
        for index in recent.indices {
            let frame = recent[index]
            guard !frame.learned, now - frame.time < 1.5, frame.level >= 6 else { continue }
            recent[index].learned = true
            learnedFrames += 1
            if template.count != FallbackDetector.bandCount {
                template = frame.shape
                templateFlatness = frame.flatness
            } else {
                let weight = 1.0 / Double(min(learnedFrames, 300))
                for band in 0..<template.count {
                    template[band] += weight * (frame.shape[band] - template[band])
                }
                templateFlatness += weight * (frame.flatness - templateFlatness)
            }
            changed = true
        }
        guard changed else { return }
        let norm = sqrt(template.reduce(0) { $0 + $1 * $1 })
        if norm > 1e-9 {
            template = template.map { $0 / norm }
        }
        save()
        onLearned?(learnedFrames)
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0
        var normA = 0.0
        var normB = 0.0
        for index in 0..<a.count {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 1e-9 ? dot / denominator : 0
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(template, forKey: Keys.template)
        defaults.set(templateFlatness, forKey: Keys.flatness)
        defaults.set(learnedFrames, forKey: Keys.frames)
    }
}

/// Garde les 3 dernières secondes de son et enregistre des échantillons
/// (taffes confirmées + bruit de fond) pour pouvoir entraîner plus tard
/// un vrai modèle sur ta vape, sans rien enregistrer à la main.
/// Toutes les méthodes sont appelées sur la file d'analyse.
final class ClipCollector {
    static let maxClipsPerKind = 150

    private var ring: [Float] = []
    private var capacity = 48000 * 3
    private var sampleRate: Double = 48000
    private var lastBackgroundClip = Date()
    var lastPuffDate = Date.distantPast

    func configure(sampleRate: Double) {
        self.sampleRate = sampleRate
        capacity = Int(sampleRate * 3)
        ring.removeAll()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        ring.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        if ring.count > capacity {
            ring.removeFirst(ring.count - capacity)
        }

        // Un échantillon de « fond » toutes les 4 minutes, loin de toute taffe.
        let now = Date()
        if now.timeIntervalSince(lastBackgroundClip) > 240 && now.timeIntervalSince(lastPuffDate) > 30 {
            lastBackgroundClip = now
            saveClip(kind: "fond")
        }
    }

    func saveClip(kind: String) {
        guard ring.count > Int(sampleRate) else { return }
        let samples = ring
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in 0..<samples.count {
            channel[index] = samples[index]
        }

        let directory = ClipCollector.directory(kind)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(kind)_\(Int(Date().timeIntervalSince1970 * 1000)).caf"
        let url = directory.appendingPathComponent(name)
        do {
            let file = try AVAudioFile(forWriting: url,
                                       settings: format.settings,
                                       commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            try file.write(from: buffer)
        } catch {
            return
        }
        ClipCollector.prune(directory)
    }

    static func directory(_ kind: String) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("echantillons").appendingPathComponent(kind)
    }

    static func files(_ kind: String) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory(kind),
                                                                 includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "caf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func count(_ kind: String) -> Int {
        files(kind).count
    }

    static func deleteAll() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("echantillons"))
    }

    private static func prune(_ directory: URL) {
        let urls = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if urls.count > maxClipsPerKind {
            for url in urls.prefix(urls.count - maxClipsPerKind) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
