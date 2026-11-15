import SwiftUI
import SwiftData
import UserNotifications
import Observation

enum AppTab: Hashable { case home, training, progress, coach, profile }

@MainActor
@Observable
final class Router {
    static let shared = Router()
    var tab: AppTab = .home
    /// Vorbereitete Coach-Anfrage (z. B. „Übung erklären“ aus dem Training)
    var coachRequest: CoachRequest?
}

struct CoachRequest: Equatable {
    var mode: String
    var label: String
    var exerciseName: String? = nil
    var sessionID: UUID? = nil
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct FormaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Exercise.self, TrainingPlan.self, PlanDay.self, PlanItem.self,
            WorkoutSession.self, SessionExercise.self, SetLog.self, UserProfile.self,
        ])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]
    @Bindable private var router = Router.shared
    @Bindable private var workout = WorkoutManager.shared
    @State private var ready = false

    private var scheme: ColorScheme? {
        switch profiles.first?.appearance ?? "system" {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some View {
        Group {
            if ready {
                tabs
            } else {
                Theme.bg.ignoresSafeArea()
            }
        }
        .preferredColorScheme(scheme)
        .task {
            Seed.runIfNeeded(context)
            #if targetEnvironment(simulator)
            DemoData.applyLaunchArguments(context)
            #endif
            let p = UserProfile.current(context)
            UserDefaults.standard.set(p.restNotifications, forKey: "restNotifications")
            ready = true
            if WorkoutManager.shared.activeSession(context) != nil { WorkoutManager.shared.showActive = true }
            Cloud.shared.scheduleBackup(context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                try? context.save()
                Cloud.shared.scheduleBackup(context)
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            TrainingView()
                .tabItem { Label("Training", systemImage: "dumbbell") }
                .tag(AppTab.training)
            FortschrittView()
                .tabItem { Label("Fortschritt", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)
            CoachView()
                .tabItem { Label("Coach", systemImage: "sparkles") }
                .tag(AppTab.coach)
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Theme.rose)
        .fullScreenCover(isPresented: $workout.showActive) {
            ActiveWorkoutContainer()
        }
        .sheet(item: Binding(get: { workout.finishedSessionID.map { IdentifiedID(id: $0) } },
                             set: { workout.finishedSessionID = $0?.id })) { ref in
            SessionSummarySheet(sessionID: ref.id)
        }
    }
}

struct IdentifiedID: Identifiable { var id: UUID }
