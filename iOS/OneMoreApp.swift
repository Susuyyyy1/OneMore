import HealthKit
import SwiftData
import SwiftUI

final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    /// 手表请求健康授权时，可能会转到 iPhone 上确认
    func applicationShouldRequestHealthAuthorization(_ application: UIApplication) {
        HKHealthStore().handleAuthorizationForExtension { _, error in
            if let error { print("健康授权转发失败：\(error)") }
        }
    }
}

@main
struct OneMoreApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate

    init() {
        AppSettings.register()
        Appearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .task {
                    #if DEBUG
                    DemoData.seedIfRequested(context: Persistence.shared.mainContext)
                    #endif
                    SyncService.shared.activate(container: Persistence.shared)
                }
        }
        .modelContainer(Persistence.shared)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HistoryView()
                .tabItem { Label("记录", systemImage: "list.bullet.clipboard") }
            LibraryView()
                .tabItem { Label("动作库", systemImage: "dumbbell") }
            TemplatesView()
                .tabItem { Label("模板", systemImage: "rectangle.stack") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Theme.tint)
        .foregroundStyle(Theme.ink)
    }
}

/// 在 iPhone 上修改数据后：更新时间戳、保存、同步到手表
@MainActor
enum Commit {
    static func workout(_ w: Workout, in context: ModelContext) {
        w.touch()
        save(context)
        SyncService.shared.send(workout: w)
    }

    static func exercise(_ e: Exercise, in context: ModelContext) {
        e.refreshSearchKey()
        e.touch()
        save(context)
        SyncService.shared.send(exercise: e)
    }

    static func template(_ t: WorkoutTemplate, in context: ModelContext) {
        t.touch()
        save(context)
        SyncService.shared.send(template: t)
    }

    static func save(_ context: ModelContext) {
        do { try context.save() } catch { print("保存失败：\(error)") }
    }
}
