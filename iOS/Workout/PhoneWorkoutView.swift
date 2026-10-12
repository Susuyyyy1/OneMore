import SwiftData
import SwiftUI

/// 手机上的一次训练：实时记录（训练中）或补录某一天
struct PhoneWorkoutView: View {
    @Bindable var workout: Workout
    let isBackfill: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @State private var path: [UUID] = []
    @State private var showPicker = false
    @State private var pendingNavigation: UUID?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var durationMinutes = 60
    @State private var discardOnClose = false

    private var ops: WorkoutOps { WorkoutOps(context: context) }
    private var hasSets: Bool { workout.exercises.contains { !$0.sets.isEmpty } }

    var body: some View {
        let names = exercises.byId
        NavigationStack(path: $path) {
            PaperList {
                if isBackfill {
                    Section("补录时间") {
                        DatePicker("开始时间", selection: $workout.startedAt, in: ...Date.now)
                        Stepper("训练时长 \(durationMinutes) 分钟", value: $durationMinutes, in: 10...300, step: 5)
                    }
                } else {
                    Section {
                        HStack {
                            Label {
                                Text(workout.startedAt, style: .timer).monospacedDigit()
                            } icon: {
                                Image(systemName: "stopwatch")
                            }
                            .font(.title2.weight(.semibold))
                            Spacer()
                            Text("\(workout.workingSetCount) 组").foregroundStyle(Theme.inkSecondary)
                        }
                        PhoneRestBanner()
                            .listRowBackground(Color.clear)
                    }
                }

                Section("动作") {
                    if workout.exercises.isEmpty {
                        Text("还没有动作，点下面“添加动作”开始").foregroundStyle(Theme.inkSecondary)
                    }
                    ForEach(workout.orderedExercises) { we in
                        NavigationLink(value: we.id) {
                            WorkoutExerciseRow(workoutExercise: we, exercise: names[we.exerciseId])
                        }
                    }
                    .onDelete { offsets in
                        let ordered = workout.orderedExercises
                        offsets.map { ordered[$0] }.forEach(ops.removeExercise)
                    }
                    Button {
                        showPicker = true
                    } label: {
                        Label("添加动作", systemImage: "plus.circle.fill")
                    }
                }

                Section {
                    Button {
                        if hasSets { confirmFinish = true } else { confirmDiscard = true }
                    } label: {
                        Label(isBackfill ? "保存补录" : "结束训练", systemImage: isBackfill ? "checkmark.circle" : "flag.checkered")
                            .font(.headline)
                    }
                    .confirmationDialog(isBackfill ? "保存这次补录？" : "结束这次训练？", isPresented: $confirmFinish, titleVisibility: .visible) {
                        Button(isBackfill ? "保存" : "结束并保存") { finish() }
                        Button("继续", role: .cancel) {}
                    }
                    Button(role: .destructive) {
                        confirmDiscard = true
                    } label: {
                        Label(isBackfill ? "取消补录" : "放弃这次训练", systemImage: "trash")
                    }
                    .confirmationDialog(hasSets ? "确定放弃？已记录的组会被删除" : "还没有记录任何一组，放弃这次训练？",
                                        isPresented: $confirmDiscard, titleVisibility: .visible) {
                        Button("放弃", role: .destructive) { discard() }
                        Button("继续", role: .cancel) {}
                    }
                }
            }
            .navigationTitle(isBackfill ? "补录训练" : "训练中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isBackfill {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("收起") { dismiss() }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let we = workout.exercises.first(where: { $0.id == id }) {
                    PhoneSetLoggerView(workoutExercise: we, isBackfill: isBackfill)
                }
            }
            .sheet(isPresented: $showPicker, onDismiss: {
                if let id = pendingNavigation {
                    pendingNavigation = nil
                    path.append(id)
                }
            }) {
                ExercisePickerSheet { id in
                    pendingNavigation = ops.addExercise(id, to: workout).id
                }
            }
        }
        .interactiveDismissDisabled(isBackfill)
        .onDisappear { if discardOnClose { ops.discard(workout) } }
        .onAppear {
            if isBackfill, let end = workout.endedAt {
                durationMinutes = max(10, Int(end.timeIntervalSince(workout.startedAt) / 60))
            }
        }
    }

    private func finish() {
        let exerciseIds = Set(workout.exercises.map(\.exerciseId))
        if isBackfill {
            ops.finish(workout, at: workout.startedAt.addingTimeInterval(Double(durationMinutes) * 60))
        } else {
            PhoneRestTimer.shared.stop()
            ops.finish(workout)
        }
        // 补录或较早的训练会影响之后训练的“个人最佳”标记
        let affected = ops.relabelSessions(after: workout.startedAt, exerciseIds: exerciseIds)
        let sync = SyncService.shared
        sync.send(workout: workout)
        affected.forEach { sync.send(workout: $0) }
        for id in exerciseIds {
            if let ex = exercises.first(where: { $0.id == id }), ex.updatedAt >= workout.startedAt { sync.send(exercise: ex) }
        }
        dismiss()
    }

    /// 页面关闭后再删除，避免删除正在显示的数据
    private func discard() {
        if !isBackfill { PhoneRestTimer.shared.stop() }
        discardOnClose = true
        dismiss()
    }
}

struct WorkoutExerciseRow: View {
    let workoutExercise: WorkoutExercise
    let exercise: Exercise?
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue

    var body: some View {
        let done = workoutExercise.workingSetCount
        let last = workoutExercise.orderedSets.last
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise?.nameZh ?? "未知动作").font(.headline)
            HStack(spacing: 6) {
                if let target = workoutExercise.targetSets {
                    Text("\(done)/\(target) 组").foregroundStyle(done >= target ? Theme.accent : Theme.inkSecondary)
                } else {
                    Text(done == 0 ? "未开始" : "\(done) 组").foregroundStyle(Theme.inkSecondary)
                }
                if let last, let exercise {
                    Text("· 最近一组 " + Fmt.set(last.values, logType: exercise.logType, unit: WeightUnit(raw: unitRaw)))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .font(.caption)
        }
    }
}

/// 要打开的训练页（实时或补录）
struct WorkoutSheetTarget: Identifiable {
    let workout: Workout
    let isBackfill: Bool
    var id: UUID { workout.id }
}
