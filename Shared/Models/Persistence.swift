import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([
        Exercise.self, Workout.self, WorkoutExercise.self, SetEntry.self, WorkoutTemplate.self, TemplateItem.self,
    ])

    @MainActor
    static let shared: ModelContainer = makeContainer(inMemory: false)

    @MainActor
    static func makeContainer(inMemory: Bool) -> ModelContainer {
        // 内存数据库（测试用）每次取不同名字，互不干扰
        let config = inMemory
            ? ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema)
        do {
            let container = try ModelContainer(for: schema, configurations: config)
            SeedLoader.seedIfNeeded(context: container.mainContext, force: inMemory)
            return container
        } catch {
            fatalError("无法打开数据库：\(error)")
        }
    }
}

/// 把内置动作库导入 SwiftData。按 id 增量更新，不覆盖用户改过的字段。
enum SeedLoader {
    private static let versionKey = "seedVersion"

    struct SeedFile: Decodable {
        let version: Int
        let exercises: [SeedExercise]
    }

    struct SeedExercise: Decodable {
        let id: String
        let zh: String
        let en: String
        let alias: [String]
        let g: MuscleGroup
        let eq: Equipment
        let t: LogType
        let uni: Bool?
    }

    static func loadSeedFile(bundle: Bundle = .main) throws -> SeedFile {
        guard let url = bundle.url(forResource: "exercises", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(SeedFile.self, from: Data(contentsOf: url))
    }

    @MainActor
    static func seedIfNeeded(context: ModelContext, force: Bool = false) {
        guard let file = try? loadSeedFile() else {
            assertionFailure("找不到 exercises.json")
            return
        }
        let defaults = UserDefaults.standard
        let isEmpty = ((try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0) == 0
        if !force, !isEmpty, defaults.integer(forKey: versionKey) >= file.version { return }

        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for (index, seed) in file.exercises.enumerated() {
            if let ex = byId[seed.id] {
                ex.sortOrder = index
                // 只更新动作库自己的字段；tracksWeight / 休息时长 / 步进 / 隐藏由用户决定
                ex.nameZh = seed.zh
                ex.nameEn = seed.en
                ex.aliases = seed.alias
                ex.muscleGroup = seed.g
                ex.equipment = seed.eq
                ex.logType = seed.t
                ex.isUnilateral = seed.uni ?? false
                ex.refreshSearchKey()
            } else {
                context.insert(Exercise(id: seed.id, nameZh: seed.zh, nameEn: seed.en, aliases: seed.alias,
                                        muscleGroup: seed.g, equipment: seed.eq, logType: seed.t,
                                        isUnilateral: seed.uni ?? false, sortOrder: index))
            }
        }
        do {
            try context.save()
            if !force { defaults.set(file.version, forKey: versionKey) }
        } catch {
            assertionFailure("导入动作库失败：\(error)")
        }
    }
}
