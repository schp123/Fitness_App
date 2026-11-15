import Foundation
import SwiftData
import SwiftUI

#if targetEnvironment(simulator)
/// Nur im Simulator (automatische Screenshot-Tests): erzeugt Beispiel-Historie.
/// Wird ausschließlich mit dem Startargument -demo ausgeführt, nie auf dem iPhone.
enum DemoData {
    static var gallery: Bool { ProcessInfo.processInfo.arguments.contains("-gallery") }

    @MainActor
    static func applyLaunchArguments(_ context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demo") { insert(context) }
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "training": Router.shared.tab = .training
            case "progress": Router.shared.tab = .progress
            case "coach": Router.shared.tab = .coach
            case "profile": Router.shared.tab = .profile
            default: Router.shared.tab = .home
            }
        }
        if args.contains("-active") {
            let plans = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
            if let day = plans.first(where: \.isActive)?.sortedDays.first {
                let s = WorkoutManager.shared.start(day: day, context: context)
                if let e = s.sortedExercises.first(where: { $0.kind != .duration }), let set = e.sortedSets.first {
                    set.reps = 12
                    WorkoutManager.shared.toggle(set, in: e, context: context)
                }
            }
        }
    }

    @MainActor
    static func insert(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        guard existing == 0 else { return }
        let plans = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        guard let plan = plans.first(where: \.isActive) else { return }
        let cal = Calendar.current
        let start: [String: Double] = ["Hip Thrust": 40, "Abduktoren (Maschine)": 35, "Cable Kickbacks": 7.5,
                                       "Romanian Deadlift": 30, "Bulgarian Split Squats": 8, "Lat Pulldown": 30,
                                       "Seated Cable Row": 30, "Leg Press": 80, "Bizepscurls": 6,
                                       "Trizepsdrücken (Kabel)": 12.5, "Schulterdrücken": 5]
        for week in (1...8).reversed() {
            for day in plan.sortedDays {
                guard let date = cal.date(byAdding: .day, value: -(week * 7) + day.order * 2 + 1, to: Date()) else { continue }
                let s = WorkoutSession(startedAt: date, planID: plan.id, planName: plan.name, dayID: day.id, dayName: day.name)
                s.endedAt = date.addingTimeInterval(55 * 60)
                s.status = .finished
                s.feeling = 3 + (week % 3)
                context.insert(s)
                for item in day.sortedItems {
                    let e = SessionExercise(order: item.order, exerciseID: item.exerciseID, name: item.exerciseName,
                                            muscleRaw: item.muscleRaw, kindRaw: item.kindRaw, targetSets: item.sets,
                                            repMin: item.repMin, repMax: item.repMax, restSeconds: item.restSeconds,
                                            perSide: item.perSide, durationMinutes: item.durationMinutes)
                    e.session = s
                    context.insert(e)
                    if item.kind == .duration { e.isDone = true; e.doneMinutes = item.durationMinutes; continue }
                    let base = start[item.exerciseName] ?? 10
                    let progress = Double(8 - week) * (base >= 40 ? 2.5 : 1.25) / 2
                    for i in 0..<item.sets {
                        let set = SetLog(index: i, weight: (base + progress).rounded(), reps: max(item.repMin, item.repMax - i),
                                         targetMin: item.repMin, targetMax: item.repMax, restSeconds: item.restSeconds)
                        set.completed = true
                        set.completedAt = date
                        set.entry = e
                        context.insert(set)
                    }
                }
            }
        }
        try? context.save()
        let all = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        for s in all { for e in s.exercises { Analytics.refreshPRs(e, sessions: all) } }
        try? context.save()
    }
}

/// Alle Animationen in Start- und Endposition (nur für den automatischen Test)
struct AnimationGallery: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(ExerciseAnimation.choices, id: \.key) { a in
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            ExerciseAnimationView(animation: a, animated: false, staticPhase: 0)
                            ExerciseAnimationView(animation: a, animated: false, staticPhase: 1)
                        }
                        Text(a.label).font(.system(size: 9))
                    }
                    .background(Theme.card)
                }
            }
            .padding(4)
        }
        .background(Theme.bg)
    }
}
#endif
