import SwiftData
import SwiftUI

/// 训练结束后的总结页
struct SummaryView: View {
    let workout: Workout

    @EnvironmentObject private var manager: WorkoutManager
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @State private var note = ""
    @State private var savedTemplate = false

    var body: some View {
        let unit = WeightUnit(raw: unitRaw)
        let names = exercises.byId
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("训练完成 🎉").font(.title3.weight(.bold))
                    Text(workout.title).foregroundStyle(Theme.accent)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        StatTile(title: "时长", value: Fmt.durationText(workout.duration))
                        StatTile(title: "动作", value: "\(workout.exercises.count)个")
                        StatTile(title: "正式组", value: "\(workout.workingSetCount)组")
                        StatTile(title: "总容量", value: Fmt.volume(workout.volumeKg, unit: unit))
                        if let hr = workout.avgHeartRate { StatTile(title: "平均心率", value: "\(Int(hr))") }
                        if let kcal = workout.activeKcal { StatTile(title: "活动千卡", value: "\(Int(kcal))") }
                    }

                    let records = workout.orderedExercises.flatMap { we in
                        we.orderedSets.filter { !$0.prKinds.isEmpty }.map { (we, $0) }
                    }
                    if !records.isEmpty {
                        Text("🏆 新纪录").font(.headline).foregroundStyle(Theme.gold)
                        ForEach(records, id: \.1.id) { we, s in
                            let ex = names[we.exerciseId]
                            VStack(alignment: .leading, spacing: 0) {
                                Text(ex?.nameZh ?? "未知动作")
                                Text(Fmt.set(s.values, logType: ex?.logType ?? .weightReps, unit: unit) + " · "
                                     + s.prKinds.map(\.displayName).joined(separator: "、"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text("动作").font(.headline)
                    ForEach(workout.orderedExercises) { we in
                        HStack {
                            Text(names[we.exerciseId]?.nameZh ?? "未知动作").lineLimit(1)
                            Spacer()
                            Text("\(we.workingSetCount)组").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }

                    TextField("添加备注", text: $note)

                    Button {
                        manager.saveAsTemplate(workout, name: workout.title)
                        savedTemplate = true
                    } label: {
                        Label(savedTemplate ? "已存为模板" : "存为模板", systemImage: savedTemplate ? "checkmark" : "square.and.arrow.down")
                    }
                    .buttonStyle(.glass)
                    .disabled(savedTemplate)

                    Button("完成") { close() }
                        .beigeGlassButton()
                }
            }
        }
        .onAppear { note = workout.note }
        // 下滑关闭也会保存备注
        .onDisappear { if note != workout.note { manager.updateNote(workout, note: note) } }
    }

    private func close() { dismiss() }
}
