import XCTest
@testable import OneMore

final class PRCalculatorTests: XCTestCase {
    func testE1RM() {
        XCTAssertEqual(PRCalculator.e1RM(weightKg: 100, reps: 1), 100)
        XCTAssertEqual(PRCalculator.e1RM(weightKg: 60, reps: 10)!, 80, accuracy: 0.001)
        XCTAssertNil(PRCalculator.e1RM(weightKg: 60, reps: 15))
        XCTAssertNil(PRCalculator.e1RM(weightKg: 0, reps: 5))
    }

    func testFirstTimeIsNotARecord() {
        let set = SetValues(weightKg: 60, reps: 10)
        XCTAssertEqual(PRCalculator.newRecords(for: set, against: PRBests(), logType: .weightReps), [])
    }

    func testHeavierWeightIsRecord() {
        let history = PRCalculator.bests(from: [SetValues(weightKg: 60, reps: 10), SetValues(weightKg: 62.5, reps: 5)],
                                         logType: .weightReps)
        XCTAssertEqual(history.maxWeight, 62.5)
        // 65×5 的估算 1RM（75.8）没超过 60×10（80），只算最大重量纪录
        XCTAssertEqual(PRCalculator.newRecords(for: SetValues(weightKg: 65, reps: 5), against: history, logType: .weightReps),
                       [.maxWeight])
        XCTAssertEqual(PRCalculator.newRecords(for: SetValues(weightKg: 65, reps: 8), against: history, logType: .weightReps),
                       [.maxWeight, .e1RM])
    }

    func testMoreRepsSameWeightIsE1RMRecordOnly() {
        let history = PRCalculator.bests(from: [SetValues(weightKg: 60, reps: 8)], logType: .weightReps)
        let kinds = PRCalculator.newRecords(for: SetValues(weightKg: 60, reps: 10), against: history, logType: .weightReps)
        XCTAssertEqual(kinds, [.e1RM])
    }

    func testWarmupIgnored() {
        let history = PRCalculator.bests(from: [SetValues(weightKg: 100, reps: 5, isWarmup: true), SetValues(weightKg: 60, reps: 5)],
                                         logType: .weightReps)
        XCTAssertEqual(history.maxWeight, 60)
        let warm = SetValues(weightKg: 80, reps: 5, isWarmup: true)
        XCTAssertEqual(PRCalculator.newRecords(for: warm, against: history, logType: .weightReps), [])
    }

    func testAssistedNeverRecords() {
        let history = PRBests(maxWeight: 20, maxE1RM: 20, maxReps: 5)
        XCTAssertEqual(PRCalculator.newRecords(for: SetValues(weightKg: 40, reps: 10), against: history, logType: .assisted), [])
    }

    func testBodyweightRepsRecord() {
        let history = PRCalculator.bests(from: [SetValues(reps: 8), SetValues(reps: 10)], logType: .bodyweight)
        XCTAssertEqual(history.maxReps, 10)
        XCTAssertEqual(PRCalculator.newRecords(for: SetValues(reps: 12), against: history, logType: .bodyweight), [.maxReps])
        XCTAssertEqual(PRCalculator.newRecords(for: SetValues(reps: 10), against: history, logType: .bodyweight), [])
    }

    func testDurationRecord() {
        let history = PRCalculator.bests(from: [SetValues(durationSec: 60)], logType: .duration)
        XCTAssertEqual(PRCalculator.newRecords(for: SetValues(durationSec: 75), against: history, logType: .duration), [.maxDuration])
    }

    func testLabelRecordsInOrder() {
        let history = PRBests(maxWeight: 60, maxE1RM: 80)
        let sets = [SetValues(weightKg: 40, reps: 10, isWarmup: true), SetValues(weightKg: 62.5, reps: 3),
                    SetValues(weightKg: 62.5, reps: 3), SetValues(weightKg: 65, reps: 1)]
        let labels = PRCalculator.labelRecords(sets: sets, history: history, logType: .weightReps)
        XCTAssertEqual(labels[0], [])
        XCTAssertEqual(labels[1], [.maxWeight])
        XCTAssertEqual(labels[2], [])
        XCTAssertEqual(labels[3], [.maxWeight])
    }
}

final class PrefillTests: XCTestCase {
    func testUsesLastSetOfCurrentSession() {
        let v = Prefill.next(current: [SetValues(weightKg: 40, reps: 12, isWarmup: true)],
                             previousSession: [SetValues(weightKg: 60, reps: 10)], target: nil,
                             logType: .weightReps, equipment: .barbell)
        XCTAssertEqual(v, SetValues(weightKg: 40, reps: 12, isWarmup: false))
    }

    func testUsesSameIndexOfPreviousSession() {
        let previous = [SetValues(weightKg: 60, reps: 10), SetValues(weightKg: 65, reps: 8)]
        let first = Prefill.next(current: [], previousSession: previous, target: nil, logType: .weightReps, equipment: .barbell)
        XCTAssertEqual(first.weightKg, 60)
    }

