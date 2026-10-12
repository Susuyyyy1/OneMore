import Foundation
import HealthKit

/// 封装 HKWorkoutSession：
/// - 训练期间 app 保持在前台，抬腕直接回到 app，倒计时震动在后台也能按时触发
/// - 采集实时心率和活动千卡，结束后把“传统力量训练”写入健康 app，计入活动圆环
@MainActor
final class HealthSession: NSObject, ObservableObject {
    static let shared = HealthSession()

    @Published private(set) var heartRate: Double = 0
    @Published private(set) var activeKcal: Double = 0
    @Published private(set) var isRunning = false

    let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var endContinuation: CheckedContinuation<Void, Never>?

    struct Result {
        var workoutUUID: UUID?
        var avgHeartRate: Double?
        var activeKcal: Double?
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            print("健康授权失败：\(error)")
        }
    }

    /// 开始力量训练会话。没有授权或不可用时返回 false，记录功能不受影响。
    @discardableResult
    func start(at date: Date = .now) async -> Bool {
        guard isAvailable, session == nil else { return isRunning }
        await requestAuthorization()
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return false }

        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            attach(session: session, builder: builder)
            session.startActivity(with: date)
            try await builder.beginCollection(at: date)
            isRunning = true
            return true
        } catch {
            print("无法开始训练会话：\(error)")
            reset()
            return false
        }
    }

    /// app 崩溃或被系统结束后，系统会重新拉起 app 并交还进行中的会话
    func recover() async {
        guard isAvailable, session == nil else { return }
        let recovered: HKWorkoutSession? = await withCheckedContinuation { c in
            store.recoverActiveWorkoutSession { session, error in
                if let error { print("恢复训练会话失败：\(error)") }
                c.resume(returning: session)
            }
        }
        guard let recovered else { return }
        attach(session: recovered, builder: recovered.associatedWorkoutBuilder())
        isRunning = true
    }

    func end() async -> Result {
        guard let session, let builder else { return Result() }
        if session.state != .ended && session.state != .stopped {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                endContinuation = c
                session.end()
                // 兜底：3 秒内没收到状态回调也继续
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    self.resumeEndContinuation()
                }
            }
        }
        var result = Result()
        do {
            try await builder.endCollection(at: .now)
            let workout: HKWorkout? = try await builder.finishWorkout()
            result.workoutUUID = workout?.uuid
        } catch {
            print("保存健康训练失败：\(error)")
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        result.avgHeartRate = builder.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm)
        result.activeKcal = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        reset()
        return result
    }

    /// 放弃训练：结束会话但不保存到健康
    func discard() {
        session?.end()
        builder?.discardWorkout()
        reset()
    }

    private func attach(session: HKWorkoutSession, builder: HKLiveWorkoutBuilder) {
        self.session = session
        self.builder = builder
        session.delegate = self
        builder.delegate = self
    }

    private func resumeEndContinuation() {
        endContinuation?.resume()
        endContinuation = nil
    }

    private func reset() {
        session = nil
        builder = nil
        isRunning = false
        heartRate = 0
        activeKcal = 0
    }

    private func update(from statistics: HKStatistics) {
        switch statistics.quantityType {
        case HKQuantityType(.heartRate):
            let bpm = HKUnit.count().unitDivided(by: .minute())
            heartRate = statistics.mostRecentQuantity()?.doubleValue(for: bpm) ?? heartRate
        case HKQuantityType(.activeEnergyBurned):
            activeKcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? activeKcal
        default:
            break
        }
    }
}

extension HealthSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in self.resumeEndContinuation() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("训练会话出错：\(error)")
        Task { @MainActor in self.resumeEndContinuation() }
    }
}

extension HealthSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { ($0 as? HKQuantityType).flatMap(workoutBuilder.statistics(for:)) }
        Task { @MainActor in stats.forEach(self.update(from:)) }
    }
}
