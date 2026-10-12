#if DEBUG
import Foundation
import SwiftData

/// 仅调试用：用 `-demo` 启动参数运行时，生成几次示例训练和一个模板（用于截图和检查界面）。
/// 正式安装（install.sh 也是 Debug 构建，但不带启动参数）不会触发。
@MainActor
enum DemoData {
    static func seedIfRequested(context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-demo"),
              ((try? context.fetchCount(FetchDescriptor<Workout>())) ?? 0) == 0 else { return }
        let plans: [(daysAgo: Double, title: String, items: [(String, [SetValues])])] = [
            (12, "胸 · 三头", [("barbell-bench-press", [.init(weightKg: 40, reps: 12, isWarmup: true), .init(weightKg: 60, reps: 10), .init(weightKg: 60, reps: 9), .init(weightKg: 60, reps: 8)]),
                              ("triceps-rope-pushdown", [.init(weightKg: 20, reps: 12), .init(weightKg: 20, reps: 12), .init(weightKg: 22.5, reps: 10)])]),
            (9, "背 · 二头", [("lat-pulldown", [.init(weightKg: 45, reps: 12), .init(weightKg: 50, reps: 10), .init(weightKg: 50, reps: 10)]),
                             ("pull-up", [.init(reps: 8), .init(reps: 7), .init(reps: 6)]),
                             ("dumbbell-curl", [.init(weightKg: 10, reps: 12), .init(weightKg: 12, reps: 10)])]),
            (5, "胸 · 三头", [("barbell-bench-press", [.init(weightKg: 40, reps: 12, isWarmup: true), .init(weightKg: 62.5, reps: 8), .init(weightKg: 62.5, reps: 8), .init(weightKg: 60, reps: 10)]),
                             ("incline-dumbbell-press", [.init(weightKg: 20, reps: 10), .init(weightKg: 20, reps: 10), .init(weightKg: 22, reps: 8)])]),
            (1, "腿", [("barbell-back-squat", [.init(weightKg: 60, reps: 8, isWarmup: true), .init(weightKg: 80, reps: 8), .init(weightKg: 85, reps: 6), .init(weightKg: 85, reps: 6)]),
                      ("leg-press", [.init(weightKg: 120, reps: 12), .init(weightKg: 140, reps: 10)]),
                      ("plank", [.init(durationSec: 60), .init(durationSec: 75)])]),
        ]
        let history = HistoryService(context: context)
        for plan in plans {
            let w = Workout(startedAt: Calendar.current.date(byAdding: .minute, value: -Int(plan.daysAgo * 1440) + 18 * 60, to: .now)!,
                            title: plan.title)
            w.endedAt = w.startedAt.addingTimeInterval(55 * 60)
            w.avgHeartRate = 118
            w.activeKcal = 260
            context.insert(w)
            for (i, item) in plan.items.enumerated() {
                let we = WorkoutExercise(order: i, exerciseId: item.0)
                context.insert(we)
                we.workout = w
                for (j, v) in item.1.enumerated() {
                    let s = SetEntry(order: j, values: v, completedAt: w.startedAt.addingTimeInterval(Double(i * 900 + j * 180)))
                    s.restSec = 120
                    context.insert(s)
                    s.workoutExercise = we
                }
                if let ex = history.exercise(id: item.0) { history.relabelRecords(in: we, exercise: ex) }
            }
        }
        let template = WorkoutTemplate(name: "胸 + 三头日")
        context.insert(template)
        for (i, id) in ["barbell-bench-press", "incline-dumbbell-press", "cable-crossover", "triceps-rope-pushdown"].enumerated() {
            let item = TemplateItem(order: i, exerciseId: id, targetSets: i == 0 ? 4 : 3, targetReps: i == 0 ? 8 : 12,
                                    targetWeightKg: i == 0 ? 62.5 : nil)
            context.insert(item)
            item.template = template
        }
        try? context.save()
    }

    /// 演示用的页面（手表截图用）：-demoScreen home / active / logger / rest / summary
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
#endif
