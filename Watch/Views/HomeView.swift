import SwiftData
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var manager: WorkoutManager
    @Query(filter: #Predicate<Workout> { !$0.isRemoved && $0.endedAt != nil },
           sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]
    @Query(filter: #Predicate<WorkoutTemplate> { !$0.isRemoved }, sort: \WorkoutTemplate.updatedAt, order: .reverse)
    private var templates: [WorkoutTemplate]

    var body: some View {
        NavigationStack {
            List {
                Button {
                    manager.start()
                } label: {
                    Label("开始训练", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.onBeige)
                        .padding(.vertical, 6)
                }
                .listItemTint(Theme.beige)

                if !templates.isEmpty {
                    NavigationLink {
                        TemplatePickerView(templates: templates)
                    } label: {
                        Label("从模板开始", systemImage: "list.bullet.rectangle.portrait")
                    }
                }

                Section("最近训练") {
                    if workouts.isEmpty {
                        Text("还没有训练记录")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(workouts.prefix(15)) { w in
                        NavigationLink {
                            WorkoutDetailView(workout: w)
                        } label: {
                            WorkoutRow(workout: w)
                        }
                    }
                }
            }
            .navigationTitle("One More")
            .warmContainerBackground()
        }
    }
}

struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workout.title.isEmpty ? "力量训练" : workout.title)
                .font(.headline)
                .lineLimit(1)
            Text(workout.startedAt, format: .dateTime.month().day().weekday())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(workout.exercises.count)个动作 · \(workout.workingSetCount)组")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct TemplatePickerView: View {
    let templates: [WorkoutTemplate]
    @EnvironmentObject private var manager: WorkoutManager
    @Query private var exercises: [Exercise]

    var body: some View {
        List(templates) { t in
            Button {
                manager.start(template: t)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(.headline)
                    Text(summary(t))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .navigationTitle("选择模板")
    }

    private func summary(_ t: WorkoutTemplate) -> String {
        let names = exercises.byId
        return t.orderedItems.compactMap { names[$0.exerciseId]?.nameZh }.joined(separator: "、")
    }
}

/// 历史训练详情（只读，编辑请在 iPhone 上进行）
struct WorkoutDetailView: View {
    let workout: Workout
    @Query private var exercises: [Exercise]
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue

    var body: some View {
        let unit = WeightUnit(raw: unitRaw)
        let names = exercises.byId
        List {
            Section {
                Text(workout.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                    StatTile(title: "时长", value: Fmt.durationText(workout.duration))
                    StatTile(title: "正式组", value: "\(workout.workingSetCount)")
                    StatTile(title: "容量", value: Fmt.volume(workout.volumeKg, unit: unit))
                    if let kcal = workout.activeKcal { StatTile(title: "千卡", value: "\(Int(kcal))") }
                }
            }
            ForEach(workout.orderedExercises) { we in
                let ex = names[we.exerciseId]
                Section(ex?.nameZh ?? "未知动作") {
                    ForEach(Array(we.orderedSets.enumerated()), id: \.element.id) { i, s in
                        HStack {
                            Text("\(i + 1)").foregroundStyle(.secondary)
                            Text(Fmt.set(s.values, logType: ex?.logType ?? .weightReps, unit: unit))
                            if s.isWarmup { Text("热身").font(.caption2).foregroundStyle(Theme.warmup) }
                            Spacer()
                            if !s.prKinds.isEmpty { Image(systemName: "trophy.fill").foregroundStyle(Theme.gold) }
                        }
                    }
                }
            }
            if !workout.note.isEmpty {
                Section("备注") { Text(workout.note) }
            }
        }
        .navigationTitle(workout.title.isEmpty ? "训练" : workout.title)
    }
}
