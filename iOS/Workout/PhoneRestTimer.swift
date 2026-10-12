import Foundation
import UIKit
import UserNotifications

/// iPhone 上的组间休息倒计时：前台时剩 10 秒轻震、结束时连震；切到后台时用本地通知提醒。
@MainActor
final class PhoneRestTimer: ObservableObject {
    static let shared = PhoneRestTimer()

    @Published private(set) var endDate: Date?
    @Published private(set) var totalSeconds = 0
    @Published private(set) var isFinished = false

    private var ticker: Timer?
    private var warned = false
    private let notificationId = "phone-rest-timer"

    var isActive: Bool { endDate != nil }
    var isRunning: Bool { endDate != nil && !isFinished }

    func start(seconds: Int) {
        totalSeconds = seconds
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        isFinished = false
        warned = seconds <= 10
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        startTicker()
        scheduleNotification()
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
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isFinished = false
        cancelNotification()
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
        guard let endDate, !isFinished else { return }
        let left = endDate.timeIntervalSinceNow
        if !warned, left <= 10, AppSettings.restWarning {
            warned = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if left <= 0 { finish() }
    }

    private func finish() {
        isFinished = true
        ticker?.invalidate()
        ticker = nil
        Task { @MainActor in
            let generator = UINotificationFeedbackGenerator()
            for i in 0..<3 {
                generator.notificationOccurred(.success)
                if i < 2 { try? await Task.sleep(for: .milliseconds(600)) }
            }
        }
    }

    private func scheduleNotification() {
        cancelNotification()
        guard let endDate else { return }
        let interval = endDate.timeIntervalSinceNow
        guard interval > 1 else { return }
        let id = notificationId
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "休息结束"
            content.body = "开始下一组吧 💪"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
    }
}
