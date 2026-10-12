import Foundation
import SwiftData

/// JSON 备份/恢复与 CSV 导出。免费开发者账号没有 iCloud，靠这个备份数据。
@MainActor
enum BackupExporter {
    static func writeJSON(context: ModelContext) throws -> URL {
        let encoder = DTOCoding.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(DataStore(context: context).backup())
        let url = exportURL(name: "OneMore备份", ext: "json")
        try data.write(to: url)
        return url
    }

    static func writeCSV(context: ModelContext) throws -> URL {
        let exercises = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).byId
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { !$0.isRemoved && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt)]
        ))) ?? []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = ["日期,训练,动作,部位,组序号,热身,重量(kg),次数,时长(秒),距离(米),RPE,休息(秒),个人最佳,备注"]
        for w in workouts {
            for we in w.orderedExercises {
                let ex = exercises[we.exerciseId]
                for (i, s) in we.orderedSets.enumerated() {
                    let fields: [String] = [
                        dateFormatter.string(from: w.startedAt), w.title, ex?.nameZh ?? we.exerciseId,
                        ex?.muscleGroup.displayName ?? "", "\(i + 1)", s.isWarmup ? "是" : "",
                        s.weightKg.map { Fmt.number($0, maxFraction: 2) } ?? "", s.reps.map(String.init) ?? "",
                        s.durationSec.map(String.init) ?? "", s.distanceM.map { Fmt.number($0, maxFraction: 0) } ?? "",
                        s.rpe.map { Fmt.number($0) } ?? "", s.restSec.map(String.init) ?? "",
                        s.prKinds.map(\.displayName).joined(separator: "/"), s.note,
                    ]
                    lines.append(fields.map(csvEscape).joined(separator: ","))
                }
            }
        }
        // 加 BOM，Excel 打开中文不乱码
        let text = "\u{FEFF}" + lines.joined(separator: "\r\n")
        let url = exportURL(name: "OneMore训练记录", ext: "csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 合并备份文件（后写者胜，不会删除本机已有的记录），返回更新的条数
    static func restore(from url: URL, context: ModelContext) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let file = try DTOCoding.decoder().decode(BackupFile.self, from: data)
        let count = DataStore(context: context).apply(file, applySettings: true)
        SyncService.shared.fullSync()
        SyncService.shared.pushSettings()
        return count
    }

    private static func exportURL(name: String, ext: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(f.string(from: .now)).\(ext)")
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
