import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { !$0.isRemoved && $0.endedAt != nil },
           sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]
    /// 手机上正在进行的训练（手表上的训练结束后才会同步过来）
    @Query(filter: #Predicate<Workout> { !$0.isRemoved && $0.endedAt == nil },
           sort: \Workout.startedAt, order: .reverse)
    private var activeWorkouts: [Workout]
    @Query(filter: #Predicate<WorkoutTemplate> { !$0.isRemoved }, sort: \WorkoutTemplate.updatedAt, order: .reverse)
    private var templates: [WorkoutTemplate]
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @State private var sheetTarget: WorkoutSheetTarget?

    private struct MonthGroup: Identifiable {
        let id: String
        let workouts: [Workout]
    }

    private var groups: [MonthGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: workouts) { w in
            let c = cal.dateComponents([.year, .month], from: w.startedAt)
            return "\(c.year ?? 0)年\(c.month ?? 0)月"
        }
        return grouped
            .map { MonthGroup(id: $0.key, workouts: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { ($0.workouts.first?.startedAt ?? .distantPast) > ($1.workouts.first?.startedAt ?? .distantPast) }
    }

    private var ops: WorkoutOps { WorkoutOps(context: context) }

    var body: some View {
        let unit = WeightUnit(raw: unitRaw)
        NavigationStack {
            Group {
                if workouts.isEmpty && activeWorkouts.isEmpty {
                    ContentUnavailableView {
                        Label("还没有训练记录", systemImage: "figure.strengthtraining.traditional")
                    } description: {
                        Text("在 Apple Watch 或这里开始一次训练，记录会出现在这里。")
                    } actions: {
                        Button("开始训练") { startLive(template: nil) }.beigeGlassButton()
                    }
                } else {
                    PaperList {
                        if let active = activeWorkouts.first {
                            Section {
                                Button {
                                    sheetTarget = WorkoutSheetTarget(workout: active, isBackfill: false)
                                } label: {
                                    HStack {
                                        Image(systemName: "figure.strengthtraining.traditional")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("训练进行中，点此继续").font(.headline)
                                            Text("已进行 \(Text(active.startedAt, style: .relative))")
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(Theme.inkSecondary)
                                    }
                                    .foregroundStyle(Theme.ink)
                                }
                            }
                        }
                        Section {
                            TrainingHeatmap(workouts: workouts, unit: unit) { day in startBackfill(on: day) }
                            WeekSummary(workouts: workouts, unit: unit)
                        } footer: {
                            Text("长按热力图上的某一天，可以补录那天的训练。")
                        }
                        ForEach(groups) { group in
                            Section(group.id) {
                                ForEach(group.workouts) { w in
                                    NavigationLink(value: w.id) { HistoryRow(workout: w, unit: unit) }
                                }
                            }
                        }
                    }
                }
            }
            .background(PaperBackground())
            .navigationTitle("训练记录")
            .navigationDestination(for: UUID.self) { id in
                if let w = workouts.first(where: { $0.id == id }) {
                    PhoneWorkoutDetailView(workout: w)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(activeWorkouts.isEmpty ? "开始训练" : "继续当前训练", systemImage: "play.fill") {
                            startLive(template: nil)
                        }
                        if !templates.isEmpty && activeWorkouts.isEmpty {
                            Menu("从模板开始", systemImage: "rectangle.stack") {
                                ForEach(templates) { t in
                                    Button(t.name) { startLive(template: t) }
                                }
                            }
                        }
                        Button("补录训练", systemImage: "calendar.badge.plus") { startBackfill(on: .now) }
                    } label: {
                        Label("新训练", systemImage: "plus")
                    }
                }
            }
            .fullScreenCover(item: $sheetTarget) { target in
                PhoneWorkoutView(workout: target.workout, isBackfill: target.isBackfill)
            }
            .onAppear(perform: removeEmptyWorkouts)
        }
    }

    /// 补录时 app 被关掉可能留下空记录（没有任何动作），回到列表时清理掉
    private func removeEmptyWorkouts() {
        guard sheetTarget == nil else { return }
        let empty = workouts.filter { $0.exercises.isEmpty }
        guard !empty.isEmpty else { return }
        empty.forEach(context.delete)
        ops.save()
    }

    /// 开始实时训练；已有进行中的训练时直接打开它
    private func startLive(template: WorkoutTemplate?) {
        if let active = activeWorkouts.first {
            sheetTarget = WorkoutSheetTarget(workout: active, isBackfill: false)
            return
        }
        sheetTarget = WorkoutSheetTarget(workout: ops.startWorkout(template: template), isBackfill: false)
    }

    /// 补录某一天：默认当天 18:00、时长 1 小时（今天的话改成一小时前），进入后可以修改
    private func startBackfill(on day: Date) {
        let cal = Calendar.current
        var start = cal.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        if start > .now { start = max(cal.startOfDay(for: .now), Date().addingTimeInterval(-3600)) }
        let w = ops.startWorkout(at: start)
        w.endedAt = start.addingTimeInterval(3600)
        ops.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        sheetTarget = WorkoutSheetTarget(workout: w, isBackfill: true)
    }
}

