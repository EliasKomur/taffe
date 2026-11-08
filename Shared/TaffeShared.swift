import Foundation

// MARK: - Stockage partagé entre l'app et le widget

enum TaffeShared {
    static let defaultGroupID = "group.com.eliaskomur.taffe"

    /// SideStore / AltStore écrivent l'identifiant réel du groupe dans la clé ALTAppGroups.
    static let groupID: String = {
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
           let first = groups.first,
           !first.isEmpty {
            return first
        }
        return defaultGroupID
    }()

    /// Vrai si l'app et le widget partagent bien un conteneur commun.
    static let hasGroupContainer: Bool =
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil

    static let defaults: UserDefaults = {
        if hasGroupContainer, let shared = UserDefaults(suiteName: groupID) {
            return shared
        }
        return UserDefaults.standard
    }()

    static let puffsChanged = Notification.Name("TaffePuffsChanged")
}

enum SharedKeys {
    static let puffs = "puffs"
    static let theme = "theme"
    static let dailyLimit = "dailyLimit"
    static let migrated = "migratedToSharedStore"
}

struct DayCount: Identifiable {
    let day: Date
    let count: Int
    var id: Date { day }
}

struct HourCount: Identifiable {
    let hour: Int
    let count: Int
    var id: Int { hour }
}

// MARK: - Taffes

enum PuffStore {

    static func load() -> [Date] {
        let raw = TaffeShared.defaults.array(forKey: SharedKeys.puffs) as? [Double] ?? []
        return raw.sorted().map { Date(timeIntervalSince1970: $0) }
    }

    static func save(_ puffs: [Date]) {
        let raw = puffs.map { $0.timeIntervalSince1970 }.sorted()
        TaffeShared.defaults.set(raw, forKey: SharedKeys.puffs)
    }

    @discardableResult
    static func add(at date: Date = Date()) -> [Date] {
        var puffs = load()
        puffs.append(date)
        puffs.sort()
        save(puffs)
        return puffs
    }

    @discardableResult
    static func remove(_ date: Date) -> [Date] {
        var puffs = load()
        if let index = puffs.lastIndex(where: { abs($0.timeIntervalSince(date)) < 0.001 }) {
            puffs.remove(at: index)
        }
        save(puffs)
        return puffs
    }

    @discardableResult
    static func removeLast() -> [Date] {
        var puffs = load()
        if !puffs.isEmpty {
            puffs.removeLast()
        }
        save(puffs)
        return puffs
    }

    static func clear() {
        save([])
    }

    static func count(in puffs: [Date], on day: Date = Date()) -> Int {
        let calendar = Calendar.current
        var total = 0
        for puff in puffs where calendar.isDate(puff, inSameDayAs: day) {
            total += 1
        }
        return total
    }

    static func dailyCounts(in puffs: [Date], days: Int, endingOn end: Date = Date()) -> [DayCount] {
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: end)
        var buckets: [Date: Int] = [:]
        for puff in puffs {
            buckets[calendar.startOfDay(for: puff), default: 0] += 1
        }
        var result: [DayCount] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: lastDay) {
                result.append(DayCount(day: day, count: buckets[day] ?? 0))
            }
        }
        return result
    }

    static func hourlyCounts(in puffs: [Date], on day: Date = Date()) -> [HourCount] {
        let calendar = Calendar.current
        var buckets = Array(repeating: 0, count: 24)
        for puff in puffs where calendar.isDate(puff, inSameDayAs: day) {
            let hour = calendar.component(.hour, from: puff)
            if hour >= 0 && hour < 24 {
                buckets[hour] += 1
            }
        }
        var result: [HourCount] = []
        for hour in 0..<24 {
            result.append(HourCount(hour: hour, count: buckets[hour]))
        }
        return result
    }

    static var dailyLimit: Int {
        TaffeShared.defaults.integer(forKey: SharedKeys.dailyLimit)
    }

    /// Copie les données des versions précédentes vers le stockage partagé avec le widget.
    static func migrateIfNeeded() {
        let shared = TaffeShared.defaults
        let standard = UserDefaults.standard
        guard shared !== standard else { return }
        guard !shared.bool(forKey: SharedKeys.migrated) else { return }

        let old = standard.array(forKey: SharedKeys.puffs) as? [Double] ?? []
        let current = shared.array(forKey: SharedKeys.puffs) as? [Double] ?? []
        if !old.isEmpty {
            let merged = Array(Set(old + current)).sorted()
            shared.set(merged, forKey: SharedKeys.puffs)
        }
        for key in [SharedKeys.theme, SharedKeys.dailyLimit] {
            if shared.object(forKey: key) == nil, let value = standard.object(forKey: key) {
                shared.set(value, forKey: key)
            }
        }
        shared.set(true, forKey: SharedKeys.migrated)
    }
}
