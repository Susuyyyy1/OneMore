import ActivityKit
import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// iPhone 上的组间休息倒计时。
/// - 在 app 里：剩 10 秒轻震、结束时连震
/// - 切到别的 app / 锁屏：灵动岛和锁屏上的实时活动显示倒计时，结束时弹系统通知
@MainActor
final class PhoneRestTimer: ObservableObject {
    static let shared = PhoneRestTimer()

    @Published private(set) var endDate: Date?
    @Published private(set) var totalSeconds = 0
    @Published private(set) var isFinished = false
    /// 通知权限状态：关闭时在休息面板和设置里提示用户去开启
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var ticker: Timer?
    private var warned = false
    private var exerciseName = ""
    private var activity: Activity<RestActivityAttributes>?
    private let notificationId = "phone-rest-timer"

    var isActive: Bool { endDate != nil }
    var isRunning: Bool { endDate != nil && !isFinished }
    var notificationsBlocked: Bool { notificationStatus == .denied }

    private init() {
        // 回到 app 时刷新权限状态；倒计时已过点的话立刻收尾
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                await PhoneRestTimer.shared.refreshAuthorization()
                PhoneRestTimer.shared.tick()
            }
        }
        Task { await refreshAuthorization() }
    }

    // MARK: 通知权限

    func refreshAuthorization() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 开始训练时调用：还没问过就请求权限
    func requestAuthorizationIfNeeded() async {
        await refreshAuthorization()
        guard notificationStatus == .notDetermined else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    static func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: 倒计时

    func start(seconds: Int, exerciseName: String) {
        totalSeconds = seconds
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        self.exerciseName = exerciseName
        isFinished = false
        warned = seconds <= 10
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        startTicker()
        scheduleNotification()
        startActivity()
    }

    func adjust(by delta: Int) {
        guard let endDate, !isFinished else { return }
        let newEnd = endDate.addingTimeInterval(TimeInterval(delta))
        guard newEnd.timeIntervalSinceNow > 1 else { return }
        self.endDate = newEnd
        totalSeconds = max(totalSeconds + delta, Int(newEnd.timeIntervalSinceNow))
        if newEnd.timeIntervalSinceNow > 10 { warned = false }
        UISelectionFeedbackGenerator().selectionChanged()
        scheduleNotification()
        updateActivity()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isFinished = false
        cancelNotification()
        endActivity()
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    fileprivate func tick() {
        guard let endDate, !isFinished else { return }
        let left = endDate.timeIntervalSinceNow
        if !warned, left <= 10, left > 0, AppSettings.restWarning {
            warned = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if left <= 0 { finish(late: left < -2) }
    }

    /// late：倒计时是在后台结束的（用户已经收到通知了），回到 app 时不再连震
    private func finish(late: Bool) {
        isFinished = true
        ticker?.invalidate()
        ticker = nil
        endActivity()
        guard !late else { return }
        Task { @MainActor in
            let generator = UINotificationFeedbackGenerator()
            for i in 0..<3 {
                generator.notificationOccurred(.success)
                if i < 2 { try? await Task.sleep(for: .milliseconds(600)) }
            }
        }
    }

    // MARK: 系统通知（在别的 app 里也能收到）

    private func scheduleNotification() {
        cancelNotification()
        guard let endDate else { return }
        let interval = endDate.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = exerciseName.isEmpty ? "开始下一组吧 💪" : "\(exerciseName) · 开始下一组吧 💪"
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "rest"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger))
    }

    private func cancelNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
        center.removeDeliveredNotifications(withIdentifiers: [notificationId])
    }

    // MARK: 实时活动（灵动岛 + 锁屏倒计时）

    private func startActivity() {
        endActivity()
        guard let endDate, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RestActivityAttributes.ContentState(endDate: endDate, totalSeconds: totalSeconds)
        activity = try? Activity.request(
            attributes: RestActivityAttributes(exerciseName: exerciseName),
            content: ActivityContent(state: state, staleDate: endDate),
            pushType: nil
        )
    }

    private func updateActivity() {
        guard let activity, let endDate else { return }
        let state = RestActivityAttributes.ContentState(endDate: endDate, totalSeconds: totalSeconds)
        Task { await activity.update(ActivityContent(state: state, staleDate: endDate)) }
    }

    private func endActivity() {
        // 也收掉上次 app 被关掉时遗留的实时活动
        let all = Activity<RestActivityAttributes>.activities
        activity = nil
        for a in all {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

/// 通知被关闭时的提示：切到别的 app 时收不到休息结束的提醒
struct NotificationOffHint: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill").foregroundStyle(Theme.warmup)
            Text("通知已关闭，切到别的 app 时收不到休息结束的提醒")
                .font(.caption)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("去开启") { PhoneRestTimer.openNotificationSettings() }
                .font(.caption.weight(.semibold))
                .buttonStyle(.glass)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.warmup.opacity(0.08)))
    }
}
