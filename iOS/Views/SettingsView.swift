import HealthKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var sync = SyncService.shared
    @ObservedObject private var restTimer = PhoneRestTimer.shared
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.restPresets) private var presetsRaw = AppSettings.encodePresets(AppSettings.defaultPresets)
    @AppStorage(SettingsKey.defaultRest) private var defaultRest = 120
    @AppStorage(SettingsKey.restWarning) private var restWarning = true

    @State private var newMinutes = 1
    @State private var newSeconds = 0
    @State private var shareFile: ShareFile?
    @State private var showImporter = false
    @State private var message: String?

    private var presets: [Int] { AppSettings.decodePresets(presetsRaw) }

    var body: some View {
        NavigationStack {
            PaperForm {
                Section("重量单位") {
                    Picker("单位", selection: $unitRaw) {
                        Text("公斤 kg").tag(WeightUnit.kg.rawValue)
                        Text("磅 lb").tag(WeightUnit.lb.rawValue)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(presets, id: \.self) { Text(Fmt.clock($0)).monospacedDigit() }
                        .onDelete { offsets in
                            var list = presets
                            list.remove(atOffsets: offsets)
                            presetsRaw = AppSettings.encodePresets(list.isEmpty ? AppSettings.defaultPresets : list)
                        }
                    HStack {
                        Picker("分", selection: $newMinutes) { ForEach(0..<16) { Text("\($0) 分").tag($0) } }
                            .labelsHidden()
                        Picker("秒", selection: $newSeconds) { ForEach([0, 15, 30, 45], id: \.self) { Text("\($0) 秒").tag($0) } }
                            .labelsHidden()
                        Spacer()
                        Button("添加") {
                            let s = newMinutes * 60 + newSeconds
                            guard s > 0 else { return }
                            presetsRaw = AppSettings.encodePresets(presets + [s])
                        }
                    }
                    Picker("新动作默认选中", selection: $defaultRest) {
                        ForEach(Array(Set(presets + [defaultRest])).sorted(), id: \.self) { Text(Fmt.clock($0)).tag($0) }
                    }
                    Toggle("剩 10 秒时轻震提醒", isOn: $restWarning)
                } header: {
                    Text("组间休息快捷时长")
                } footer: {
                    Text("手表上记完一组后会显示这些按钮，点一下开始倒计时。每个动作会单独记住你上次选的时长。")
                }

                Section {
                    LabeledContent("休息结束通知", value: notificationText)
                    if restTimer.notificationStatus == .notDetermined {
                        Button("允许通知") { Task { await restTimer.requestAuthorizationIfNeeded() } }
                    } else if restTimer.notificationsBlocked {
                        Button("去系统设置开启") { PhoneRestTimer.openNotificationSettings() }
                    }
                } header: {
                    Text("通知")
                } footer: {
                    Text("在手机上休息倒计时时，切到别的 app 也会在灵动岛和锁屏显示剩余时间，时间到了会弹通知提醒。开着专注模式时，请把 One More 加入允许通知的 app。")
                }

                Section("与手表同步") {
                    LabeledContent("Apple Watch", value: sync.isCounterpartAvailable ? "已配对" : (sync.isActivated ? "未配对" : "未激活"))
                    if let at = sync.lastReceivedAt {
                        LabeledContent("最近收到数据", value: at.formatted(.dateTime.month().day().hour().minute()))
                    }
                    if sync.pendingTransfers > 0 {
                        LabeledContent("等待发送", value: "\(sync.pendingTransfers) 条")
                    }
                    Button("立即全量同步") {
                        sync.fullSync()
                        sync.pushSettings()
                        message = "已开始同步。手表在附近并解锁时会自动完成。"
                    }
                    .disabled(!sync.isCounterpartAvailable)
                }

                Section {
                    Button("导出 JSON 备份") { export { try BackupExporter.writeJSON(context: context) } }
                    Button("导出 CSV（可用 Excel 打开）") { export { try BackupExporter.writeCSV(context: context) } }
                    Button("从 JSON 备份恢复") { showImporter = true }
                } header: {
                    Text("备份")
                } footer: {
                    Text("免费开发者账号无法使用 iCloud。删除 app 会清空数据，建议定期导出 JSON 备份（可存到“文件”或发给自己）。恢复时会合并，不会删除现有记录。")
                }

                Section {
                    Text("训练时由手表记录心率和卡路里，结束后以“传统力量训练”写入健康 app，计入活动圆环。第一次在手表上开始训练时会请求授权。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("在 iPhone 上授权健康数据") { requestHealth() }
                } header: {
                    Text("健康")
                }

                Section("记录约定") {
                    Label("哑铃记录单只哑铃的重量", systemImage: "dumbbell")
                    Label("杠铃记录含杆的总重量", systemImage: "scalemass")
                    Label("单侧动作记录每侧的次数", systemImage: "hand.raised")
                    Label("热身组不计入组数、容量和个人最佳", systemImage: "flame")
                }
                .font(.callout)

                Section {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("设置")
            .onChange(of: unitRaw) { sync.pushSettings() }
            .onChange(of: presetsRaw) { sync.pushSettings() }
            .onChange(of: defaultRest) { sync.pushSettings() }
            .onChange(of: restWarning) { sync.pushSettings() }
            .sheet(item: $shareFile) { file in ShareSheet(url: file.url) }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let count = try BackupExporter.restore(from: url, context: context)
                        message = "恢复完成，更新了 \(count) 条记录。"
                    } catch {
                        message = "恢复失败：这不是有效的 One More 备份文件。"
                    }
                case .failure(let error):
                    message = "无法打开文件：\(error.localizedDescription)"
                }
            }
            .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var notificationText: String {
        switch restTimer.notificationStatus {
        case .authorized, .provisional, .ephemeral: "已开启"
        case .denied: "已关闭"
        default: "未设置"
        }
    }

    private func export(_ make: () throws -> URL) {
        do {
            shareFile = ShareFile(url: try make())
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func requestHealth() {
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "这台设备不支持健康数据。"
            return
        }
        let store = HKHealthStore()
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        Task {
            do {
                try await store.requestAuthorization(toShare: share, read: read)
                message = "已提交授权。可以在“健康”app → 共享 → App 中随时修改。"
            } catch {
                message = "授权失败：\(error.localizedDescription)"
            }
        }
    }
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
