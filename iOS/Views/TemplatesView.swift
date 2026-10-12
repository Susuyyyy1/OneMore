import SwiftData
import SwiftUI

struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutTemplate> { !$0.isRemoved }, sort: \WorkoutTemplate.updatedAt, order: .reverse)
    private var templates: [WorkoutTemplate]
    @Query private var exercises: [Exercise]
    @State private var path: [UUID] = []

    var body: some View {
        let names = exercises.byId
        NavigationStack(path: $path) {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView {
                        Label("还没有模板", systemImage: "rectangle.stack")
                    } description: {
                        Text("把固定的训练安排存成模板，在手表上点一下就能开始。也可以在训练记录里把某次训练“存为模板”。")
                    } actions: {
                        Button("新建模板") { create() }.beigeGlassButton()
                    }
                } else {
                    PaperList {
                        ForEach(templates) { t in
                            NavigationLink(value: t.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t.name).font(.headline)
                                    Text(t.orderedItems.compactMap { names[$0.exerciseId]?.nameZh }.joined(separator: "、"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                templates[i].isRemoved = true
                                Commit.template(templates[i], in: context)
                            }
                        }
                    }
                }
            }
            .background(PaperBackground())
            .navigationTitle("训练模板")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { create() } label: { Label("新建模板", systemImage: "plus") }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let t = templates.first(where: { $0.id == id }) { TemplateEditView(template: t) }
            }
        }
    }

    private func create() {
        let t = WorkoutTemplate(name: "新模板")
        context.insert(t)
        Commit.template(t, in: context)
        path.append(t.id)
    }
}

struct TemplateEditView: View {
    @Bindable var template: WorkoutTemplate

    @Environment(\.modelContext) private var context
    @Query private var exercises: [Exercise]
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @State private var showPicker = false

    var body: some View {
        let names = exercises.byId
        let unit = WeightUnit(raw: unitRaw)
        PaperList {
            Section("名称") {
                TextField("例如：胸 + 三头日", text: $template.name)
            }
            Section {
                ForEach(template.orderedItems) { item in
                    TemplateItemRow(item: item, exercise: names[item.exerciseId], unit: unit)
                }
                .onDelete { offsets in
                    let ordered = template.orderedItems
                    offsets.forEach { context.delete(ordered[$0]) }
                    renumber()
                }
                .onMove { from, to in
                    var ordered = template.orderedItems
                    ordered.move(fromOffsets: from, toOffset: to)
                    for (i, item) in ordered.enumerated() { item.order = i }
                }
                Button {
                    showPicker = true
                } label: {
                    Label("添加动作", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("动作（\(template.items.count)）")
            } footer: {
                Text("目标组数、次数和重量会在手表上作为预填值，实际做了多少以手表记录为准。")
            }
        }
        .navigationTitle(template.name.isEmpty ? "模板" : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet { id in
                let item = TemplateItem(order: (template.items.map(\.order).max() ?? -1) + 1, exerciseId: id)
                if let ex = names[id] {
                    if !ex.logType.usesReps { item.targetReps = nil }
                    if ex.logType.usesDuration { item.targetDurationSec = ex.logType == .cardio ? 600 : 60 }
                }
                context.insert(item)
                item.template = template
            }
        }
        .onDisappear { Commit.template(template, in: context) }
    }

    private func renumber() {
        for (i, item) in template.orderedItems.enumerated() { item.order = i }
    }
}

struct TemplateItemRow: View {
    @Bindable var item: TemplateItem
    let exercise: Exercise?
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise?.nameZh ?? "未知动作").font(.headline)
            Stepper("目标 \(item.targetSets) 组", value: $item.targetSets, in: 1...20)
            if exercise?.logType.usesReps ?? true {
                Stepper("每组 \(item.targetReps ?? 10) 次", value: Binding(
                    get: { item.targetReps ?? 10 }, set: { item.targetReps = $0 }), in: 1...100)
            }
            if exercise?.logType.usesDuration ?? false {
                Stepper("每组 \(Fmt.clock(item.targetDurationSec ?? 60))", value: Binding(
                    get: { item.targetDurationSec ?? 60 }, set: { item.targetDurationSec = $0 }), in: 5...7200, step: 15)
            }
            if exercise?.showsWeight ?? false {
                LabeledContent("目标重量（\(unit.rawValue)）") {
                    TextField("不指定", value: Binding(
                        get: { item.targetWeightKg.map { (unit.fromKg($0) * 100).rounded() / 100 } },
                        set: { item.targetWeightKg = $0.map(unit.toKg) }), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// iPhone 上选择动作
struct ExercisePickerSheet: View {
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Exercise> { !$0.isHidden }, sort: \Exercise.sortOrder)
    private var exercises: [Exercise]
    @State private var query = ""

    var body: some View {
        let items = exercises.filter { SearchIndex.matches(key: $0.searchKey, query: query) }
        NavigationStack {
            PaperList {
                ForEach(MuscleGroup.allCases) { group in
                    let groupItems = items.filter { $0.muscleGroup == group }
                    if !groupItems.isEmpty {
                        Section(group.displayName) {
                            ForEach(groupItems) { ex in
                                Button {
                                    onPick(ex.id)
                                    dismiss()
                                } label: {
                                    LibraryRow(exercise: ex)
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "中文 / 拼音首字母 / 英文")
            .navigationTitle("选择动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}
