import Charts
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \Exercise.sortOrder) private var exercises: [Exercise]
    @State private var query = ""
    @State private var equipmentFilter: Equipment?
    @State private var showHidden = false
    @State private var showNew = false

    private var filtered: [Exercise] {
        exercises.filter { ex in
            (showHidden || !ex.isHidden)
                && (equipmentFilter == nil || ex.equipment == equipmentFilter)
                && SearchIndex.matches(key: ex.searchKey, query: query)
        }
    }

    var body: some View {
        let items = filtered
        NavigationStack {
            PaperList {
                ForEach(MuscleGroup.allCases) { group in
                    let groupItems = items.filter { $0.muscleGroup == group }
                    if !groupItems.isEmpty {
                        Section("\(group.displayName)（\(groupItems.count)）") {
                            ForEach(groupItems) { ex in
                                NavigationLink(value: ex.id) { LibraryRow(exercise: ex) }
                            }
                        }
                    }
                }
                if items.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "中文 / 拼音首字母 / 英文")
            .navigationTitle("动作库")
            .navigationDestination(for: String.self) { id in ExerciseDetailView(exerciseId: id) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("器材", selection: $equipmentFilter) {
                            Text("全部器材").tag(Equipment?.none)
                            ForEach(Equipment.allCases) { Text($0.displayName).tag(Equipment?.some($0)) }
                        }
                        Toggle("显示已隐藏的动作", isOn: $showHidden)
                    } label: {
                        Label("筛选", systemImage: equipmentFilter == nil ? "line.3.horizontal.decrease.circle"
                                                                         : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Label("新建动作", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showNew) { ExerciseEditView(exercise: nil) }
        }
    }
}

struct LibraryRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(exercise.nameZh)
                if exercise.isCustom { Tag(text: "自定义", color: Theme.accent) }
                if exercise.isHidden { Tag(text: "已隐藏", color: .gray) }
            }
            Text("\(exercise.equipment.displayName) · \(exercise.nameEn)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }
}

struct ExerciseDetailView: View {
    let exerciseId: String

