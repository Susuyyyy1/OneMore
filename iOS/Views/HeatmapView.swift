import SwiftUI

/// 训练热力图（类似代码提交热力图）：每格一天，每列一周（周一到周日）。
/// 一屏显示约 3 个月，格子大小按宽度自动算出；往右滑可以看最近一年。
/// 颜色深浅 = 当天正式组数（不含热身），按这一年里练得最多的那天分 4 档。
struct TrainingHeatmap: View {
    let workouts: [Workout]
    let unit: WeightUnit
    /// 长按某一天（用于补录）
    var onLongPress: ((Date) -> Void)?

    @State private var selected: Date?
    @State private var width: CGFloat = 0

    private static let weekCount = 53       // 可滑动查看的总周数（约一年）
    private static let visibleWeeks = 13    // 一屏显示的周数（约 3 个月）
    private static let gap: CGFloat = 4
    private static let labelWidth: CGFloat = 14
    private static let monthRowHeight: CGFloat = 13

    private struct Day {
        var sets = 0
        var volumeKg: Double = 0
        var sessions = 0
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2   // 周一开始
        c.locale = Locale(identifier: "zh_CN")
        return c
    }

    /// 让一屏刚好放下 visibleWeeks 列
    private var cell: CGFloat {
        guard width > 0 else { return 20 }
        let available = width - Self.labelWidth - Self.gap * CGFloat(Self.visibleWeeks)
        return max(10, (available / CGFloat(Self.visibleWeeks)).rounded(.down))
    }

    var body: some View {
        let cal = calendar
        let today = cal.startOfDay(for: .now)
        let firstDay = cal.date(byAdding: .weekOfYear, value: -(Self.weekCount - 1),
                                to: cal.dateInterval(of: .weekOfYear, for: today)!.start)!
        let days = dailyStats(from: firstDay, calendar: cal)
        let maxSets = max(10, days.values.map(\.sets).max() ?? 0)
        let weeks = (0..<Self.weekCount).map { cal.date(byAdding: .weekOfYear, value: $0, to: firstDay)! }
        let size = cell

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Self.gap) {
                // 星期标签固定在左边，不跟着滑动；行高和格子一致
                VStack(spacing: Self.gap) {
                    Color.clear.frame(width: Self.labelWidth, height: Self.monthRowHeight)
                    ForEach(0..<7, id: \.self) { offset in
                        Text(["一", "", "三", "", "五", "", "日"][offset])
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: Self.labelWidth, height: size)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Self.gap) {
                        HStack(spacing: Self.gap) { monthLabels(weeks: weeks, calendar: cal, cell: size) }
                        ForEach(0..<7, id: \.self) { offset in
                            HStack(spacing: Self.gap) {
                                ForEach(weeks, id: \.self) { weekStart in
                                    let date = cal.date(byAdding: .day, value: offset, to: weekStart)!
                                    cellView(date: date, today: today, day: days[date], maxSets: maxSets, size: size)
                                }
                            }
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)   // 默认显示最近的几周
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }

            Text(caption(days: days, calendar: cal))
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
    }

    // MARK: 组成部分

    private func monthLabels(weeks: [Date], calendar cal: Calendar, cell: CGFloat) -> some View {
        ForEach(Array(weeks.enumerated()), id: \.offset) { i, weekStart in
            let month = cal.component(.month, from: weekStart)
            let isNewMonth = i == 0 || cal.component(.month, from: weeks[i - 1]) != month
            Text(isNewMonth ? "\(month)月" : "")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize()
                .frame(width: cell, height: Self.monthRowHeight, alignment: .leading)
        }
    }

    @ViewBuilder
    private func cellView(date: Date, today: Date, day: Day?, maxSets: Int, size: CGFloat) -> some View {
        if date > today {
            Color.clear.frame(width: size, height: size)
        } else {
            let level = Self.level(sets: day?.sets ?? 0, maxSets: maxSets)
            RoundedRectangle(cornerRadius: 5)
                .fill(Theme.heat[level])
                .frame(width: size, height: size)
                .overlay {
                    if selected == date {
                        RoundedRectangle(cornerRadius: 5).stroke(Theme.ink.opacity(0.7), lineWidth: 1.5)
                    } else if date == today {
                        RoundedRectangle(cornerRadius: 5).stroke(Theme.ink.opacity(0.25), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4) {
                    selected = date
                    onLongPress?(date)
                }
                .onTapGesture { selected = selected == date ? nil : date }
                .accessibilityLabel(date.formatted(.dateTime.month().day()))
                .accessibilityValue(day.map { "\($0.sets)组" } ?? "没有训练")
        }
    }

    // MARK: 数据

    /// 0 = 没练；1–4 按当天组数占最高那天的比例分档
    static func level(sets: Int, maxSets: Int) -> Int {
        guard sets > 0, maxSets > 0 else { return 0 }
        let ratio = Double(sets) / Double(maxSets)
        return min(4, max(1, Int((ratio * 4).rounded(.up))))
    }

    private func dailyStats(from firstDay: Date, calendar cal: Calendar) -> [Date: Day] {
        var result: [Date: Day] = [:]
        for w in workouts where w.startedAt >= firstDay {
            let key = cal.startOfDay(for: w.startedAt)
            var day = result[key] ?? Day()
            day.sets += w.workingSetCount
            day.volumeKg += w.volumeKg
            day.sessions += 1
            result[key] = day
        }
        return result
    }

    private func caption(days: [Date: Day], calendar cal: Calendar) -> String {
        if let selected {
            // 今年的日期不显示年份；往年的（比如滑到去年）加上年份，避免分不清
            let isThisYear = cal.isDate(selected, equalTo: .now, toGranularity: .year)
            let date = isThisYear
                ? selected.formatted(.dateTime.month().day().weekday())
                : selected.formatted(.dateTime.year().month().day().weekday())
            guard let day = days[selected], day.sessions > 0 else { return "\(date) · 没有训练" }
            return "\(date) · \(day.sets)组 · \(Fmt.volume(day.volumeKg, unit: unit))"
        }
        let monthStart = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        let thisMonth = days.filter { $0.key >= monthStart }.count
        return "最近一年练了 \(days.count) 天 · 本月 \(thisMonth) 天"
    }
}
