import Foundation

// 同步和备份用的 Codable 结构。以“聚合”为单位：一次训练连同它的动作和组一起传。

struct SetDTO: Codable, Equatable {
    var id: UUID
    var order: Int
    var weightKg: Double?
    var reps: Int?
    var durationSec: Int?
    var distanceM: Double?
    var isWarmup: Bool
    var rpe: Double?
    var note: String
    var completedAt: Date
    var restSec: Int?
    var prKinds: [String]
    /// 递减组的后续各段；旧版本的数据没有这个字段
    var drops: [DropStage]?
}

struct WorkoutExerciseDTO: Codable, Equatable {
    var id: UUID
    var order: Int
    var exerciseId: String
    var note: String
    var targetSets: Int?
    var targetReps: Int?
    var targetWeightKg: Double?
    var sets: [SetDTO]
}

struct WorkoutDTO: Codable, Equatable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var title: String
    var note: String
    var templateId: UUID?
    var hkWorkoutUUID: UUID?
    var avgHeartRate: Double?
    var activeKcal: Double?
    var updatedAt: Date
    var isRemoved: Bool
    var exercises: [WorkoutExerciseDTO]
}

struct TemplateItemDTO: Codable, Equatable {
    var id: UUID
    var order: Int
    var exerciseId: String
    var targetSets: Int
    var targetReps: Int?
    var targetWeightKg: Double?
    var targetDurationSec: Int?
}

struct TemplateDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isRemoved: Bool
    var items: [TemplateItemDTO]
}

struct ExerciseDTO: Codable, Equatable {
    var id: String
    var nameZh: String
    var nameEn: String
    var aliases: [String]
    var muscleGroup: String
    var equipment: String
    var logType: String
    var isUnilateral: Bool
    var tracksWeight: Bool
    var lastRestSeconds: Int?
    var weightStepKg: Double
    var isCustom: Bool
    var isHidden: Bool
    var updatedAt: Date
}

/// 全量数据：用于 JSON 备份/恢复，以及手表与 iPhone 的首次全量同步
struct BackupFile: Codable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var exportedAt: Date = .now
    var exercises: [ExerciseDTO]
    var workouts: [WorkoutDTO]
    var templates: [TemplateDTO]
    var settings: [String: String]?
}

enum DTOCoding {
    // 日期用毫秒时间戳，保证“后写者胜”比较时精度足够
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}
