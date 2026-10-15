import SwiftData
import SwiftUI

/// 输入框里的数值（重量以当前单位显示）
struct SetInput: Equatable {
    var weight: Double = 0
    var reps: Double = 10
    var duration: Double = 60
    var distanceKm: Double = 0
    /// 递减组的后续各段（重量以当前单位显示）
    var drops: [Drop] = []

    struct Drop: Equatable, Identifiable {
        var id = UUID()
        var weight: Double
        var reps: Double
    }

    init() {}

    init(_ v: SetValues, unit: WeightUnit) {
        weight = (unit.fromKg(v.weightKg ?? 0) * 10).rounded() / 10
        reps = Double(v.reps ?? 10)
        duration = Double(v.durationSec ?? 60)
        distanceKm = (v.distanceM ?? 0) / 1000
        drops = v.drops.map { Drop(weight: (unit.fromKg($0.weightKg ?? 0) * 10).rounded() / 10, reps: Double($0.reps ?? 10)) }
    }

    static func supportsDrops(_ ex: Exercise) -> Bool { ex.showsWeight && ex.logType.usesReps }

    func values(for ex: Exercise, unit: WeightUnit, isWarmup: Bool) -> SetValues {
        var v = SetValues(isWarmup: isWarmup)
        if ex.showsWeight, weight > 0 { v.weightKg = unit.toKg(weight) }
        if ex.logType.usesReps { v.reps = Int(reps.rounded()) }
        if ex.logType.usesDuration { v.durationSec = Int(duration.rounded()) }
        if ex.logType.usesDistance, distanceKm > 0 { v.distanceM = distanceKm * 1000 }
        if Self.supportsDrops(ex) {
            v.drops = drops.map { DropStage(weightKg: $0.weight > 0 ? unit.toKg($0.weight) : nil, reps: Int($0.reps.rounded())) }
        }
        return v
    }

    /// 加一段递减：重量减半（对齐到步进），次数与上一段相同
    mutating func addDrop(step: Double) {
        let lastWeight = drops.last?.weight ?? weight
        let lastReps = drops.last?.reps ?? reps
        let half = max(step, ((lastWeight / 2) / step).rounded() * step)
        drops.append(Drop(weight: min(half, lastWeight), reps: lastReps))
    }
}

enum InputField: Hashable {
    case weight, reps, duration, distance
    case dropWeight(UUID), dropReps(UUID)
}

/// 输入区：根据动作类型显示重量 / 次数 / 时间 / 距离
struct SetInputFields: View {
    let exercise: Exercise
    let unit: WeightUnit
    @Binding var input: SetInput
    var focus: FocusState<InputField?>.Binding

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if exercise.showsWeight {
                    CrownField(title: "\(exercise.logType.weightLabel) \(unit.rawValue)", value: $input.weight,
                               step: unit.step(forKgStep: exercise.weightStepKg), range: 0...999,
                               format: { Fmt.number($0, maxFraction: 2) }, focus: focus, field: .weight)
                }
                if exercise.logType.usesReps {
                    CrownField(title: exercise.isUnilateral ? "次数(每侧)" : "次数", value: $input.reps,
                               step: 1, range: 0...300, format: { "\(Int($0.rounded()))" }, focus: focus, field: .reps)
                }
                if exercise.logType.usesDuration {
                    CrownField(title: exercise.isUnilateral ? "时间(每侧)" : "时间", value: $input.duration,
                               step: exercise.logType == .cardio ? 60 : 5, range: 0...(4 * 3600),
                               format: { Fmt.clock(Int($0.rounded())) }, focus: focus, field: .duration)
                }
            }
            if exercise.logType.usesDistance {
                CrownField(title: "距离 km（可不填）", value: $input.distanceKm, step: 0.1, range: 0...100,
                           format: { $0 > 0 ? Fmt.number($0, maxFraction: 1) : "—" }, focus: focus, field: .distance)
            }
            if SetInput.supportsDrops(exercise) {
                dropRows
            }
        }
    }

    /// 递减组：每一段一行（重量、次数、删除），下面一个“＋”按钮再加一段
    @ViewBuilder
    private var dropRows: some View {
        let step = unit.step(forKgStep: exercise.weightStepKg)
        ForEach($input.drops) { $d in
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.right.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                CrownField(title: "递减 \(unit.rawValue)", value: $d.weight, step: step, range: 0...999,
                           format: { Fmt.number($0, maxFraction: 2) }, focus: focus, field: .dropWeight(d.id))
                CrownField(title: "次数", value: $d.reps, step: 1, range: 0...300,
                           format: { "\(Int($0.rounded()))" }, focus: focus, field: .dropReps(d.id))
                Button {
                    input.drops.removeAll { $0.id == d.id }
                } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            }
        }
        Button {
            input.addDrop(step: step)
        } label: {
            Label(input.drops.isEmpty ? "递减组" : "再加一段", systemImage: "plus")
                .font(.caption)
        }
        .buttonStyle(.glass)
        .controlSize(.mini)
    }
}

