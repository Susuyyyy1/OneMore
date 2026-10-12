import Foundation
import SwiftData
import WatchKit

/// 当前训练的状态和所有修改操作。每次修改都立即保存，app 崩溃也不会丢数据。
@MainActor
final class WorkoutManager: ObservableObject {
    static let shared = WorkoutManager()

    @Published private(set) var workout: Workout?
    /// 刚结束的训练，用于显示总结页
    @Published var finishedWorkout: Workout?
    @Published private(set) var isFinishing = false

    private var context: ModelContext { Persistence.shared.mainContext }
    private var ops: WorkoutOps { WorkoutOps(context: context) }

    // MARK: 开始 / 恢复

    /// 启动时找回未结束的训练（例如 app 被系统结束后重新打开）
    func restoreActiveWorkout() {
        guard workout == nil else { return }
        var d = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.endedAt == nil && !$0.isRemoved },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        d.fetchLimit = 1
        guard let active = try? context.fetch(d).first else { return }
        // 超过 12 小时的未结束训练视为忘记结束，直接收尾
        if active.startedAt.timeIntervalSinceNow < -12 * 3600 {
            close(active, health: nil)
            return
        }
        workout = active
        Task {
            let health = HealthSession.shared
            await health.recover()
            // 系统没有可恢复的会话（例如 app 被强制关闭过）：重新开始一个，心率和卡路里接着记
            if !health.isRunning { await health.start(at: active.startedAt) }
        }
    }

    func start(template: WorkoutTemplate? = nil) {
        guard workout == nil else { return }
        let w = ops.startWorkout(template: template)
        workout = w
        WKInterfaceDevice.current().play(.start)
        Task { await HealthSession.shared.start(at: w.startedAt) }
    }

    // MARK: 动作

    /// 添加动作；如果本次训练已经有这个动作，直接返回已有的那一项
    @discardableResult
    func addExercise(_ exerciseId: String) -> WorkoutExercise? {
        guard let workout else { return nil }
        return ops.addExercise(exerciseId, to: workout)
    }

    func removeExercise(_ we: WorkoutExercise) {
        ops.removeExercise(we)
    }

    // MARK: 组

    /// 记录一组，返回打破的纪录
    @discardableResult
    func logSet(_ values: SetValues, in we: WorkoutExercise, exercise: Exercise) -> [PRKind] {
        guard workout != nil else { return [] }
        let kinds = ops.logSet(values, in: we, exercise: exercise).records

        WKInterfaceDevice.current().play(.success)
        if !kinds.isEmpty {
            // 破纪录时再震一次
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                WKInterfaceDevice.current().play(.success)
            }
        }
        return kinds
    }

    func update(_ set: SetEntry, values: SetValues, rpe: Double?, note: String, in we: WorkoutExercise, exercise: Exercise) {
        ops.update(set, values: values, rpe: rpe, note: note, in: we, exercise: exercise)
        syncIfFinished(we.workout)
    }

    func delete(_ set: SetEntry, in we: WorkoutExercise, exercise: Exercise) {
        let workout = we.workout
        ops.delete(set, in: we, exercise: exercise)
        syncIfFinished(workout)
    }

    /// 开始休息：记住这个动作的休息时长，并记在刚完成的那一组上
    func startRest(seconds: Int, exercise: Exercise, after set: SetEntry?) {
        ops.recordRest(seconds: seconds, exercise: exercise, after: set)
        RestTimer.shared.start(seconds: seconds, exerciseId: exercise.id)
    }

    // MARK: 结束

    var hasAnySet: Bool { workout?.exercises.contains { !$0.sets.isEmpty } ?? false }

    func finish() async {
        guard let w = workout, !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }
        RestTimer.shared.stop()
        let result = await HealthSession.shared.end()
        close(w, health: result)
        workout = nil
        finishedWorkout = w
    }

    /// 放弃本次训练：不保存记录，也不写入健康
    func discard() {
        guard let w = workout else { return }
        RestTimer.shared.stop()
        HealthSession.shared.discard()
        ops.discard(w)
        workout = nil
    }

    private func close(_ w: Workout, health: HealthSession.Result?) {
        if let health {
            w.hkWorkoutUUID = health.workoutUUID
            w.avgHeartRate = health.avgHeartRate
            w.activeKcal = health.activeKcal
        }
        ops.finish(w)
        let exercises = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).byId

        let sync = SyncService.shared
        sync.send(workout: w)
        // 本次训练中改过休息时长等设置的动作也同步过去
        for we in w.exercises {
            if let ex = exercises[we.exerciseId], ex.updatedAt >= w.startedAt { sync.send(exercise: ex) }
        }
    }

    // MARK: 总结页操作

    func updateNote(_ w: Workout, note: String) {
        w.note = note
        w.touch()
        save()
        SyncService.shared.send(workout: w)
    }

    /// 把一次训练存成模板：目标组数 = 正式组数，目标次数/重量 = 最后一组正式组
    @discardableResult
    func saveAsTemplate(_ w: Workout, name: String) -> WorkoutTemplate {
        let t = ops.saveAsTemplate(w, name: name)
        SyncService.shared.send(template: t)
        return t
    }

    private func syncIfFinished(_ w: Workout?) {
        guard let w, w.endedAt != nil else { return }
        SyncService.shared.send(workout: w)
    }

    private func save() { ops.save() }

    #if DEBUG
    /// 演示模式：开一个已经练了一会儿的训练（不启动健康会话），用于截图
    func startDemoWorkout() {
        guard workout == nil else { return }
        let history = HistoryService(context: context)
        let w = ops.startWorkout(at: Date().addingTimeInterval(-24 * 60))
        let plan: [(String, [SetValues])] = [
            ("barbell-bench-press", [SetValues(weightKg: 40, reps: 12, isWarmup: true), SetValues(weightKg: 62.5, reps: 8),
                                     SetValues(weightKg: 62.5, reps: 8)]),
            ("incline-dumbbell-press", [SetValues(weightKg: 22, reps: 10)]),
            ("triceps-rope-pushdown", []),
        ]
        for (id, sets) in plan {
            let we = ops.addExercise(id, to: w)
            guard let ex = history.exercise(id: id) else { continue }
            for (i, v) in sets.enumerated() {
                ops.logSet(v, in: we, exercise: ex, at: w.startedAt.addingTimeInterval(Double(i + 1) * 150))
            }
        }
        workout = w
    }
    #endif
}
