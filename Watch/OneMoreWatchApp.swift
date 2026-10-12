import SwiftData
import SwiftUI
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// app 在训练中被系统结束后，系统会重新拉起 app 并调用这里
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in WorkoutManager.shared.restoreActiveWorkout() }
    }
}

@main
struct OneMoreWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    init() {
        AppSettings.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(WorkoutManager.shared)
                .environmentObject(RestTimer.shared)
                .environmentObject(HealthSession.shared)
        }
        .modelContainer(Persistence.shared)
    }
}

struct RootView: View {
    @EnvironmentObject private var manager: WorkoutManager

    var body: some View {
        Group {
            if manager.workout != nil {
                ActiveWorkoutView()
            } else {
                HomeView()
            }
        }
        .sheet(item: $manager.finishedWorkout) { workout in
            SummaryView(workout: workout)
        }
        .task {
            #if DEBUG
            DemoData.seedIfRequested(context: Persistence.shared.mainContext)
            switch DemoData.screen {
            case "active", "logger", "rest": manager.startDemoWorkout()
            case "summary":
                var d = FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt != nil },
                                                 sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
                d.fetchLimit = 1
                manager.finishedWorkout = try? Persistence.shared.mainContext.fetch(d).first
            default: break
            }
            if DemoData.screen != nil { return }
            #endif
            SyncService.shared.activate(container: Persistence.shared)
            manager.restoreActiveWorkout()
        }
    }
}