private struct WeekSummary: View {
    let workouts: [Workout]
    let unit: WeightUnit

    var body: some View {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let week = workouts.filter { $0.startedAt >= start }
        HStack {
            stat("本周训练", "\(week.count)次")
            stat("正式组", "\(week.reduce(0) { $0 + $1.workingSetCount })组")
            stat("总容量", Fmt.volume(week.reduce(0) { $0 + $1.volumeKg }, unit: unit))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryRow: View {
    let workout: Workout
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.title.isEmpty ? "力量训练" : workout.title).font(.headline)
                Spacer()
                if workout.prCount > 0 {
                    Label("\(workout.prCount)", systemImage: "trophy.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.gold)
                }
            }
            Text("\(workout.startedAt.formatted(.dateTime.month().day().weekday().hour().minute())) · \(Fmt.durationText(workout.duration))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(workout.exercises.count)个动作 · \(workout.workingSetCount)组 · \(Fmt.volume(workout.volumeKg, unit: unit))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct PhoneWorkoutDetailView: View {
    @Bindable var workout: Workout

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @State private var editing: SetEditTarget?
    @State private var confirmDelete = false
    @State private var templateSaved = false
    @State private var originalText = ""

    var body: some View {
        let unit = WeightUnit(raw: unitRaw)
        let names = exercises.byId
        PaperList {
            Section {
                LabeledContent("开始", value: workout.startedAt.formatted(.dateTime.year().month().day().hour().minute()))
                LabeledContent("时长", value: Fmt.durationText(workout.duration))
                LabeledContent("动作 / 正式组", value: "\(workout.exercises.count) / \(workout.workingSetCount)")
                LabeledContent("总容量", value: Fmt.volume(workout.volumeKg, unit: unit))
                if let hr = workout.avgHeartRate { LabeledContent("平均心率", value: "\(Int(hr)) 次/分") }
                if let kcal = workout.activeKcal { LabeledContent("活动千卡", value: "\(Int(kcal))") }
            }

            Section("标题与备注") {
                TextField("标题", text: $workout.title)
                TextField("备注", text: $workout.note, axis: .vertical)
            }

            ForEach(workout.orderedExercises) { we in
                let ex = names[we.exerciseId]
                Section {
                    ForEach(Array(we.orderedSets.enumerated()), id: \.element.id) { i, s in
                        Button {
                            if let ex { editing = SetEditTarget(entry: s, workoutExercise: we, exercise: ex) }
                        } label: {
                            PhoneSetRow(index: i + 1, set: s, logType: ex?.logType ?? .weightReps, unit: unit)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in deleteSets(offsets, in: we, exercise: ex) }
                    if let ex {
                        Button {
                            addSet(to: we, exercise: ex)
                        } label: {
                            Label("补记一组", systemImage: "plus")
                        }
                    }
                } header: {
                    HStack {
                        Text(ex?.nameZh ?? "未知动作")
                        Spacer()
                        Text("\(we.workingSetCount)组")
                    }
                }
            }

            Section {
                Button {
                    saveAsTemplate(names: names)
                } label: {
                    Label(templateSaved ? "已存为模板" : "存为模板", systemImage: "rectangle.stack.badge.plus")
                }
                .disabled(templateSaved)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("删除这次训练", systemImage: "trash")
                }
            }
        }
        .navigationTitle(workout.title.isEmpty ? "训练" : workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            PhoneSetEditView(target: target) { Commit.workout(workout, in: context) }
        }
        .confirmationDialog("删除后手表上的这条记录也会删除", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                workout.isRemoved = true
                Commit.workout(workout, in: context)
                dismiss()
            }
        }
        .onAppear { originalText = workout.title + "\u{1}" + workout.note }
        .onDisappear {
            if !workout.isRemoved, workout.title + "\u{1}" + workout.note != originalText {
                Commit.workout(workout, in: context)
            }
        }
    }

    private func deleteSets(_ offsets: IndexSet, in we: WorkoutExercise, exercise: Exercise?) {
        let ordered = we.orderedSets
        for i in offsets { context.delete(ordered[i]) }
        Commit.save(context)
        if let exercise { HistoryService(context: context).relabelRecords(in: we, exercise: exercise) }
        Commit.workout(workout, in: context)
    }

    private func addSet(to we: WorkoutExercise, exercise: Exercise) {
        var values = we.orderedSets.last?.values
            ?? Prefill.defaults(logType: exercise.logType, equipment: exercise.equipment)
        values.isWarmup = false
        let set = SetEntry(order: (we.sets.map(\.order).max() ?? -1) + 1, values: values,
                           completedAt: we.orderedSets.last?.completedAt ?? workout.startedAt)
        context.insert(set)
        set.workoutExercise = we
        HistoryService(context: context).relabelRecords(in: we, exercise: exercise)
        Commit.workout(workout, in: context)
        editing = SetEditTarget(entry: set, workoutExercise: we, exercise: exercise)
    }

    private func saveAsTemplate(names: [String: Exercise]) {
        let t = WorkoutTemplate(name: workout.title.isEmpty ? "我的模板" : workout.title)
        context.insert(t)
        for (i, we) in workout.orderedExercises.enumerated() {
            let working = we.orderedSets.filter { !$0.isWarmup }
            let last = working.last ?? we.orderedSets.last
            let item = TemplateItem(order: i, exerciseId: we.exerciseId, targetSets: max(1, working.count),
                                    targetReps: last?.reps, targetWeightKg: last?.values.loadKg,
                                    targetDurationSec: last?.durationSec)
            context.insert(item)
            item.template = t
        }
        Commit.template(t, in: context)
        templateSaved = true
    }
}

struct PhoneSetRow: View {
    let index: Int
    let set: SetEntry
    let logType: LogType
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 10) {
            Text(set.isWarmup ? "热身" : "\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(set.isWarmup ? Theme.warmup : Theme.inkSecondary)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.set(set.values, logType: logType, unit: unit))
                    .font(.body.monospacedDigit())
                let extras = [set.rpe.map(Fmt.rpe), set.restSec.map { "休息 \(Fmt.clock($0))" }, set.note.isEmpty ? nil : set.note]
                    .compactMap { $0 }
                if !extras.isEmpty {
                    Text(extras.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !set.prKinds.isEmpty {
                Label(set.prKinds.map(\.displayName).joined(separator: "、"), systemImage: "trophy.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.gold)
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}

struct SetEditTarget: Identifiable {
    var id: UUID { entry.id }
    let entry: SetEntry
    let workoutExercise: WorkoutExercise
    let exercise: Exercise
}

/// 在 iPhone 上编辑一组
struct PhoneSetEditView: View {
    let target: SetEditTarget
    let onSave: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @State private var weight: Double?
    @State private var reps = 10
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var distanceKm: Double?
    @State private var isWarmup = false
    @State private var rpe: Double = 0
    @State private var note = ""

    var body: some View {
        let unit = WeightUnit(raw: unitRaw)
        let ex = target.exercise
        NavigationStack {
            PaperForm {
                Section(ex.nameZh) {
                    if ex.logType.supportsWeight {
                        LabeledContent("\(ex.logType.weightLabel)（\(unit.rawValue)）") {
                            TextField("不记录", value: $weight, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if ex.logType.usesReps {
                        Stepper(value: $reps, in: 0...300) {
                            LabeledContent(ex.isUnilateral ? "次数（每侧）" : "次数", value: "\(reps)")
                        }
                    }
                    if ex.logType.usesDuration {
                        HStack {
                            Text("时间")
                            Spacer()
                            Picker("分", selection: $minutes) { ForEach(0..<240) { Text("\($0) 分").tag($0) } }
                                .labelsHidden()
                            Picker("秒", selection: $seconds) { ForEach(0..<60) { Text("\($0) 秒").tag($0) } }
                                .labelsHidden()
                        }
                    }
                    if ex.logType.usesDistance {
                        LabeledContent("距离（km）") {
                            TextField("不记录", value: $distanceKm, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Toggle("热身组", isOn: $isWarmup)
                }
                Section {
                    Picker("主观强度 RPE", selection: $rpe) {
                        Text("不记录").tag(0.0)
                        ForEach(stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }, id: \.self) {
                            Text(Fmt.number($0)).tag($0)
                        }
                    }
                    TextField("备注", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("编辑这一组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save(unit: unit) } }
            }
        }
        .onAppear { load(unit: unit) }
    }

    private func load(unit: WeightUnit) {
        let s = target.entry
        weight = s.weightKg.map { (unit.fromKg($0) * 100).rounded() / 100 }
        reps = s.reps ?? 10
        minutes = (s.durationSec ?? 0) / 60
        seconds = (s.durationSec ?? 0) % 60
        distanceKm = s.distanceM.map { $0 / 1000 }
        isWarmup = s.isWarmup
        rpe = s.rpe ?? 0
        note = s.note
    }

    private func save(unit: WeightUnit) {
        let ex = target.exercise
        var v = SetValues(isWarmup: isWarmup)
        if ex.logType.supportsWeight, let weight, weight > 0 { v.weightKg = unit.toKg(weight) }
        if ex.logType.usesReps { v.reps = reps }
        if ex.logType.usesDuration { v.durationSec = minutes * 60 + seconds }
        if ex.logType.usesDistance, let distanceKm, distanceKm > 0 { v.distanceM = distanceKm * 1000 }
        target.entry.values = v
        target.entry.rpe = rpe > 0 ? rpe : nil
        target.entry.note = note
        HistoryService(context: context).relabelRecords(in: target.workoutExercise, exercise: ex)
        onSave()
        dismiss()
    }
}
