import Foundation
import SwiftData

/// 查询某个动作的历史：上次成绩、个人最佳、最近用过的动作
@MainActor
struct HistoryService {
    let context: ModelContext

    /// 某动作在所有有效训练中的记录，按训练开始时间从新到旧
    func sessions(for exerciseId: String, excludingWorkout workoutId: UUID? = nil) -> [WorkoutExercise] {
        let descriptor = FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.exerciseId == exerciseId })
        let all = (try? context.fetch(descriptor)) ?? []
        return all
            .filter { we in
                guard let w = we.workout, !w.isRemoved, !we.sets.isEmpty else { return false }
                return w.id != workoutId
            }
            .sorted { ($0.workout?.startedAt ?? .distantPast) > ($1.workout?.startedAt ?? .distantPast) }
    }

    /// 本次训练之前最近一次做这个动作
    func lastSession(for exerciseId: String, before workout: Workout) -> WorkoutExercise? {
        sessions(for: exerciseId, excludingWorkout: workout.id)
            .first { ($0.workout?.startedAt ?? .distantFuture) < workout.startedAt }
    }

    /// 本次训练开始之前的历史最佳
    func bests(for exercise: Exercise, before workout: Workout) -> PRBests {
        let sets = sessions(for: exercise.id, excludingWorkout: workout.id)
            .filter { ($0.workout?.startedAt ?? .distantFuture) < workout.startedAt }
            .flatMap { $0.sets.map(\.values) }
        return PRCalculator.bests(from: sets, logType: exercise.logType)
    }

    /// 所有历史最佳（动作详情页用）
    func allTimeBests(for exercise: Exercise) -> PRBests {
        let sets = sessions(for: exercise.id).flatMap { $0.sets.map(\.values) }
        return PRCalculator.bests(from: sets, logType: exercise.logType)
    }

    /// 重新给本次训练中该动作的组标记 PR
    func relabelRecords(in we: WorkoutExercise, exercise: Exercise) {
        guard let workout = we.workout else { return }
        let ordered = we.orderedSets
        let labels = PRCalculator.labelRecords(sets: ordered.map(\.values),
                                               history: bests(for: exercise, before: workout),
                                               logType: exercise.logType)
        for (set, kinds) in zip(ordered, labels) where set.prKinds != kinds {
            set.prKinds = kinds
        }
    }

    /// 最近训练里用过的动作 id（去重，按最近排序）
    func recentExerciseIds(limit: Int = 8) -> [String] {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { !$0.isRemoved },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 15
        let workouts = (try? context.fetch(descriptor)) ?? []
        var seen = Set<String>()
        var result: [String] = []
        for w in workouts {
            for we in w.orderedExercises.reversed() where !seen.contains(we.exerciseId) {
                seen.insert(we.exerciseId)
                result.append(we.exerciseId)
                if result.count >= limit { return result }
            }
        }
        return result
    }

    func exercise(id: String) -> Exercise? {
        var d = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// 按动作部位自动生成训练标题，例如 “胸 · 三头”
    static func autoTitle(for workout: Workout, exercises: [String: Exercise]) -> String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for we in workout.orderedExercises {
            guard let ex = exercises[we.exerciseId] else { continue }
            let name = ex.muscleGroup.shortName
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += max(1, we.sets.count)
        }
        // 组数多的部位在前，一样多时按出现顺序
        let top = order.enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
            .map(\.element)
            .prefix(3)
        return top.isEmpty ? "力量训练" : top.joined(separator: " · ")
    }
}

extension Workout {
    var allSetValues: [SetValues] { exercises.flatMap { $0.sets.map(\.values) } }
    var workingSetCount: Int { WorkoutStats.workingSetCount(allSetValues) }
    var volumeKg: Double { WorkoutStats.volumeKg(allSetValues) }
    var prCount: Int { exercises.reduce(0) { $0 + $1.sets.filter { !$0.prKinds.isEmpty }.count } }
}

/// 把动作数组转成按 id 查找的字典
extension Array where Element == Exercise {
    var byId: [String: Exercise] { Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
}
