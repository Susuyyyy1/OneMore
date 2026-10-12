import SwiftData
import SwiftUI

struct ActiveWorkoutView: View {
    @EnvironmentObject private var manager: WorkoutManager
    @EnvironmentObject private var health: HealthSession
    @Query private var exercises: [Exercise]
    @State private var path: [UUID] = []
    @State private var showPicker = false
    @State private var pendingNavigation: UUID?
    @State private var showEndDialog = false

    var body: some View {
        NavigationStack(path: $path) {
            if let workout = manager.workout {
                list(workout)
                    .navigationTitle(workout.title.isEmpty ? "训练中" : workout.title)
                    .warmContainerBackground()
                    .navigationDestination(for: UUID.self) { id in
                        if let we = workout.exercises.first(where: { $0.id == id }) {
                            SetLoggerView(workoutExercise: we)
                        }
                    }
            }
        }
        .sheet(isPresented: $showPicker, onDismiss: {
            if let id = pendingNavigation {
                pendingNavigation = nil
                path.append(id)
            }
        }) {
            ExercisePickerView { exerciseId in
                pendingNavigation = manager.addExercise(exerciseId)?.id
                showPicker = false
            }
        }
        #if DEBUG
        .onAppear {
            // 演示模式：直接打开第一个动作的记组页
            if ["logger", "rest"].contains(DemoData.screen ?? ""), path.isEmpty,
               let first = manager.workout?.orderedExercises.first {
                path = [first.id]
            }
        }
        #endif
        .confirmationDialog(manager.hasAnySet ? "结束训练？" : "还没有记录任何一组", isPresented: $showEndDialog) {
            if manager.hasAnySet {
                Button("结束并保存") { Task { await manager.finish() } }
            }
            Button("放弃本次训练", role: .destructive) { manager.discard() }
            Button("继续训练", role: .cancel) {}
        }
    }

    private func list(_ workout: Workout) -> some View {
        let names = exercises.byId
        return List {
            header(workout)

            RestMiniRow()

            ForEach(workout.orderedExercises) { we in
                NavigationLink(value: we.id) {
                    ExerciseProgressRow(workoutExercise: we, exercise: names[we.exerciseId])
                }
            }
            .onDelete { offsets in
                let ordered = workout.orderedExercises
                offsets.map { ordered[$0] }.forEach(manager.removeExercise)
            }

            Button {
                showPicker = true
            } label: {
                Label("添加动作", systemImage: "plus.circle.fill")
            }
            .listItemTint(Theme.beige.opacity(0.55))

            Button(role: .destructive) {
                showEndDialog = true
            } label: {
                Label(manager.isFinishing ? "正在保存…" : "结束训练", systemImage: "stop.fill")
            }
            .disabled(manager.isFinishing)
        }
    }

    private func header(_ workout: Workout) -> some View {
        HStack {
            Text(workout.startedAt, style: .timer)
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.accent)
            Spacer()
            if health.isRunning {
                VStack(alignment: .trailing, spacing: 0) {
                    Label(health.heartRate > 0 ? "\(Int(health.heartRate))" : "--", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                    Text("\(Int(health.activeKcal)) 千卡")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
        }
        .listRowBackground(Color.clear)
    }
}

struct ExerciseProgressRow: View {
    let workoutExercise: WorkoutExercise
    let exercise: Exercise?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise?.nameZh ?? "未知动作")
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 4) {
                let done = workoutExercise.workingSetCount
                if let target = workoutExercise.targetSets {
                    Text("\(done)/\(target) 组")
                        .foregroundStyle(done >= target ? Theme.accent : .secondary)
                } else {
                    Text(done == 0 ? "未开始" : "\(done) 组")
                        .foregroundStyle(.secondary)
                }
                let warmups = workoutExercise.sets.count - done
                if warmups > 0 {
                    Text("+\(warmups) 热身").foregroundStyle(Theme.warmup)
                }
            }
            .font(.caption2)
        }
    }
}
