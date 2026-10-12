import Foundation
import SwiftData
import WatchConnectivity

/// 手表 ↔ iPhone 同步（WatchConnectivity，不需要 iCloud，免费开发者账号可用）
/// - 单条记录：transferUserInfo，系统排队保证送达，对方 app 没打开也能收到
/// - 全量数据：transferFile（首次配对、手动“全量同步”、从备份恢复后）
/// - 设置：updateApplicationContext（只保留最新一份）
@MainActor
final class SyncService: NSObject, ObservableObject {
    static let shared = SyncService()

    @Published private(set) var isActivated = false
    @Published private(set) var isCounterpartAvailable = false
    @Published private(set) var lastReceivedAt: Date?
    @Published private(set) var pendingTransfers = 0

    private var container: ModelContainer?
    private let fullSyncKey = "didInitialFullSync"
    private let lastPushKey = "lastPushAt"

    private enum Kind: String {
        case workout, template, exercise, requestFullSync
    }

    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private var context: ModelContext? { container?.mainContext }

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        let s = WCSession.default
        return s.activationState == .activated ? s : nil
    }

    // MARK: 发送

    func send(workout: Workout) {
        guard let context else { return }
        send(kind: .workout, value: DataStore(context: context).dto(workout))
    }

    func send(template: WorkoutTemplate) {
        guard let context else { return }
        send(kind: .template, value: DataStore(context: context).dto(template))
    }

    func send(exercise: Exercise) {
        guard let context else { return }
        send(kind: .exercise, value: DataStore(context: context).dto(exercise))
    }

    private func send<T: Encodable>(kind: Kind, value: T) {
        guard let session, canSend(session),
              let data = try? DTOCoding.encoder().encode(value) else { return }
        session.transferUserInfo(["kind": kind.rawValue, "data": data])
        refreshPending()
    }

    /// 补发：把上次推送之后本机新增或改动的记录都发给对方。
    /// 每次 app 启动（会话激活）时调用，弥补断连、对方未激活等原因没发出去的数据；对方按“后写者胜”合并，重复发送没有副作用。
    func pushChanges() {
        guard let session, canSend(session), let context else { return }
        let since = UserDefaults.standard.object(forKey: lastPushKey) as? Date ?? .distantPast
        let now = Date()
        let store = DataStore(context: context)
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.endedAt != nil && $0.updatedAt > since }))) ?? []
        let templates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.updatedAt > since }))) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.updatedAt > since }))) ?? []
        exercises.filter { $0.updatedAt > .distantPast }.forEach { send(kind: .exercise, value: store.dto($0)) }
        templates.forEach { send(kind: .template, value: store.dto($0)) }
        workouts.forEach { send(kind: .workout, value: store.dto($0)) }
        UserDefaults.standard.set(now, forKey: lastPushKey)
    }

    /// 把本机全部数据发给对方，并请对方也发一份回来
    func fullSync() {
        guard let session, canSend(session), let context else { return }
        let backup = DataStore(context: context).backup(includeSettings: false)
        guard let data = try? DTOCoding.encoder().encode(backup) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("onemore-sync-\(UUID().uuidString).json")
        do {
            try data.write(to: url)
            session.transferFile(url, metadata: ["kind": "backup"])
            session.transferUserInfo(["kind": Kind.requestFullSync.rawValue])
            UserDefaults.standard.set(true, forKey: fullSyncKey)
            UserDefaults.standard.set(Date(), forKey: lastPushKey)
            refreshPending()
        } catch {
            print("全量同步写文件失败：\(error)")
        }
    }

    func pushSettings() {
        guard let session, canSend(session) else { return }
        try? session.updateApplicationContext(["settings": AppSettings.snapshot()])
    }

    /// 能否发送。transferUserInfo / transferFile 由系统排队，对方暂时不可达也会在之后送达。
    /// 注意不能依赖 isWatchAppInstalled / isCompanionAppInstalled：用命令行直接把 app 装到手表时
    /// （见 install.sh），iPhone 不知道手表装了这个 app，这两个标志会一直是 false。
    private func canSend(_ session: WCSession) -> Bool {
        #if os(iOS)
        return session.isPaired
        #else
        return true
        #endif
    }

    private func refreshPending() {
        guard let session else { return }
        pendingTransfers = session.outstandingUserInfoTransfers.count + session.outstandingFileTransfers.count
    }

    private func refreshState() {
        guard let session else {
            isCounterpartAvailable = false
            return
        }
        isCounterpartAvailable = canSend(session)
        refreshPending()
        guard isCounterpartAvailable else { return }
        if UserDefaults.standard.bool(forKey: fullSyncKey) {
            pushChanges()
        } else {
            fullSync()
        }
    }

    // MARK: 接收

    private func handle(kind: String, data: Data?) {
        guard let context, let kind = Kind(rawValue: kind) else { return }
        let store = DataStore(context: context)
        let decoder = DTOCoding.decoder()
        switch kind {
        case .workout:
            if let data, let dto = try? decoder.decode(WorkoutDTO.self, from: data) { store.apply(dto) }
        case .template:
            if let data, let dto = try? decoder.decode(TemplateDTO.self, from: data) { store.apply(dto) }
        case .exercise:
            if let data, let dto = try? decoder.decode(ExerciseDTO.self, from: data) { store.apply(dto) }
        case .requestFullSync:
            let backup = store.backup(includeSettings: false)
            if let d = try? DTOCoding.encoder().encode(backup), let session {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("onemore-sync-\(UUID().uuidString).json")
                if (try? d.write(to: url)) != nil {
                    session.transferFile(url, metadata: ["kind": "backup"])
                }
            }
        }
        try? context.save()
        lastReceivedAt = .now
    }

    private func handleBackup(data: Data) {
        guard let context, let file = try? DTOCoding.decoder().decode(BackupFile.self, from: data) else { return }
        DataStore(context: context).apply(file, applySettings: false)
        lastReceivedAt = .now
    }
}

extension SyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isActivated = activationState == .activated
            self.refreshState()
            #if os(iOS)
            self.pushSettings()
            #endif
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let kind = userInfo["kind"] as? String ?? ""
        let data = userInfo["data"] as? Data
        Task { @MainActor in self.handle(kind: kind, data: data) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // 文件在这个方法返回后会被系统删除，必须同步读出来
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in self.handleBackup(data: data) }
    }

    #if os(watchOS)
    /// 设置以 iPhone 为准
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let settings = applicationContext["settings"] as? [String: String] else { return }
        Task { @MainActor in AppSettings.apply(settings) }
    }
    #endif

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        Task { @MainActor in self.refreshPending() }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        Task { @MainActor in self.refreshPending() }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // 用户换了一块手表：重新激活，并对新手表做一次全量同步
        UserDefaults.standard.set(false, forKey: "didInitialFullSync")
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }
    #else
    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }
    #endif
}
