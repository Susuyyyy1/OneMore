import Foundation

/// 设置项存放在 UserDefaults，界面里用 @AppStorage(SettingsKey.xxx) 读写。
/// iPhone 修改后通过 WatchConnectivity 的 applicationContext 同步到手表。
enum SettingsKey {
    static let unit = "unit"
    static let restPresets = "restPresets"
    static let defaultRest = "defaultRest"
    static let restWarning = "restWarning"

    static let all = [unit, restPresets, defaultRest, restWarning]
}

enum AppSettings {
    static let defaultPresets = [60, 90, 120, 180, 300]

    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.unit: WeightUnit.kg.rawValue,
            SettingsKey.restPresets: encodePresets(defaultPresets),
            SettingsKey.defaultRest: 120,
            SettingsKey.restWarning: true,
        ])
    }

    static var unit: WeightUnit {
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: SettingsKey.unit) ?? "") ?? .kg
    }

    static var restPresets: [Int] {
        decodePresets(UserDefaults.standard.string(forKey: SettingsKey.restPresets) ?? "")
    }

    static var defaultRest: Int {
        let v = UserDefaults.standard.integer(forKey: SettingsKey.defaultRest)
        return v > 0 ? v : 120
    }

    static var restWarning: Bool { UserDefaults.standard.bool(forKey: SettingsKey.restWarning) }

    static func encodePresets(_ presets: [Int]) -> String {
        presets.map(String.init).joined(separator: ",")
    }

    static func decodePresets(_ text: String) -> [Int] {
        let values = text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 }
        let unique = Array(Set(values)).sorted()
        return unique.isEmpty ? defaultPresets : unique
    }

    /// 同步用：导出所有设置
    static func snapshot() -> [String: String] {
        var dict: [String: String] = [:]
        let d = UserDefaults.standard
        dict[SettingsKey.unit] = unit.rawValue
        dict[SettingsKey.restPresets] = encodePresets(restPresets)
        dict[SettingsKey.defaultRest] = String(defaultRest)
        dict[SettingsKey.restWarning] = d.bool(forKey: SettingsKey.restWarning) ? "1" : "0"
        return dict
    }

    static func apply(_ dict: [String: String]) {
        let d = UserDefaults.standard
        if let v = dict[SettingsKey.unit], WeightUnit(rawValue: v) != nil { d.set(v, forKey: SettingsKey.unit) }
        if let v = dict[SettingsKey.restPresets] { d.set(encodePresets(decodePresets(v)), forKey: SettingsKey.restPresets) }
        if let v = dict[SettingsKey.defaultRest], let i = Int(v), i > 0 { d.set(i, forKey: SettingsKey.defaultRest) }
        if let v = dict[SettingsKey.restWarning] { d.set(v == "1", forKey: SettingsKey.restWarning) }
    }
}