struct SetLoggerView: View {
    let workoutExercise: WorkoutExercise

    @EnvironmentObject private var manager: WorkoutManager
    @EnvironmentObject private var timer: RestTimer
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @Query private var matches: [Exercise]

    @State private var input = SetInput()
    @State private var isWarmup = false
    @State private var didPrefill = false
    @State private var lastSessionText: String?
    @State private var restContext: RestContext?
    @State private var editingSet: SetEntry?
    @FocusState private var focus: InputField?

    struct RestContext: Identifiable {
        let id = UUID()
        let set: SetEntry?
        let records: [PRKind]
    }

    init(workoutExercise: WorkoutExercise) {
        self.workoutExercise = workoutExercise
        let id = workoutExercise.exerciseId
        _matches = Query(filter: #Predicate<Exercise> { $0.id == id })
    }

    private var unit: WeightUnit { WeightUnit(raw: unitRaw) }

    var body: some View {
        if let exercise = matches.first {
            content(exercise)
                .onAppear {
                    if !didPrefill { prefill(exercise) }
                    #if DEBUG
                    if DemoData.screen == "rest", restContext == nil {
                        restContext = RestContext(set: workoutExercise.orderedSets.last, records: [.maxWeight])
                    }
                    #endif
                }
                .sheet(item: $restContext) { ctx in
                    RestPanelView(exercise: exercise, newRecords: ctx.records) { seconds in
                        manager.startRest(seconds: seconds, exercise: exercise, after: ctx.set)
                    }
                }
                .sheet(item: $editingSet) { set in
                    SetEditView(set: set, workoutExercise: workoutExercise, exercise: exercise)
                }
        } else {
            Text("找不到这个动作")
        }
    }

    private func content(_ exercise: Exercise) -> some View {
        let sets = workoutExercise.orderedSets
        let working = sets.filter { !$0.isWarmup }.count
        return ScrollView {
            VStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text(exercise.nameZh)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 4) {
                        Text(isWarmup ? "热身组" : "第 \(working + 1) 组")
                        if let target = workoutExercise.targetSets { Text("/ 目标 \(target)") }
                    }
                    .font(.caption)
                    .foregroundStyle(isWarmup ? Theme.warmup : Theme.accent)
                    if let lastSessionText {
                        Text("上次：\(lastSessionText)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                SetInputFields(exercise: exercise, unit: unit, input: $input, focus: $focus)

                Button {
                    isWarmup.toggle()
                } label: {
                    Label(isWarmup ? "热身组" : "标为热身", systemImage: isWarmup ? "flame.fill" : "flame")
                        .font(.caption)
                }
                .buttonStyle(.glass)
                .tint(isWarmup ? Theme.warmup : nil)
                .controlSize(.mini)

                Button {
                    logSet(exercise)
                } label: {
                    Label("完成本组", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .beigeGlassButton()
                .modifier(PrimaryActionShortcut())

                RestMiniRow()

                if !sets.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已完成").font(.caption2).foregroundStyle(.secondary)
                        ForEach(Array(sets.enumerated()), id: \.element.id) { i, s in
                            Button {
                                editingSet = s
                            } label: {
                                CompletedSetRow(index: i + 1, set: s, exercise: exercise, unit: unit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(exercise.equipment.displayName)
        .warmContainerBackground()
    }

    private func prefill(_ exercise: Exercise) {
        didPrefill = true
        let history = HistoryService(context: context)
        var previous: [SetValues] = []
        if let workout = workoutExercise.workout, let last = history.lastSession(for: exercise.id, before: workout) {
            previous = last.orderedSets.map(\.values)
            let workingSets = previous.filter { !$0.isWarmup }
            let top = workingSets.max { ($0.loadKg ?? 0, $0.reps ?? 0, $0.durationSec ?? 0) < ($1.loadKg ?? 0, $1.reps ?? 0, $1.durationSec ?? 0) }
            if let top {
                lastSessionText = Fmt.set(top, logType: exercise.logType, unit: unit) + " · \(workingSets.count)组"
            }
        }
        let target = Prefill.Target(reps: workoutExercise.targetReps, weightKg: workoutExercise.targetWeightKg, durationSec: nil)
        let v = Prefill.next(current: workoutExercise.orderedSets.map(\.values), previousSession: previous,
                             target: target, logType: exercise.logType, equipment: exercise.equipment)
        input = SetInput(v, unit: unit)
    }

    private func logSet(_ exercise: Exercise) {
        // 开始新的一组意味着休息结束
        timer.stop()
        let values = input.values(for: exercise, unit: unit, isWarmup: isWarmup)
        let records = manager.logSet(values, in: workoutExercise, exercise: exercise)
        isWarmup = false
        focus = nil
        restContext = RestContext(set: workoutExercise.orderedSets.last, records: records)
    }
}

struct CompletedSetRow: View {
    let index: Int
    let set: SetEntry
    let exercise: Exercise
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 6) {
            Text(set.isWarmup ? "热" : "\(index)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(set.isWarmup ? Theme.warmup : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.set(set.values, logType: exercise.logType, unit: unit))
                    .font(.system(.body, design: .rounded).monospacedDigit())
                if let rpe = set.rpe {
                    Text(Fmt.rpe(rpe)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !set.prKinds.isEmpty {
                Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
            }
            if !set.note.isEmpty {
                Image(systemName: "text.bubble").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

/// 编辑或删除已完成的一组
struct SetEditView: View {
    let set: SetEntry
    let workoutExercise: WorkoutExercise
    let exercise: Exercise

    @EnvironmentObject private var manager: WorkoutManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @State private var input = SetInput()
    @State private var isWarmup = false
    @State private var rpe: Double = 0
    @State private var note = ""
    @State private var loaded = false
    @FocusState private var focus: InputField?

    private static let rpeOptions: [Double] = stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }

    var body: some View {
        let unit = WeightUnit(raw: unitRaw)
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    SetInputFields(exercise: exercise, unit: unit, input: $input, focus: $focus)
                    Toggle("热身组", isOn: $isWarmup)
                    Picker("主观强度 RPE", selection: $rpe) {
                        Text("不记录").tag(0.0)
                        ForEach(Self.rpeOptions, id: \.self) { Text(Fmt.number($0)).tag($0) }
                    }
                    TextField("备注", text: $note)
                    Button("保存") {
                        manager.update(set, values: input.values(for: exercise, unit: unit, isWarmup: isWarmup),
                                       rpe: rpe > 0 ? rpe : nil, note: note, in: workoutExercise, exercise: exercise)
                        dismiss()
                    }
                    .beigeGlassButton()
                    Button("删除这一组", role: .destructive) {
                        manager.delete(set, in: workoutExercise, exercise: exercise)
                        dismiss()
                    }
                }
            }
            .navigationTitle("编辑")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            input = SetInput(set.values, unit: unit)
            isWarmup = set.isWarmup
            rpe = set.rpe ?? 0
            note = set.note
        }
    }
}
