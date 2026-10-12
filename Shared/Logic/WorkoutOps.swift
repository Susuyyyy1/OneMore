import Foundation
import SwiftData

/// 训练记录的增删改，手表和 iPhone 共用同一套逻辑。
/// 只负责修改数据并保存；同步、触感、健康会话由调用方处理。
@MainActor
struct WorkoutOps {
    let context: ModelContext

    private var history: HistoryService { HistoryService(context: context) }

    // MARK: 训练

    /// 新建一次训练（可从模板开始，可指定开始时间用于补录）
    func startWorkout(template: WorkoutTemplate? = nil, at date: Date = .now) -> Workout {
        let w = Workout(startedAt: date, title: template?.name ?? "", templateId: template?.id)
        context.insert(w)
        if let template {
            for (i, item) in template.orderedItems.enumerated() {
                let we = WorkoutExercise(order: i, exerciseId: item.exerciseId, targetSets: item.targetSets,
                                         targetReps: item.targetReps, targetWeightKg: item.targetWeightKg)
                context.insert(we)
                we.workout = w
            }
        }
        save()
        return w
    }

    /// 结束训练：去掉没有记组的动作，写入结束时间，没有标题时按部位自动生成
    func finish(_ w: Workout, at end: Date = .now) {
        // 先从关系里移除再删除，否则下面生成标题时还会算上这些空动作
        let empty = w.exercises.filter { $0.sets.isEmpty }
        w.exercises.removeAll { $0.sets.isEmpty }
        empty.forEach(context.delete)
        w.endedAt = end
        if w.title.isEmpty {
            let exercises = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).byId
            w.title = HistoryService.autoTitle(for: w, exercises: exercises)
        }
        w.touch()
        save()
    }

    /// 放弃训练：直接删除
    func discard(_ w: Workout) {
        context.delete(w)
        save()
    }

    // MARK: 动作

    /// 添加动作；本次训练已经有这个动作时直接返回已有的那一项
    @discardableResult
    func addExercise(_ exerciseId: String, to w: Workout) -> WorkoutExercise {
        if let existing = w.exercises.first(where: { $0.exerciseId == exerciseId }) { return existing }
        let we = WorkoutExercise(order: (w.exercises.map(\.order).max() ?? -1) + 1, exerciseId: exerciseId)
        context.insert(we)
        we.workout = w
        w.touch()
        save()
        return we
    }

    func removeExercise(_ we: WorkoutExercise) {
        let w = we.workout
        context.delete(we)
        w?.touch()
        save()
    }

    // MARK: 组

    /// 记录一组，返回新的一组和打破的纪录
    @discardableResult
    func logSet(_ values: SetValues, in we: WorkoutExercise, exercise: Exercise,
                at date: Date = .now) -> (set: SetEntry, records: [PRKind]) {
        var running = PRBests()
        if let w = we.workout { running = history.bests(for: exercise, before: w) }
        for s in we.orderedSets where PRCalculator.counts(s.values, logType: exercise.logType) {
            PRCalculator.merge(s.values, logType: exercise.logType, into: &running)
        }
        let records = PRCalculator.newRecords(for: values, against: running, logType: exercise.logType)

        let set = SetEntry(order: (we.sets.map(\.order).max() ?? -1) + 1, values: values, completedAt: date)
        set.prKinds = records
        context.insert(set)
        set.workoutExercise = we
        we.workout?.touch()
        save()
        return (set, records)
    }

    func update(_ set: SetEntry, values: SetValues, rpe: Double?, note: String, in we: WorkoutExercise, exercise: Exercise) {
        set.values = values
        set.rpe = rpe
        set.note = note
        history.relabelRecords(in: we, exercise: exercise)
        we.workout?.touch()
        save()
    }

    func delete(_ set: SetEntry, in we: WorkoutExercise, exercise: Exercise) {
        context.delete(set)
        save()
        history.relabelRecords(in: we, exercise: exercise)
        we.workout?.touch()
        save()
    }

    /// 记住这个动作的休息时长，并记在刚完成的那一组上
    func recordRest(seconds: Int, exercise: Exercise, after set: SetEntry?) {
        if exercise.lastRestSeconds != seconds {
            exercise.lastRestSeconds = seconds
            exercise.touch()
        }
        set?.restSec = seconds
        save()
    }

    // MARK: 个人最佳

    /// 补录或修改了较早的训练后，重新标记之后各次训练里这些动作的个人最佳。返回标记有变化的训练（需要同步）。
    func relabelSessions(after date: Date, exerciseIds: Set<String>) -> [Workout] {
        var changed: [UUID: Workout] = [:]
        for id in exerciseIds {
            guard let exercise = history.exercise(id: id) else { continue }
            for we in history.sessions(for: id) {
                guard let w = we.workout, w.startedAt > date else { continue }
                let before = we.orderedSets.map(\.prKindsRaw)
                history.relabelRecords(in: we, exercise: exercise)
                if we.orderedSets.map(\.prKindsRaw) != before {
                    w.touch()
                    changed[w.id] = w
                }
            }
        }
        save()
        return Array(changed.values)
    }

    // MARK: 模板

    /// 把一次训练存成模板：目标组数 = 正式组数，目标次数/重量 = 最后一组正式组
    @discardableResult
    func saveAsTemplate(_ w: Workout, name: String) -> WorkoutTemplate {
        let t = WorkoutTemplate(name: name)
        context.insert(t)
        for (i, we) in w.orderedExercises.enumerated() {
            let working = we.orderedSets.filter { !$0.isWarmup }
            let last = working.last ?? we.orderedSets.last
            let item = TemplateItem(order: i, exerciseId: we.exerciseId, targetSets: max(1, working.count),
                                    targetReps: last?.reps, targetWeightKg: last?.values.loadKg,
                                    targetDurationSec: last?.durationSec)
            context.insert(item)
            item.template = t
        }
        save()
        return t
    }

    func save() {
        do { try context.save() } catch { print("保存失败：\(error)") }
    }
}
