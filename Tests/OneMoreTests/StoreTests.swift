import SwiftData
import XCTest
@testable import OneMore

@MainActor
final class StoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = Persistence.makeContainer(inMemory: true)
    }

    private func makeWorkout(daysAgo: Double, sets: [SetValues], exerciseId: String = "barbell-bench-press") -> Workout {
        let w = Workout(startedAt: Date().addingTimeInterval(-daysAgo * 86400))
        w.endedAt = w.startedAt.addingTimeInterval(3600)
        context.insert(w)
        let we = WorkoutExercise(order: 0, exerciseId: exerciseId)
        context.insert(we)
        we.workout = w
        for (i, v) in sets.enumerated() {
            let s = SetEntry(order: i, values: v)
            context.insert(s)
            s.workoutExercise = we
        }
        try? context.save()
        return w
    }

    func testSeedImported() throws {
        let count = try context.fetchCount(FetchDescriptor<Exercise>())
        XCTAssertGreaterThanOrEqual(count, 200)
        let bench = HistoryService(context: context).exercise(id: "barbell-bench-press")
        XCTAssertEqual(bench?.nameZh, "杠铃卧推")
        XCTAssertEqual(bench?.tracksWeight, true)
        XCTAssertEqual(HistoryService(context: context).exercise(id: "pull-up")?.tracksWeight, false)
    }

    func testLastSessionAndBests() throws {
        _ = makeWorkout(daysAgo: 7, sets: [SetValues(weightKg: 60, reps: 10)])
        _ = makeWorkout(daysAgo: 3, sets: [SetValues(weightKg: 62.5, reps: 8), SetValues(weightKg: 62.5, reps: 8)])
        let current = makeWorkout(daysAgo: 0, sets: [])
        let history = HistoryService(context: context)
        let last = history.lastSession(for: "barbell-bench-press", before: current)
        XCTAssertEqual(last?.sets.count, 2)
        let bench = try XCTUnwrap(history.exercise(id: "barbell-bench-press"))
        XCTAssertEqual(history.bests(for: bench, before: current).maxWeight, 62.5)
    }

    func testRemovedWorkoutsIgnored() throws {
        let old = makeWorkout(daysAgo: 2, sets: [SetValues(weightKg: 100, reps: 5)])
        old.isRemoved = true
        try context.save()
        let current = makeWorkout(daysAgo: 0, sets: [])
        let history = HistoryService(context: context)
        let bench = try XCTUnwrap(history.exercise(id: "barbell-bench-press"))
        XCTAssertNil(history.bests(for: bench, before: current).maxWeight)
    }

    func testWorkoutDTORoundTripAndLastWriterWins() throws {
        let w = makeWorkout(daysAgo: 1, sets: [SetValues(weightKg: 60, reps: 10), SetValues(weightKg: 40, reps: 12, isWarmup: true)])
        w.title = "胸"
        let store = DataStore(context: context)
        var dto = store.dto(w)
        // 日期按毫秒传输：解码后再编码应得到完全相同的数据
        let data = try DTOCoding.encoder().encode(dto)
        let decoded = try DTOCoding.decoder().decode(WorkoutDTO.self, from: data)
        XCTAssertEqual(try DTOCoding.encoder().encode(decoded), data)
        XCTAssertEqual(decoded.exercises.first?.sets.count, 2)

        // 另一台设备上的数据库（必须持有 container，否则 context 会失效）
        let otherContainer = Persistence.makeContainer(inMemory: true)
        let other = otherContainer.mainContext
        let otherStore = DataStore(context: other)
        XCTAssertTrue(otherStore.apply(dto))
        XCTAssertFalse(otherStore.apply(dto), "相同时间戳不应重复应用")
        let copied = try XCTUnwrap(other.fetch(FetchDescriptor<Workout>()).first)
        XCTAssertEqual(copied.title, "胸")
        XCTAssertEqual(copied.workingSetCount, 1)

        // 较新的修改覆盖，较旧的忽略
        dto.title = "胸 · 三头"
        dto.updatedAt = dto.updatedAt.addingTimeInterval(10)
        XCTAssertTrue(otherStore.apply(dto))
        XCTAssertEqual(copied.title, "胸 · 三头")
        var stale = dto
        stale.title = "旧标题"
        stale.updatedAt = dto.updatedAt.addingTimeInterval(-60)
        XCTAssertFalse(otherStore.apply(stale))
        XCTAssertEqual(copied.title, "胸 · 三头")

        // 删除用墓碑标记
        dto.isRemoved = true
        dto.updatedAt = dto.updatedAt.addingTimeInterval(10)
        XCTAssertTrue(otherStore.apply(dto))
        XCTAssertTrue(copied.isRemoved)
    }

    func testExerciseSettingsSync() throws {
        let store = DataStore(context: context)
        let bench = try XCTUnwrap(HistoryService(context: context).exercise(id: "barbell-bench-press"))
        bench.lastRestSeconds = 180
        bench.touch()
        let dto = store.dto(bench)

        let otherContainer = Persistence.makeContainer(inMemory: true)
        let other = otherContainer.mainContext
        XCTAssertTrue(DataStore(context: other).apply(dto))
        let otherBench = try XCTUnwrap(HistoryService(context: other).exercise(id: "barbell-bench-press"))
        XCTAssertEqual(otherBench.lastRestSeconds, 180)
    }

    func testBackupContainsOnlyChangedExercises() throws {
        _ = makeWorkout(daysAgo: 1, sets: [SetValues(weightKg: 60, reps: 10)])
        let custom = Exercise(id: UUID().uuidString, nameZh: "我的动作", nameEn: "", muscleGroup: .chest,
                              equipment: .machine, logType: .weightReps, isCustom: true, updatedAt: .now)
        context.insert(custom)
        try context.save()
        let backup = DataStore(context: context).backup()
        XCTAssertEqual(backup.exercises.map(\.nameZh), ["我的动作"])
        XCTAssertEqual(backup.workouts.count, 1)
    }

    func testAutoTitle() throws {
        let w = makeWorkout(daysAgo: 0, sets: [SetValues(weightKg: 60, reps: 10)])
        let we = WorkoutExercise(order: 1, exerciseId: "triceps-rope-pushdown")
        context.insert(we)
        we.workout = w
        let exercises = try context.fetch(FetchDescriptor<Exercise>()).byId
        XCTAssertEqual(HistoryService.autoTitle(for: w, exercises: exercises), "胸 · 三头")
    }

    func testWorkoutOpsLogAndFinish() throws {
        let ops = WorkoutOps(context: context)
        _ = makeWorkout(daysAgo: 3, sets: [SetValues(weightKg: 60, reps: 8)])
        let bench = try XCTUnwrap(HistoryService(context: context).exercise(id: "barbell-bench-press"))
        let w = ops.startWorkout()
        let we = ops.addExercise(bench.id, to: w)
        XCTAssertTrue(ops.addExercise(bench.id, to: w) === we, "同一动作不重复添加")
        _ = ops.addExercise("plank", to: w)
        XCTAssertEqual(ops.logSet(SetValues(weightKg: 40, reps: 10, isWarmup: true), in: we, exercise: bench).records, [])
        XCTAssertEqual(ops.logSet(SetValues(weightKg: 65, reps: 5), in: we, exercise: bench).records, [.maxWeight])
        ops.finish(w)
        XCTAssertNotNil(w.endedAt)
        XCTAssertEqual(w.exercises.count, 1, "没记组的动作在结束时去掉")
        XCTAssertEqual(w.title, "胸")
    }

    func testBackfillRelabelsLaterSessions() throws {
        let ops = WorkoutOps(context: context)
        let later = makeWorkout(daysAgo: 1, sets: [SetValues(weightKg: 60, reps: 8)])
        let earlier = makeWorkout(daysAgo: 5, sets: [SetValues(weightKg: 50, reps: 8)])
        let bench = try XCTUnwrap(HistoryService(context: context).exercise(id: "barbell-bench-press"))
        let laterExercise = try XCTUnwrap(later.exercises.first)
        HistoryService(context: context).relabelRecords(in: laterExercise, exercise: bench)
        XCTAssertEqual(laterExercise.sets.first?.prKinds, [.maxWeight, .e1RM])

        // 在更早的日期补录一组更重的：之后那次不再算个人最佳
        let backfill = ops.startWorkout(at: earlier.startedAt.addingTimeInterval(-86400))
        let we = ops.addExercise(bench.id, to: backfill)
        ops.logSet(SetValues(weightKg: 70, reps: 5), in: we, exercise: bench, at: backfill.startedAt)
        ops.finish(backfill, at: backfill.startedAt.addingTimeInterval(3600))
        let changed = ops.relabelSessions(after: backfill.startedAt, exerciseIds: [bench.id])
        XCTAssertTrue(changed.contains { $0.id == later.id })
        XCTAssertEqual(laterExercise.sets.first?.prKinds, [])
    }

    func testDropSetPersistsAndSyncs() throws {
        let w = makeWorkout(daysAgo: 0, sets: [SetValues(weightKg: 6, reps: 12, drops: [DropStage(weightKg: 3, reps: 12)])])
        let set = try XCTUnwrap(w.exercises.first?.sets.first)
        XCTAssertEqual(set.drops, [DropStage(weightKg: 3, reps: 12)])
        XCTAssertEqual(w.volumeKg, 108, accuracy: 0.001)

        let dto = DataStore(context: context).dto(w)
        XCTAssertEqual(dto.exercises.first?.sets.first?.drops, [DropStage(weightKg: 3, reps: 12)])
        let otherContainer = Persistence.makeContainer(inMemory: true)
        let other = otherContainer.mainContext
        XCTAssertTrue(DataStore(context: other).apply(dto))
        let copied = try XCTUnwrap(other.fetch(FetchDescriptor<SetEntry>()).first)
        XCTAssertEqual(copied.values.drops, [DropStage(weightKg: 3, reps: 12)])
    }
}
