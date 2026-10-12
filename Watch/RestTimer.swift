import Foundation
import UserNotifications
import WatchKit

/// 组间休息倒计时。手动开始；剩 10 秒轻震一次（可在设置关闭），结束时连续强震。
@MainActor
final class RestTimer: ObservableObject {
    static let shared = RestTimer()

    @Published private(set) var endDate: Date?
    @Published private(set) var totalSeconds = 0
    @Published private(set) var isFinished = false
    /// 正在为哪个动作休息（用于在记组页面显示迷你倒计时）
    @Published private(set) var exerciseId: String?

    private var ticker: Timer?
    private var warned = false
    private let notificationId = "rest-timer"

    var isRunning: Bool { endDate != nil && !isFinished }

    var remaining: Int {
        guard let endDate else { return 0 }
        return max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
    }

    func start(seconds: Int, exerciseId: String?) {
        totalSeconds = seconds
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        self.exerciseId = exerciseId
        isFinished = false
        warned = seconds <= 10
        WKInterfaceDevice.current().play(.start)
        startTicker()
        scheduleBackupNotification()
    }

    func adjust(by delta: Int) {
        guard let endDate, !isFinished else { return }
        let newEnd = endDate.addingTimeInterval(TimeInterval(delta))
        guard newEnd.timeIntervalSinceNow > 1 else { return }
        self.endDate = newEnd
        totalSeconds = max(totalSeconds + delta, remaining)
        if remaining > 10 { warned = false }
        WKInterfaceDevice.current().play(.click)
        scheduleBackupNotification()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isFinished = false
        exerciseId = nil
        cancelBackupNotification()
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard endDate != nil, !isFinished else { return }
        let left = remaining
        if !warned, left <= 10, AppSettings.restWarning {
            warned = true
            WKInterfaceDevice.current().play(.directionUp)
        }
        if left <= 0 {
            finish()
        }
    }

    private func finish() {
        isFinished = true
        ticker?.invalidate()
        ticker = nil
        cancelBackupNotification()
        Task { @MainActor in
            let device = WKInterfaceDevice.current()
            for i in 0..<3 {
                device.play(.notification)
                if i < 2 { try? await Task.sleep(for: .milliseconds(900)) }
            }
        }
    }

    // MARK: 兜底通知
    // 没有健康授权时训练会话不运行，放下手腕后 app 会被挂起，计时器不会触发；
    // 这时用本地通知在倒计时结束时提醒。

    private func scheduleBackupNotification() {
        cancelBackupNotification()
        guard !HealthSession.shared.isRunning, let endDate else { return }
        let interval = endDate.timeIntervalSinceNow
        guard interval > 1 else { return }
        let id = notificationId
        UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "休息结束"
            content.body = "开始下一组吧 💪"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    private func cancelBackupNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
    }
}
