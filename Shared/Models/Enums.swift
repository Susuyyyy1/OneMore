import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, forearms, quads, hamstrings, glutes, calves, core, fullBody, cardio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "胸"
        case .back: "背"
        case .shoulders: "肩"
        case .biceps: "二头肌"
        case .triceps: "三头肌"
        case .forearms: "前臂"
        case .quads: "股四头/内收"
        case .hamstrings: "腘绳肌"
        case .glutes: "臀"
        case .calves: "小腿"
        case .core: "核心/腹部"
        case .fullBody: "全身/功能性"
        case .cardio: "有氧"
        }
    }

    /// 用于训练标题，例如“胸 · 三头”
    var shortName: String {
        switch self {
        case .biceps: "二头"
        case .triceps: "三头"
        case .quads: "腿"
        case .hamstrings: "腿"
        case .core: "核心"
        case .fullBody: "全身"
        default: displayName
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell, dumbbell, machine, cable, smith, bodyweight, kettlebell, band, ezBar, cardioMachine, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: "杠铃"
        case .dumbbell: "哑铃"
        case .machine: "固定器械"
        case .cable: "绳索"
        case .smith: "史密斯机"
        case .bodyweight: "自重"
        case .kettlebell: "壶铃"
        case .band: "弹力带"
        case .ezBar: "EZ杆"
        case .cardioMachine: "有氧器械"
        case .other: "其他"
        }
    }

    /// 健身房里的其他叫法，加进搜索关键词
    var searchAliases: [String] {
        switch self {
        case .cable: ["龙门架", "拉力器"]
        case .machine: ["器械"]
        case .smith: ["史密斯"]
        case .ezBar: ["曲杆"]
        case .bodyweight: ["徒手"]
        default: []
        }
    }

    var defaultWeightStepKg: Double {
        switch self {
        case .barbell, .smith, .ezBar: 2.5
        default: 1
        }
    }
}

/// 一组需要记录哪些数据
enum LogType: String, Codable, CaseIterable, Identifiable {
    /// 重量 × 次数（卧推、硬拉）
    case weightReps
    /// 自重 × 次数，可以选择记录附加重量（引体向上）
    case bodyweight
    /// 辅助器械：记录配重（越重越轻松）× 次数
    case assisted
    /// 计时（平板支撑），可以选择记录负重
    case duration
    /// 重量 + 时间（农夫行走）
    case weightDuration
    /// 有氧器械：时长 + 可选距离
    case cardio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weightReps: "重量 × 次数"
        case .bodyweight: "自重 × 次数"
        case .assisted: "辅助配重 × 次数"
        case .duration: "计时"
        case .weightDuration: "重量 + 时间"
        case .cardio: "有氧（时长 + 距离）"
        }
    }

    var usesReps: Bool { self == .weightReps || self == .bodyweight || self == .assisted }
    var usesDuration: Bool { self == .duration || self == .weightDuration || self == .cardio }
    var usesDistance: Bool { self == .cardio }
    /// 能不能记录重量
    var supportsWeight: Bool { self != .cardio }

    /// 新动作默认是否记录重量
    var defaultTracksWeight: Bool { self == .weightReps || self == .assisted || self == .weightDuration }

    var weightLabel: String {
        switch self {
        case .bodyweight, .duration: "附加重量"
        case .assisted: "辅助配重"
        default: "重量"
        }
    }
}

enum PRKind: String, Codable, CaseIterable {
    case maxWeight, e1RM, maxReps, maxDuration

    var displayName: String {
        switch self {
        case .maxWeight: "最大重量"
        case .e1RM: "估算1RM"
        case .maxReps: "最多次数"
        case .maxDuration: "最长时间"
        }
    }
}

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kg, lb

    var id: String { rawValue }
    static let lbPerKg = 2.20462262185

    /// 从 @AppStorage 的原始值读取
    init(raw: String) { self = WeightUnit(rawValue: raw) ?? .kg }

    func fromKg(_ kg: Double) -> Double { self == .kg ? kg : kg * Self.lbPerKg }
    func toKg(_ value: Double) -> Double { self == .kg ? value : value / Self.lbPerKg }

    /// 表冠调节重量时每格的步进（以当前单位计）
    func step(forKgStep kgStep: Double) -> Double {
        switch self {
        case .kg: kgStep
        case .lb: kgStep >= 2.5 ? 5 : 2.5
        }
    }
}