    func testFallsBackToTemplateThenDefaults() {
        let t = Prefill.Target(reps: 8, weightKg: 50, durationSec: nil)
        let v = Prefill.next(current: [], previousSession: [], target: t, logType: .weightReps, equipment: .barbell)
        XCTAssertEqual(v.weightKg, 50)
        XCTAssertEqual(v.reps, 8)
        let d = Prefill.next(current: [], previousSession: [], target: nil, logType: .weightReps, equipment: .barbell)
        XCTAssertEqual(d.weightKg, 20)
        XCTAssertEqual(d.reps, 10)
    }
}

final class StatsAndFormatTests: XCTestCase {
    func testVolumeExcludesWarmupsAndBodyweight() {
        let sets = [SetValues(weightKg: 40, reps: 10, isWarmup: true), SetValues(weightKg: 60, reps: 10),
                    SetValues(weightKg: 60, reps: 8), SetValues(reps: 12)]
        XCTAssertEqual(WorkoutStats.volumeKg(sets), 1080, accuracy: 0.001)
        XCTAssertEqual(WorkoutStats.workingSetCount(sets), 3)
    }

    func testUnitConversionRoundTrip() {
        let lb = WeightUnit.lb
        XCTAssertEqual(lb.fromKg(lb.toKg(135)), 135, accuracy: 0.0001)
        XCTAssertEqual(Fmt.weight(60, unit: .kg), "60kg")
        XCTAssertEqual(Fmt.weight(20, unit: .lb), "44.1lb")
        XCTAssertEqual(lb.step(forKgStep: 2.5), 5)
    }

    func testSetFormatting() {
        XCTAssertEqual(Fmt.set(SetValues(weightKg: 62.5, reps: 8), logType: .weightReps, unit: .kg), "62.5kg × 8")
        XCTAssertEqual(Fmt.set(SetValues(reps: 12), logType: .bodyweight, unit: .kg), "× 12")
        XCTAssertEqual(Fmt.set(SetValues(weightKg: 10, reps: 8), logType: .bodyweight, unit: .kg), "+10kg × 8")
        XCTAssertEqual(Fmt.set(SetValues(durationSec: 90), logType: .duration, unit: .kg), "1:30")
        XCTAssertEqual(Fmt.set(SetValues(durationSec: 1200, distanceM: 3500), logType: .cardio, unit: .kg), "20:00 · 3.5km")
    }

    func testRestPresetsParsing() {
        XCTAssertEqual(AppSettings.decodePresets("300,60, 120,60"), [60, 120, 300])
        XCTAssertEqual(AppSettings.decodePresets(""), AppSettings.defaultPresets)
    }
}

final class SearchTests: XCTestCase {
    func testPinyinInitialsAndAliases() {
        let key = SearchIndex.key(nameZh: "高位下拉", aliases: ["宽握高位下拉", "龙门架"], nameEn: "Lat Pulldown")
        XCTAssertTrue(SearchIndex.matches(key: key, query: "gwxl"))
        XCTAssertTrue(SearchIndex.matches(key: key, query: "gaowei"))
        XCTAssertTrue(SearchIndex.matches(key: key, query: "下拉"))
        XCTAssertTrue(SearchIndex.matches(key: key, query: "lat pull"))
        XCTAssertTrue(SearchIndex.matches(key: key, query: "龙门架"))
        XCTAssertFalse(SearchIndex.matches(key: key, query: "卧推"))
    }
}

final class SeedTests: XCTestCase {
    func testSeedFileIsValid() throws {
        let file = try SeedLoader.loadSeedFile()
        XCTAssertGreaterThanOrEqual(file.exercises.count, 200)
        XCTAssertEqual(Set(file.exercises.map(\.id)).count, file.exercises.count, "id 重复")
        XCTAssertEqual(Set(file.exercises.map(\.zh)).count, file.exercises.count, "中文名重复")
        XCTAssertTrue(file.exercises.allSatisfy { !$0.zh.isEmpty && !$0.en.isEmpty })
        for group in MuscleGroup.allCases {
            XCTAssertTrue(file.exercises.contains { $0.g == group }, "\(group) 没有动作")
        }
        XCTAssertTrue(file.exercises.contains { $0.zh == "杠铃卧推" })
        XCTAssertTrue(file.exercises.contains { $0.zh == "高位下拉" })
    }
}

final class HeatmapTests: XCTestCase {
    func testLevels() {
        XCTAssertEqual(TrainingHeatmap.level(sets: 0, maxSets: 20), 0)
        XCTAssertEqual(TrainingHeatmap.level(sets: 1, maxSets: 20), 1)
        XCTAssertEqual(TrainingHeatmap.level(sets: 5, maxSets: 20), 1)
        XCTAssertEqual(TrainingHeatmap.level(sets: 6, maxSets: 20), 2)
        XCTAssertEqual(TrainingHeatmap.level(sets: 15, maxSets: 20), 3)
        XCTAssertEqual(TrainingHeatmap.level(sets: 20, maxSets: 20), 4)
        XCTAssertEqual(TrainingHeatmap.level(sets: 30, maxSets: 20), 4)
    }
}
