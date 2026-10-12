import Foundation
import SwiftData

// 说明：SwiftData 的 PersistentModel 自带 `isDeleted`，所以软删除标记叫 `isRemoved`。
// 子对象（WorkoutExercise / SetEntry / TemplateItem）同步时整体替换，因此 id 不加唯一约束。

@Model
final class Exercise {
    /// 内置动作用稳定的英文 slug，自定义动作用 UUID 字符串
    @Attribute(.unique) var id: String
    var nameZh: String
    var nameEn: String
    var aliases: [String]
    var muscleGroupRaw: String
    var equipmentRaw: String
    var logTypeRaw: String
    var isUnilateral: Bool
    /// 用户可改：是否记录重量
    var tracksWeight: Bool
    /// 用户可改：这个动作上次选的组间休息时长（秒）
    var lastRestSeconds: Int?
    /// 用户可改：表冠调重量的步进（kg）
    var weightStepKg: Double
    var isCustom: Bool
    var isHidden: Bool
    /// 列表排序：内置动作按动作库顺序（常用的在前），自定义动作排在后面
    var sortOrder: Int
    /// 内置动作从未被用户修改过时为 distantPast，同步时会跳过
    var updatedAt: Date
    /// 小写的搜索串：中文名、别名、英文名、拼音、拼音首字母
    var searchKey: String

    init(id: String, nameZh: String, nameEn: String, aliases: [String] = [], muscleGroup: MuscleGroup,
         equipment: Equipment, logType: LogType, isUnilateral: Bool = false, tracksWeight: Bool? = nil,
         lastRestSeconds: Int? = nil, weightStepKg: Double? = nil, isCustom: Bool = false, isHidden: Bool = false,
         sortOrder: Int = 100_000, updatedAt: Date = .distantPast) {
        self.id = id
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.aliases = aliases
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentRaw = equipment.rawValue
        self.logTypeRaw = logType.rawValue
        self.isUnilateral = isUnilateral
        self.tracksWeight = tracksWeight ?? logType.defaultTracksWeight
        self.lastRestSeconds = lastRestSeconds
        self.weightStepKg = weightStepKg ?? equipment.defaultWeightStepKg
        self.isCustom = isCustom
        self.isHidden = isHidden
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
        self.searchKey = ""
        refreshSearchKey()
    }

    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .fullBody }
        set { muscleGroupRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var logType: LogType {
        get { LogType(rawValue: logTypeRaw) ?? .weightReps }
        set { logTypeRaw = newValue.rawValue }
    }

    /// 这一组是否显示重量输入
    var showsWeight: Bool { logType.supportsWeight && tracksWeight }

    func refreshSearchKey() {
        searchKey = SearchIndex.key(nameZh: nameZh, aliases: aliases + equipment.searchAliases + [equipment.displayName], nameEn: nameEn)
    }

    func touch() { updatedAt = .now }
}

@Model
final class Workout {
    @Attribute(.unique) var id: UUID
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
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise]

    init(id: UUID = UUID(), startedAt: Date = .now, title: String = "", templateId: UUID? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.title = title
        self.note = ""
        self.templateId = templateId
        self.updatedAt = .now
        self.isRemoved = false
        self.exercises = []
    }

    var orderedExercises: [WorkoutExercise] { exercises.sorted { $0.order < $1.order } }
    var isActive: Bool { endedAt == nil }
    var duration: TimeInterval { (endedAt ?? .now).timeIntervalSince(startedAt) }

    func touch() { updatedAt = .now }
}

@Model
final class WorkoutExercise {
    var id: UUID
    var order: Int
    var exerciseId: String
    var note: String
    /// 从模板开始时的目标组数，用来显示“2/4 组”
    var targetSets: Int?
    var targetReps: Int?
    var targetWeightKg: Double?
    var workout: Workout?
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.workoutExercise)
    var sets: [SetEntry]

    init(id: UUID = UUID(), order: Int, exerciseId: String, targetSets: Int? = nil, targetReps: Int? = nil, targetWeightKg: Double? = nil) {
        self.id = id
        self.order = order
        self.exerciseId = exerciseId
        self.note = ""
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        self.sets = []
    }

    var orderedSets: [SetEntry] { sets.sorted { $0.order < $1.order } }
    var workingSetCount: Int { sets.filter { !$0.isWarmup }.count }
}

@Model
final class SetEntry {
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
    /// 这一组之后选择的休息时长
    var restSec: Int?
    var prKindsRaw: [String]
    var workoutExercise: WorkoutExercise?

    init(id: UUID = UUID(), order: Int, values: SetValues, completedAt: Date = .now) {
        self.id = id
        self.order = order
        self.weightKg = values.weightKg
        self.reps = values.reps
        self.durationSec = values.durationSec
        self.distanceM = values.distanceM
        self.isWarmup = values.isWarmup
        self.rpe = nil
        self.note = ""
        self.completedAt = completedAt
        self.restSec = nil
        self.prKindsRaw = []
    }

    var values: SetValues {
        get { SetValues(weightKg: weightKg, reps: reps, durationSec: durationSec, distanceM: distanceM, isWarmup: isWarmup) }
        set {
            weightKg = newValue.weightKg
            reps = newValue.reps
            durationSec = newValue.durationSec
            distanceM = newValue.distanceM
            isWarmup = newValue.isWarmup
        }
    }

    var prKinds: [PRKind] {
        get { prKindsRaw.compactMap(PRKind.init(rawValue:)) }
        set { prKindsRaw = newValue.map(\.rawValue) }
    }
}

@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isRemoved: Bool
    @Relationship(deleteRule: .cascade, inverse: \TemplateItem.template)
    var items: [TemplateItem]

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
        self.isRemoved = false
        self.items = []
    }

    var orderedItems: [TemplateItem] { items.sorted { $0.order < $1.order } }

    func touch() { updatedAt = .now }
}

@Model
final class TemplateItem {
    var id: UUID
    var order: Int
    var exerciseId: String
    var targetSets: Int
    var targetReps: Int?
    var targetWeightKg: Double?
    var targetDurationSec: Int?
    var template: WorkoutTemplate?

    init(id: UUID = UUID(), order: Int, exerciseId: String, targetSets: Int = 3, targetReps: Int? = 10,
         targetWeightKg: Double? = nil, targetDurationSec: Int? = nil) {
        self.id = id
        self.order = order
        self.exerciseId = exerciseId
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        self.targetDurationSec = targetDurationSec
    }
}
