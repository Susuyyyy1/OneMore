import Foundation
import SwiftData

/// SwiftData 模型与 DTO 互转，以及“后写者胜”的合并
@MainActor
struct DataStore {
    let context: ModelContext

    // MARK: 导出

    func dto(_ w: Workout) -> WorkoutDTO {
        WorkoutDTO(
            id: w.id, startedAt: w.startedAt, endedAt: w.endedAt, title: w.title, note: w.note,
            templateId: w.templateId, hkWorkoutUUID: w.hkWorkoutUUID, avgHeartRate: w.avgHeartRate,
            activeKcal: w.activeKcal, updatedAt: w.updatedAt, isRemoved: w.isRemoved,
            exercises: w.orderedExercises.map { we in
                WorkoutExerciseDTO(
                    id: we.id, order: we.order, exerciseId: we.exerciseId, note: we.note,
                    targetSets: we.targetSets, targetReps: we.targetReps, targetWeightKg: we.targetWeightKg,
                    sets: we.orderedSets.map { s in
                        SetDTO(id: s.id, order: s.order, weightKg: s.weightKg, reps: s.reps, durationSec: s.durationSec,
                               distanceM: s.distanceM, isWarmup: s.isWarmup, rpe: s.rpe, note: s.note,
                               completedAt: s.completedAt, restSec: s.restSec, prKinds: s.prKindsRaw)
                    })
            })
    }

    func dto(_ t: WorkoutTemplate) -> TemplateDTO {
        TemplateDTO(id: t.id, name: t.name, createdAt: t.createdAt, updatedAt: t.updatedAt, isRemoved: t.isRemoved,
                    items: t.orderedItems.map {
                        TemplateItemDTO(id: $0.id, order: $0.order, exerciseId: $0.exerciseId, targetSets: $0.targetSets,
                                        targetReps: $0.targetReps, targetWeightKg: $0.targetWeightKg,
                                        targetDurationSec: $0.targetDurationSec)
                    })
    }

    func dto(_ e: Exercise) -> ExerciseDTO {
        ExerciseDTO(id: e.id, nameZh: e.nameZh, nameEn: e.nameEn, aliases: e.aliases, muscleGroup: e.muscleGroupRaw,
                    equipment: e.equipmentRaw, logType: e.logTypeRaw, isUnilateral: e.isUnilateral,
                    tracksWeight: e.tracksWeight, lastRestSeconds: e.lastRestSeconds, weightStepKg: e.weightStepKg,
                    isCustom: e.isCustom, isHidden: e.isHidden, updatedAt: e.updatedAt)
    }

