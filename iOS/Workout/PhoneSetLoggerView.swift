import SwiftData
import SwiftUI

/// 手机上记录某个动作的组：和手表一样自动预填、记组、判断破纪录，记完弹出休息面板
struct PhoneSetLoggerView: View {
    let workoutExercise: WorkoutExercise
    /// 补录时不弹休息面板，每组的完成时间按训练开始时间顺延
    let isBackfill: Bool

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @Query private var matches: [Exercise]

    @State private var weight: Double = 0
    @State private var reps: Double = 10
    @State private var duration: Double = 60
    @State private var distanceKm: Double = 0
    @State private var isWarmup = false
    @State private var didPrefill = false
    @State private var lastSessionText: String?
    @State private var restContext: RestContext?
    @State private var editing: SetEditTarget?
    @State private var recordBanner: [PRKind] = []
    /// 递减组的后续各段（重量以当前单位显示）
    @State private var drops: [DropInput] = []

    struct DropInput: Identifiable {
        let id = UUID()
        var weight: Double
        var reps: Double
    }

    struct RestContext: Identifiable {
        let id = UUID()
        let set: SetEntry
        let records: [PRKind]
    }

    init(workoutExercise: WorkoutExercise, isBackfill: Bool) {
        self.workoutExercise = workoutExercise
        self.isBackfill = isBackfill
        let id = workoutExercise.exerciseId
        _matches = Query(filter: #Predicate<Exercise> { $0.id == id })
    }

    private var unit: WeightUnit { WeightUnit(raw: unitRaw) }
    private var ops: WorkoutOps { WorkoutOps(context: context) }

    var body: some View {
        if let exercise = matches.first {
            content(exercise)
                .onAppear { if !didPrefill { prefill(exercise) } }
                .sheet(item: $restContext) { ctx in
                    PhoneRestPanel(exercise: exercise, records: ctx.records) { seconds in
                        ops.recordRest(seconds: seconds, exercise: exercise, after: ctx.set)
                        PhoneRestTimer.shared.start(seconds: seconds, exerciseName: exercise.nameZh)
                    }
                    .presentationDetents([.medium])
                }
                .sheet(item: $editing) { target in
                    PhoneSetEditView(target: target) { ops.save() }
                }
        } else {
            ContentUnavailableView("找不到这个动作", systemImage: "questionmark")
        }
    }

    private func content(_ ex: Exercise) -> some View {
        let sets = workoutExercise.orderedSets
        let working = sets.filter { !$0.isWarmup }.count
        return ScrollView {
            VStack(spacing: 16) {
                // 标题
                VStack(spacing: 4) {
                    Text(isWarmup ? "热身组" : "第 \(working + 1) 组" + (workoutExercise.targetSets.map { " / 目标 \($0)" } ?? ""))
                        .font(.headline)
                        .foregroundStyle(isWarmup ? Theme.warmup : Theme.accent)
                    if let lastSessionText {
                        Text("上次：\(lastSessionText)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                if !recordBanner.isEmpty {
                    Label("新纪录：" + recordBanner.map(\.displayName).joined(separator: "、"), systemImage: "trophy.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassCard(cornerRadius: 16)
                        .transition(.scale.combined(with: .opacity))
                }

                // 输入
                VStack(spacing: 14) {
                    if ex.showsWeight {
                        NumberStepper(title: "\(ex.logType.weightLabel)（\(unit.rawValue)）", value: $weight,
                                      step: unit.step(forKgStep: ex.weightStepKg), range: 0...999, editable: true,
                                      format: { Fmt.number($0, maxFraction: 2) })
                    }
                    if ex.logType.usesReps {
                        NumberStepper(title: ex.isUnilateral ? "次数（每侧）" : "次数", value: $reps,
                                      step: 1, range: 0...300, editable: true, format: { "\(Int($0.rounded()))" })
                    }
                    if supportsDrops(ex) {
                        dropSection(ex)
                    }
                    if ex.logType.usesDuration {
                        NumberStepper(title: ex.isUnilateral ? "时间（每侧）" : "时间", value: $duration,
                                      step: ex.logType == .cardio ? 60 : 5, range: 0...(4 * 3600), editable: false,
                                      format: { Fmt.clock(Int($0.rounded())) })
                    }
                    if ex.logType.usesDistance {
                        NumberStepper(title: "距离（km，可不填）", value: $distanceKm, step: 0.1, range: 0...100, editable: true,
                                      format: { Fmt.number($0, maxFraction: 2) })
                    }
                    Toggle(isOn: $isWarmup) {
                        Label("这一组是热身组", systemImage: isWarmup ? "flame.fill" : "flame")
                            .foregroundStyle(isWarmup ? Theme.warmup : Theme.ink)
                    }
                    .tint(Theme.warmup)
                }
                .padding(18)
                .glassCard()

                Button {
                    logSet(ex)
                } label: {
                    Label("完成本组", systemImage: "checkmark")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .beigeGlassButton()
                .controlSize(.large)

                if !isBackfill { PhoneRestBanner() }

                // 已完成的组
                if !sets.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("已完成 · 点一下修改，长按删除")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.bottom, 6)
                        ForEach(Array(sets.enumerated()), id: \.element.id) { i, s in
                            Button {
                                editing = SetEditTarget(entry: s, workoutExercise: workoutExercise, exercise: ex)
                            } label: {
                                PhoneSetRow(index: i + 1, set: s, logType: ex.logType, unit: unit)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("删除这一组", systemImage: "trash", role: .destructive) {
                                    ops.delete(s, in: workoutExercise, exercise: ex)
                                }
                            }
                            if i < sets.count - 1 { Divider().overlay(Theme.ink.opacity(0.08)) }
                        }
                    }
                    .padding(18)
                    .glassCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(PaperBackground())
        .navigationTitle(ex.nameZh)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 递减组

    private func supportsDrops(_ ex: Exercise) -> Bool { ex.showsWeight && ex.logType.usesReps }

    /// 递减的每一段：重量 + 次数，可以删掉；下面的按钮再加一段
    @ViewBuilder
    private func dropSection(_ ex: Exercise) -> some View {
        let step = unit.step(forKgStep: ex.weightStepKg)
        ForEach($drops) { $d in
            let index = (drops.firstIndex { $0.id == d.id } ?? 0) + 1
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("递减第 \(index) 段", systemImage: "arrow.turn.right.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.tint)
                    Spacer()
                    Button {
                        withAnimation { drops.removeAll { $0.id == d.id } }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    CompactStepper(title: unit.rawValue, value: $d.weight, step: step, range: 0...999,
                                   format: { Fmt.number($0, maxFraction: 2) })
                    CompactStepper(title: "次", value: $d.reps, step: 1, range: 0...300,
                                   format: { "\(Int($0.rounded()))" })
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.ink.opacity(0.04)))
        }
        Button {
            withAnimation { addDrop(step: step) }
        } label: {
            Label(drops.isEmpty ? "递减组：加一段" : "再加一段递减", systemImage: "plus")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
    }

    /// 新的一段默认重量减半（对齐到步进）、次数与上一段相同
    private func addDrop(step: Double) {
        let lastWeight = drops.last?.weight ?? weight
        let lastReps = drops.last?.reps ?? reps
        let half = max(step, ((lastWeight / 2) / step).rounded() * step)
        drops.append(DropInput(weight: min(half, lastWeight), reps: lastReps))
    }

    private func prefill(_ ex: Exercise) {
        didPrefill = true
        let history = HistoryService(context: context)
        var previous: [SetValues] = []
        if let w = workoutExercise.workout, let last = history.lastSession(for: ex.id, before: w) {
            previous = last.orderedSets.map(\.values)
            let workingSets = previous.filter { !$0.isWarmup }
            let top = workingSets.max { ($0.loadKg ?? 0, $0.reps ?? 0, $0.durationSec ?? 0) < ($1.loadKg ?? 0, $1.reps ?? 0, $1.durationSec ?? 0) }
            if let top { lastSessionText = Fmt.set(top, logType: ex.logType, unit: unit) + " · \(workingSets.count)组" }
        }
        let target = Prefill.Target(reps: workoutExercise.targetReps, weightKg: workoutExercise.targetWeightKg, durationSec: nil)
        let v = Prefill.next(current: workoutExercise.orderedSets.map(\.values), previousSession: previous,
                             target: target, logType: ex.logType, equipment: ex.equipment)
        weight = (unit.fromKg(v.weightKg ?? 0) * 100).rounded() / 100
        reps = Double(v.reps ?? 10)
        duration = Double(v.durationSec ?? 60)
        distanceKm = (v.distanceM ?? 0) / 1000
        // 上一组是递减组的话，这一组沿用同样的结构
        drops = supportsDrops(ex) ? v.drops.map {
            DropInput(weight: (unit.fromKg($0.weightKg ?? 0) * 100).rounded() / 100, reps: Double($0.reps ?? Int(reps)))
        } : []
    }

    private func logSet(_ ex: Exercise) {
        var v = SetValues(isWarmup: isWarmup)
        if ex.showsWeight, weight > 0 { v.weightKg = unit.toKg(weight) }
        if ex.logType.usesReps { v.reps = Int(reps.rounded()) }
        if ex.logType.usesDuration { v.durationSec = Int(duration.rounded()) }
        if ex.logType.usesDistance, distanceKm > 0 { v.distanceM = distanceKm * 1000 }
        if supportsDrops(ex) {
            v.drops = drops.map { DropStage(weightKg: $0.weight > 0 ? unit.toKg($0.weight) : nil, reps: Int($0.reps.rounded())) }
        }

        let date: Date
        if isBackfill {
            // 补录：每组在上一组之后约 2.5 分钟
            let last = workoutExercise.workout?.exercises.flatMap(\.sets).map(\.completedAt).max()
            date = (last ?? workoutExercise.workout?.startedAt ?? .now).addingTimeInterval(150)
        } else {
            PhoneRestTimer.shared.stop()
            date = .now
        }
        let result = ops.logSet(v, in: workoutExercise, exercise: ex, at: date)
        isWarmup = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if isBackfill {
            if !result.records.isEmpty {
                withAnimation { recordBanner = result.records }
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { recordBanner = [] }
                }
            }
        } else {
            restContext = RestContext(set: result.set, records: result.records)
        }
    }
}

/// 递减组里用的紧凑版 − 数值 +
struct CompactStepper: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    private func snap(_ raw: Double) -> Double {
        let snapped = range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step
        return (min(max(snapped, range.lowerBound), range.upperBound) * 1000).rounded() / 1000
    }

    var body: some View {
        HStack(spacing: 6) {
            button("minus") { value = snap(value - step) }
            VStack(spacing: 0) {
                Text(format(value)).font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                Text(title).font(.caption2).foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            button("plus") { value = snap(value + step) }
        }
        .frame(maxWidth: .infinity)
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Image(systemName: symbol).font(.subheadline.weight(.semibold)).frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}

/// − 数值 + 的输入行；editable 时可以直接点数字输入
struct NumberStepper: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>
    let editable: Bool
    let format: (Double) -> String

    @FocusState private var focused: Bool

    private func snap(_ raw: Double) -> Double {
        let snapped = range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step
        return (min(max(snapped, range.lowerBound), range.upperBound) * 1000).rounded() / 1000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.inkSecondary)
            HStack(spacing: 12) {
                circleButton("minus") { value = snap(value - step) }
                Group {
                    if editable {
                        TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(format(value))
                    }
                }
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(maxWidth: .infinity)
                circleButton("plus") { value = snap(value + step) }
            }
        }
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focused = false }
                }
            }
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            focused = false
            action()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}

/// 记完一组后的休息面板：快捷时长（这个动作上次用的高亮），点一下开始；之后显示倒计时
struct PhoneRestPanel: View {
    let exercise: Exercise
    let records: [PRKind]
    let onStart: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var timer = PhoneRestTimer.shared
    @AppStorage(SettingsKey.restPresets) private var presetsRaw = AppSettings.encodePresets(AppSettings.defaultPresets)
    @AppStorage(SettingsKey.defaultRest) private var defaultRest = 120
    @State private var started = false
    @State private var customMinutes = 2
    @State private var customSeconds = 0
    @State private var showCustom = false

    private var remembered: Int { exercise.lastRestSeconds ?? defaultRest }
    private var options: [Int] {
        var list = AppSettings.decodePresets(presetsRaw)
        if !list.contains(remembered) { list.insert(remembered, at: 0) }
        return list
    }

    var body: some View {
        VStack(spacing: 16) {
            if !records.isEmpty {
                Label("新纪录：" + records.map(\.displayName).joined(separator: "、"), systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
            }
            if started {
                PhoneRestCountdown { dismiss() }
            } else {
                Text("组间休息").font(.title3.weight(.semibold))
                if timer.notificationsBlocked {
                    NotificationOffHint()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(options, id: \.self) { s in
                        Button {
                            start(s)
                        } label: {
                            Text(Fmt.clock(s))
                                .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(s == remembered ? Theme.onBeige : Theme.ink)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(s == remembered ? .regular.tint(Theme.beigeButton).interactive() : .regular.interactive(), in: .capsule)
                    }
                    Button {
                        customMinutes = remembered / 60
                        customSeconds = (remembered % 60) / 15 * 15
                        showCustom.toggle()
                    } label: {
                        Text("自定义").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                if showCustom {
                    HStack {
                        Picker("分", selection: $customMinutes) { ForEach(0..<16) { Text("\($0) 分").tag($0) } }
                        Picker("秒", selection: $customSeconds) { ForEach([0, 15, 30, 45], id: \.self) { Text("\($0) 秒").tag($0) } }
                        Button("开始") { start(max(15, customMinutes * 60 + customSeconds)) }
                            .beigeGlassButton()
                    }
                }
                Button("不休息") { dismiss() }
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PaperBackground())
    }

    private func start(_ seconds: Int) {
        onStart(seconds)
        started = true
    }
}

/// 大号倒计时
struct PhoneRestCountdown: View {
    let onClose: () -> Void
    @ObservedObject private var timer = PhoneRestTimer.shared

    var body: some View {
        VStack(spacing: 14) {
            if timer.isFinished {
                Image(systemName: "bell.and.waves.left.and.right.fill").font(.largeTitle).foregroundStyle(Theme.warmup)
                Text("休息结束，开始下一组！").font(.title3.weight(.semibold))
                Button("好") {
                    timer.stop()
                    onClose()
                }
                .beigeGlassButton()
                .controlSize(.large)
            } else if let end = timer.endDate {
                Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                ProgressView(timerInterval: min(end.addingTimeInterval(-Double(max(timer.totalSeconds, 1))), Date.now)...end,
                             countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(Theme.accent)
                HStack(spacing: 12) {
                    Button("−15 秒") { timer.adjust(by: -15) }
                    Button("+15 秒") { timer.adjust(by: 15) }
                    Button("结束休息") {
                        timer.stop()
                        onClose()
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }
}

/// 休息中的小横条，点开看大号倒计时
struct PhoneRestBanner: View {
    @ObservedObject private var timer = PhoneRestTimer.shared
    @State private var showCountdown = false

    var body: some View {
        if timer.isActive {
            Button {
                showCountdown = true
            } label: {
                HStack {
                    Image(systemName: timer.isFinished ? "bell.fill" : "timer")
                    if timer.isFinished {
                        Text("休息结束")
                    } else if let end = timer.endDate {
                        Text("休息中 \(Text(timerInterval: min(Date.now, end)...end, countsDown: true))")
                    }
                    Spacer()
                    Text(timer.isFinished ? "知道了" : "查看").font(.caption).foregroundStyle(Theme.inkSecondary)
                }
                .font(.headline.monospacedDigit())
                .foregroundStyle(timer.isFinished ? Theme.warmup : Theme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .glassCard(cornerRadius: 18)
            .sheet(isPresented: $showCountdown) {
                PhoneRestCountdown { showCountdown = false }
                    .padding(24)
                    .presentationDetents([.medium])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PaperBackground())
            }
        }
    }
}