    @Environment(\.modelContext) private var context
    @Query private var matches: [Exercise]
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.restPresets) private var presetsRaw = AppSettings.encodePresets(AppSettings.defaultPresets)
    @State private var metric: Metric = .maxWeight
    @State private var showEdit = false
    @State private var sessions: [WorkoutExercise] = []

    enum Metric: String, CaseIterable, Identifiable {
        case maxWeight = "最大重量", e1RM = "估算1RM", volume = "容量", maxReps = "最多次数", maxDuration = "最长时间"
        var id: String { rawValue }
    }

    init(exerciseId: String) {
        self.exerciseId = exerciseId
        _matches = Query(filter: #Predicate<Exercise> { $0.id == exerciseId })
    }

    var body: some View {
        if let ex = matches.first {
            content(ex)
                .onAppear {
                    sessions = HistoryService(context: context).sessions(for: ex.id)
                    if !metrics(for: ex).contains(metric) { metric = metrics(for: ex).first ?? .maxReps }
                }
        } else {
            ContentUnavailableView("找不到这个动作", systemImage: "questionmark")
        }
    }

    private func metrics(for ex: Exercise) -> [Metric] {
        switch ex.logType {
        case .weightReps, .assisted: [.maxWeight, .e1RM, .volume]
        case .bodyweight: ex.tracksWeight ? [.maxReps, .maxWeight] : [.maxReps]
        case .duration, .cardio: [.maxDuration]
        case .weightDuration: [.maxWeight, .maxDuration]
        }
    }

    private func content(_ ex: Exercise) -> some View {
        let unit = WeightUnit(raw: unitRaw)
        let bests = HistoryService(context: context).allTimeBests(for: ex)
        let points = chartPoints(ex, unit: unit)
        return PaperList {
            Section {
                LabeledContent("部位", value: ex.muscleGroup.displayName)
                LabeledContent("器材", value: ex.equipment.displayName)
                LabeledContent("记录方式", value: ex.logType.displayName)
                if ex.isUnilateral { LabeledContent("单侧动作", value: "次数按每侧记") }
                if !ex.aliases.isEmpty { LabeledContent("别名", value: ex.aliases.joined(separator: "、")) }
            } header: {
                Text(ex.nameEn)
            }

            if !bests.isEmpty {
                Section("个人最佳") {
                    if let w = bests.maxWeight { LabeledContent(ex.logType == .bodyweight ? "最大附加重量" : "最大重量", value: Fmt.weight(w, unit: unit)) }
                    if let e = bests.maxE1RM { LabeledContent("估算 1RM", value: Fmt.weight(e, unit: unit)) }
                    if let r = bests.maxReps { LabeledContent("最多次数", value: "\(r)") }
                    if let d = bests.maxDuration { LabeledContent("最长时间", value: Fmt.clock(d)) }
                }
            }

            if !points.isEmpty {
                Section("走势") {
                    let options = metrics(for: ex)
                    if options.count > 1 {
                        Picker("指标", selection: $metric) {
                            ForEach(options) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Chart(points) { p in
                        LineMark(x: .value("日期", p.date), y: .value(metric.rawValue, p.value))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("日期", p.date), y: .value(metric.rawValue, p.value))
                    }
                    .foregroundStyle(Theme.accent)
                    .chartYAxisLabel(axisLabel(unit: unit))
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                }
            }

            Section {
                if ex.logType.supportsWeight {
                    Toggle("记录重量", isOn: binding(ex, \.tracksWeight))
                }
                Picker("组间休息", selection: binding(ex, \.lastRestSeconds)) {
                    Text("跟随默认设置").tag(Int?.none)
                    ForEach(restOptions(including: ex.lastRestSeconds), id: \.self) { Text(Fmt.clock($0)).tag(Int?.some($0)) }
                }
                if ex.showsWeight {
                    Picker("表冠调重量步进", selection: binding(ex, \.weightStepKg)) {
                        ForEach([0.5, 1, 1.25, 2, 2.5, 5], id: \.self) { Text(Fmt.number($0, maxFraction: 2) + " kg").tag($0) }
                    }
                }
                Toggle("在手表上隐藏", isOn: binding(ex, \.isHidden))
                if ex.isCustom {
                    Button("编辑动作信息") { showEdit = true }
                }
            } header: {
                Text("设置")
            } footer: {
                Text("组间休息会在手表上自动记住你上次选的时长，这里也可以手动修改。")
            }

            Section("历史记录（\(sessions.count)次）") {
                if sessions.isEmpty {
                    Text("还没有做过这个动作").foregroundStyle(.secondary)
                }
                ForEach(sessions) { we in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(we.workout?.startedAt.formatted(.dateTime.year().month().day().weekday()) ?? "")
                            .font(.subheadline.weight(.semibold))
                        Text(we.orderedSets.map { s in
                            (s.isWarmup ? "热身 " : "") + Fmt.set(s.values, logType: ex.logType, unit: unit)
                                + (s.prKinds.isEmpty ? "" : " 🏆")
                        }.joined(separator: "\n"))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(ex.nameZh)
        .sheet(isPresented: $showEdit) { ExerciseEditView(exercise: ex) }
    }

    private func binding<T>(_ ex: Exercise, _ keyPath: ReferenceWritableKeyPath<Exercise, T>) -> Binding<T> {
        Binding(get: { ex[keyPath: keyPath] }, set: {
            ex[keyPath: keyPath] = $0
            Commit.exercise(ex, in: context)
        })
    }

    private func restOptions(including current: Int?) -> [Int] {
        var list = AppSettings.decodePresets(presetsRaw)
        if let current, !list.contains(current) { list.append(current) }
        return list.sorted()
    }

    struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private func chartPoints(_ ex: Exercise, unit: WeightUnit) -> [ChartPoint] {
        sessions.reversed().compactMap { we in
            guard let date = we.workout?.startedAt else { return nil }
            let working = we.sets.map(\.values).filter { !$0.isWarmup }
            let value: Double?
            switch metric {
            case .maxWeight:
                value = working.compactMap(\.loadKg).max().map(unit.fromKg)
            case .e1RM:
                value = working.compactMap { s in s.loadKg.flatMap { w in s.reps.flatMap { PRCalculator.e1RM(weightKg: w, reps: $0) } } }
                    .max().map(unit.fromKg)
            case .volume:
                let v = WorkoutStats.volumeKg(working)
                value = v > 0 ? unit.fromKg(v) : nil
            case .maxReps:
                value = working.compactMap(\.reps).max().map(Double.init)
            case .maxDuration:
                value = working.compactMap(\.durationSec).max().map { Double($0) / 60 }
            }
            return value.map { ChartPoint(date: date, value: $0) }
        }
    }

    private func axisLabel(unit: WeightUnit) -> String {
        switch metric {
        case .maxWeight, .e1RM, .volume: unit.rawValue
        case .maxReps: "次"
        case .maxDuration: "分钟"
        }
    }
}

/// 新建或编辑自定义动作
struct ExerciseEditView: View {
    let exercise: Exercise?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var nameZh = ""
    @State private var nameEn = ""
    @State private var group: MuscleGroup = .chest
    @State private var equipment: Equipment = .dumbbell
    @State private var logType: LogType = .weightReps
    @State private var isUnilateral = false

    var body: some View {
        NavigationStack {
            PaperForm {
                Section {
                    TextField("动作名称（中文）", text: $nameZh)
                    TextField("英文名（可不填）", text: $nameEn)
                }
                Section {
                    Picker("部位", selection: $group) { ForEach(MuscleGroup.allCases) { Text($0.displayName).tag($0) } }
                    Picker("器材", selection: $equipment) { ForEach(Equipment.allCases) { Text($0.displayName).tag($0) } }
                    Picker("记录方式", selection: $logType) { ForEach(LogType.allCases) { Text($0.displayName).tag($0) } }
                    Toggle("单侧动作（次数按每侧记）", isOn: $isUnilateral)
                }
            }
            .navigationTitle(exercise == nil ? "新建动作" : "编辑动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(nameZh.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let exercise else { return }
                nameZh = exercise.nameZh
                nameEn = exercise.nameEn
                group = exercise.muscleGroup
                equipment = exercise.equipment
                logType = exercise.logType
                isUnilateral = exercise.isUnilateral
            }
        }
    }

    private func save() {
        let name = nameZh.trimmingCharacters(in: .whitespaces)
        let ex: Exercise
        if let exercise {
            ex = exercise
            ex.nameZh = name
            ex.nameEn = nameEn
            ex.muscleGroup = group
            ex.equipment = equipment
            if ex.logType != logType {
                ex.logType = logType
                ex.tracksWeight = logType.defaultTracksWeight
            }
            ex.isUnilateral = isUnilateral
        } else {
            ex = Exercise(id: UUID().uuidString, nameZh: name, nameEn: nameEn, muscleGroup: group, equipment: equipment,
                          logType: logType, isUnilateral: isUnilateral, isCustom: true, updatedAt: .now)
            context.insert(ex)
        }
        Commit.exercise(ex, in: context)
        dismiss()
    }
}