    /// 全量导出。内置且从未修改过的动作不导出（双方都有）。
    func backup(includeSettings: Bool = true) -> BackupFile {
        let exercises = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? [])
            .filter { $0.isCustom || $0.updatedAt > .distantPast }
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt != nil }))) ?? []
        let templates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        return BackupFile(exercises: exercises.map(dto), workouts: workouts.map(dto), templates: templates.map(dto),
                          settings: includeSettings ? AppSettings.snapshot() : nil)
    }

    // MARK: 合并（后写者胜）

    static func shouldApply(incoming: Date, existing: Date?) -> Bool {
        guard let existing else { return true }
        return incoming > existing
    }

    @discardableResult
    func apply(_ d: WorkoutDTO) -> Bool {
        let id = d.id
        var fd = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        fd.fetchLimit = 1
        let existing = try? context.fetch(fd).first
        guard Self.shouldApply(incoming: d.updatedAt, existing: existing?.updatedAt) else { return false }
        // 正在进行中的训练以手表本地为准
        if let existing, existing.isActive, d.endedAt == nil { return false }

        let w = existing ?? Workout(id: d.id, startedAt: d.startedAt)
        if existing == nil { context.insert(w) }
        w.startedAt = d.startedAt
        w.endedAt = d.endedAt
        w.title = d.title
        w.note = d.note
        w.templateId = d.templateId
        w.hkWorkoutUUID = d.hkWorkoutUUID
        w.avgHeartRate = d.avgHeartRate
        w.activeKcal = d.activeKcal
        w.isRemoved = d.isRemoved

        for old in w.exercises { context.delete(old) }
        w.exercises = []
        for ed in d.exercises {
            let we = WorkoutExercise(id: ed.id, order: ed.order, exerciseId: ed.exerciseId, targetSets: ed.targetSets,
                                     targetReps: ed.targetReps, targetWeightKg: ed.targetWeightKg)
            we.note = ed.note
            context.insert(we)
            we.workout = w
            for sd in ed.sets {
                let s = SetEntry(id: sd.id, order: sd.order,
                                 values: SetValues(weightKg: sd.weightKg, reps: sd.reps, durationSec: sd.durationSec,
                                                   distanceM: sd.distanceM, isWarmup: sd.isWarmup),
                                 completedAt: sd.completedAt)
                s.rpe = sd.rpe
                s.note = sd.note
                s.restSec = sd.restSec
                s.prKindsRaw = sd.prKinds
                context.insert(s)
                s.workoutExercise = we
            }
        }
        w.updatedAt = d.updatedAt
        return true
    }

    @discardableResult
    func apply(_ d: TemplateDTO) -> Bool {
        let id = d.id
        var fd = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == id })
        fd.fetchLimit = 1
        let existing = try? context.fetch(fd).first
        guard Self.shouldApply(incoming: d.updatedAt, existing: existing?.updatedAt) else { return false }

        let t = existing ?? WorkoutTemplate(id: d.id, name: d.name)
        if existing == nil { context.insert(t) }
        t.name = d.name
        t.createdAt = d.createdAt
        t.isRemoved = d.isRemoved
        for old in t.items { context.delete(old) }
        t.items = []
        for i in d.items {
            let item = TemplateItem(id: i.id, order: i.order, exerciseId: i.exerciseId, targetSets: i.targetSets,
                                    targetReps: i.targetReps, targetWeightKg: i.targetWeightKg,
                                    targetDurationSec: i.targetDurationSec)
            context.insert(item)
            item.template = t
        }
        t.updatedAt = d.updatedAt
        return true
    }

    @discardableResult
    func apply(_ d: ExerciseDTO) -> Bool {
        let id = d.id
        var fd = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        fd.fetchLimit = 1
        let existing = try? context.fetch(fd).first
        guard Self.shouldApply(incoming: d.updatedAt, existing: existing?.updatedAt) else { return false }

        let group = MuscleGroup(rawValue: d.muscleGroup) ?? .fullBody
        let equipment = Equipment(rawValue: d.equipment) ?? .other
        let logType = LogType(rawValue: d.logType) ?? .weightReps
        let e: Exercise
        if let existing {
            e = existing
        } else {
            e = Exercise(id: d.id, nameZh: d.nameZh, nameEn: d.nameEn, muscleGroup: group, equipment: equipment, logType: logType)
            context.insert(e)
        }
        // 内置动作的名称、分类以本机动作库为准；自定义动作全部字段都同步
        if d.isCustom || existing == nil {
            e.nameZh = d.nameZh
            e.nameEn = d.nameEn
            e.aliases = d.aliases
            e.muscleGroup = group
            e.equipment = equipment
            e.logType = logType
            e.isUnilateral = d.isUnilateral
            e.isCustom = d.isCustom
        }
        e.tracksWeight = d.tracksWeight
        e.lastRestSeconds = d.lastRestSeconds
        e.weightStepKg = d.weightStepKg
        e.isHidden = d.isHidden
        e.refreshSearchKey()
        e.updatedAt = d.updatedAt
        return true
    }

    /// 合并整个备份文件，返回实际更新的条数
    @discardableResult
    func apply(_ file: BackupFile, applySettings: Bool) -> Int {
        var changed = 0
        for e in file.exercises where apply(e) { changed += 1 }
        for t in file.templates where apply(t) { changed += 1 }
        for w in file.workouts where apply(w) { changed += 1 }
        if applySettings, let s = file.settings { AppSettings.apply(s) }
        try? context.save()
        return changed
    }
}
