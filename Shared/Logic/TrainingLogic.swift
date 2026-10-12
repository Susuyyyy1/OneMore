import Foundation

/// 一组的数值（与存储无关，方便测试）
struct SetValues: Equatable, Codable {
    var weightKg: Double?
    var reps: Int?
    var durationSec: Int?
    var distanceM: Double?
    var isWarmup: Bool = false

    /// 有效的负重（0 视为没有负重）
    var loadKg: Double? {
        guard let w = weightKg, w > 0 else { return nil }
        return w
    }
}

// MARK: - 个人最佳

struct PRBests: Equatable {
    var maxWeight: Double?
    var maxE1RM: Double?
    var maxReps: Int?
    var maxDuration: Int?

    var isEmpty: Bool { maxWeight == nil && maxE1RM == nil && maxReps == nil && maxDuration == nil }
}

enum PRCalculator {
    /// Epley 公式估算 1RM，只对 1–12 次有意义
    static func e1RM(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, (1...12).contains(reps) else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }

    static func counts(_ set: SetValues, logType: LogType) -> Bool {
        !set.isWarmup && logType != .assisted && logType != .cardio
    }

    /// 从历史组里算出各项最佳。热身组、辅助器械、有氧不参与。
    static func bests(from sets: [SetValues], logType: LogType) -> PRBests {
        var b = PRBests()
        for s in sets where counts(s, logType: logType) {
            merge(s, logType: logType, into: &b)
        }
        return b
    }

    static func merge(_ s: SetValues, logType: LogType, into b: inout PRBests) {
        if let load = s.loadKg {
            b.maxWeight = max(b.maxWeight ?? 0, load)
            if logType.usesReps, let reps = s.reps, let e = e1RM(weightKg: load, reps: reps) {
                b.maxE1RM = max(b.maxE1RM ?? 0, e)
            }
        } else if logType.usesReps, let reps = s.reps, reps > 0 {
            b.maxReps = max(b.maxReps ?? 0, reps)
        } else if logType.usesDuration, let d = s.durationSec, d > 0 {
            b.maxDuration = max(b.maxDuration ?? 0, d)
        }
    }

    /// 这一组打破了哪些纪录。第一次做某个维度时不算纪录，避免第一组就弹提示。
    static func newRecords(for s: SetValues, against b: PRBests, logType: LogType) -> [PRKind] {
        guard counts(s, logType: logType) else { return [] }
        var kinds: [PRKind] = []
        if let load = s.loadKg {
            if let best = b.maxWeight, load > best + 0.001 { kinds.append(.maxWeight) }
            if logType.usesReps, let reps = s.reps, let e = e1RM(weightKg: load, reps: reps),
               let best = b.maxE1RM, e > best + 0.001 {
                kinds.append(.e1RM)
            }
        } else if logType.usesReps, let reps = s.reps {
            if let best = b.maxReps, reps > best { kinds.append(.maxReps) }
        } else if logType.usesDuration, let d = s.durationSec {
            if let best = b.maxDuration, d > best { kinds.append(.maxDuration) }
        }
        return kinds
    }

    /// 按顺序给一个动作本次的所有组重新标记 PR（编辑或删除组之后调用）
    static func labelRecords(sets: [SetValues], history: PRBests, logType: LogType) -> [[PRKind]] {
        var running = history
        return sets.map { s in
            let kinds = newRecords(for: s, against: running, logType: logType)
            if counts(s, logType: logType) { merge(s, logType: logType, into: &running) }
            return kinds
        }
    }
}

// MARK: - 预填

enum Prefill {
    struct Target: Equatable {
        var reps: Int?
        var weightKg: Double?
        var durationSec: Int?
    }

