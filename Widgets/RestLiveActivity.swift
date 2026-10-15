import ActivityKit
import SwiftUI
import WidgetKit

// 组间休息的实时活动：锁屏横幅 + 灵动岛。时间到后系统通知提醒，这里显示“休息结束”。

private let ink = Color(red: 0x3A / 255, green: 0x30 / 255, blue: 0x27 / 255)
private let beige = Color(red: 0xE3 / 255, green: 0xD7 / 255, blue: 0xC4 / 255)
private let paper = Color(red: 0xFA / 255, green: 0xF7 / 255, blue: 0xF1 / 255)

@main
struct OneMoreWidgets: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
    }
}

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(paper.opacity(0.85))
                .activitySystemActionForegroundColor(ink)
        } dynamicIsland: { context in
            let ended = context.isStale || context.state.endDate <= .now
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("组间休息", systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(beige)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(endDate: context.state.endDate, ended: ended)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.attributes.exerciseName).font(.caption).foregroundStyle(.secondary)
                        if !ended {
                            ProgressView(timerInterval: start(context)...context.state.endDate, countsDown: true) {
                                EmptyView()
                            } currentValueLabel: { EmptyView() }
                                .tint(beige)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(beige)
            } compactTrailing: {
                Countdown(endDate: context.state.endDate, ended: ended)
                    .monospacedDigit()
                    .frame(width: 44)
                    .foregroundStyle(beige)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(beige)
            }
        }
    }

    private func start(_ context: ActivityViewContext<RestActivityAttributes>) -> Date {
        min(context.state.endDate.addingTimeInterval(-Double(max(context.state.totalSeconds, 1))), .now)
    }
}

/// 剩余时间；结束后显示“结束”
private struct Countdown: View {
    let endDate: Date
    let ended: Bool

    var body: some View {
        if ended {
            Text("结束")
        } else {
            Text(timerInterval: min(Date.now, endDate)...endDate, countsDown: true)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RestActivityAttributes>

    var body: some View {
        let ended = context.isStale || context.state.endDate <= .now
        HStack(spacing: 14) {
            Image(systemName: ended ? "bell.fill" : "timer")
                .font(.title2)
                .foregroundStyle(ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(beige))
            VStack(alignment: .leading, spacing: 2) {
                Text(ended ? "休息结束，开始下一组！" : "组间休息")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(context.attributes.exerciseName)
                    .font(.subheadline)
                    .foregroundStyle(ink.opacity(0.6))
            }
            Spacer()
            if !ended {
                Text(timerInterval: min(Date.now, context.state.endDate)...context.state.endDate, countsDown: true)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110, alignment: .trailing)
            }
        }
        .padding(16)
    }
}
