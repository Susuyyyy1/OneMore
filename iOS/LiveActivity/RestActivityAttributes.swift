import ActivityKit
import Foundation

/// 组间休息的实时活动（灵动岛 + 锁屏倒计时）。App 和小组件扩展共用这份定义。
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var totalSeconds: Int
    }

    /// 正在休息的动作，例如“哑铃侧平举”
    var exerciseName: String
}
