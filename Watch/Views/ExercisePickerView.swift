import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    let onPick: (String) -> Void

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { !$0.isHidden }, sort: \Exercise.sortOrder)
    private var exercises: [Exercise]
    @State private var query = ""
    @State private var recentIds: [String] = []

    var body: some View {
        NavigationStack {
            List {
                TextField("搜索：卧推 / gwxl", text: $query)

                if !query.isEmpty {
                    let results = exercises.filter { SearchIndex.matches(key: $0.searchKey, query: query) }
                    if results.isEmpty {
                        Text("没有找到“\(query)”")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results.prefix(40)) { ex in
                        ExercisePickRow(exercise: ex, onPick: onPick)
                    }
                } else {
                    let byId = exercises.byId
                    let recent = recentIds.compactMap { byId[$0] }
                    if !recent.isEmpty {
                        Section("最近用过") {
                            ForEach(recent) { ex in ExercisePickRow(exercise: ex, onPick: onPick) }
                        }
                    }
                    Section("按部位") {
                        ForEach(MuscleGroup.allCases) { group in
                            NavigationLink(group.displayName) {
                                MuscleGroupPickList(group: group, exercises: exercises.filter { $0.muscleGroup == group },
                                                    onPick: onPick)
                            }
                        }
                    }
                }
            }
            .navigationTitle("添加动作")
            .onAppear { recentIds = HistoryService(context: context).recentExerciseIds() }
        }
    }
}

struct MuscleGroupPickList: View {
    let group: MuscleGroup
    let exercises: [Exercise]
    let onPick: (String) -> Void

    var body: some View {
        List {
            ForEach(Equipment.allCases) { eq in
                let items = exercises.filter { $0.equipment == eq }
                if !items.isEmpty {
                    Section(eq.displayName) {
                        ForEach(items) { ex in ExercisePickRow(exercise: ex, onPick: onPick, showsEquipment: false) }
                    }
                }
            }
        }
        .navigationTitle(group.displayName)
    }
}

struct ExercisePickRow: View {
    let exercise: Exercise
    let onPick: (String) -> Void
    var showsEquipment = true

    var body: some View {
        Button {
            onPick(exercise.id)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.nameZh)
                if showsEquipment {
                    Text("\(exercise.muscleGroup.displayName) · \(exercise.equipment.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