    /// 预填下一组：本次上一组 → 上次训练同序号的组 → 模板目标 → 默认值
    static func next(current: [SetValues], previousSession: [SetValues], target: Target?,
                     logType: LogType, equipment: Equipment) -> SetValues {
        if var last = current.last {
            last.isWarmup = false
            return last
        }
        let index = current.count
        if !previousSession.isEmpty {
            var v = index < previousSession.count ? previousSession[index] : previousSession[previousSession.count - 1]
            v.isWarmup = false
            return v
        }
        var v = defaults(logType: logType, equipment: equipment)
        if let t = target {
            if let r = t.reps, logType.usesReps { v.reps = r }
            if let w = t.weightKg { v.weightKg = w }
            if let d = t.durationSec, logType.usesDuration { v.durationSec = d }
        }
        return v
    }

    static func defaults(logType: LogType, equipment: Equipment) -> SetValues {
        var v = SetValues()
        switch logType {
        case .weightReps, .assisted:
            v.weightKg = equipment == .barbell ? 20 : 10
            v.reps = 10
        case .bodyweight:
            v.reps = 10
        case .duration:
            v.durationSec = 60
        case .weightDuration:
            v.weightKg = 20
            v.durationSec = 60
        case .cardio:
            v.durationSec = 600
        }
        return v
    }
}

// MARK: - 统计

enum WorkoutStats {
    static func workingSetCount(_ sets: [SetValues]) -> Int { sets.filter { !$0.isWarmup }.count }

    /// 总容量 = Σ 重量 × 次数（不含热身组）
    static func volumeKg(_ sets: [SetValues]) -> Double {
        sets.reduce(0) { sum, s in
            guard !s.isWarmup, let w = s.loadKg, let r = s.reps else { return sum }
            return sum + w * Double(r)
        }
    }
}

// MARK: - 格式化

enum Fmt {
    static func number(_ value: Double, maxFraction: Int = 1) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = maxFraction
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func weight(_ kg: Double, unit: WeightUnit) -> String {
        number(unit.fromKg(kg)) + unit.rawValue
    }

    static func volume(_ kg: Double, unit: WeightUnit) -> String {
        let v = unit.fromKg(kg)
        let f = NumberFormatter()
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        return (f.string(from: NSNumber(value: v)) ?? "\(Int(v))") + unit.rawValue
    }

    /// 1:30、12:05、1:02:03
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 训练时长：45分钟、1小时12分
    static func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)分钟" }
        return "\(minutes / 60)小时\(minutes % 60)分"
    }

    static func distance(_ meters: Double) -> String {
        meters >= 1000 ? number(meters / 1000, maxFraction: 2) + "km" : number(meters, maxFraction: 0) + "m"
    }

    /// 一组的简短描述，例如 “60kg × 10”、“× 12”、“+10kg × 8”、“1:00”、“20:00 · 3.5km”
    static func set(_ v: SetValues, logType: LogType, unit: WeightUnit) -> String {
        var parts: [String] = []
        let load = v.loadKg
        switch logType {
        case .weightReps:
            if let load { parts.append(weight(load, unit: unit)) }
            if let r = v.reps { parts.append("× \(r)") }
            return parts.joined(separator: " ")
        case .bodyweight:
            if let load { parts.append("+" + weight(load, unit: unit)) }
            if let r = v.reps { parts.append("× \(r)") }
            return parts.joined(separator: " ")
        case .assisted:
            if let load { parts.append("辅助" + weight(load, unit: unit)) }
            if let r = v.reps { parts.append("× \(r)") }
            return parts.joined(separator: " ")
        case .duration, .weightDuration:
            if let load { parts.append(weight(load, unit: unit)) }
            if let d = v.durationSec { parts.append(clock(d)) }
            return parts.joined(separator: " · ")
        case .cardio:
            if let d = v.durationSec { parts.append(clock(d)) }
            if let m = v.distanceM, m > 0 { parts.append(distance(m)) }
            return parts.joined(separator: " · ")
        }
    }

    static func rpe(_ value: Double) -> String { "RPE " + number(value) }
}
