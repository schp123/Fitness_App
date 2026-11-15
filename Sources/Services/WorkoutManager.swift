import Foundation
import SwiftData
import Observation
import UserNotifications

/// Steuert das laufende Training: Starten, Pausieren, Sätze abhaken, Pausentimer, Abschließen.
@MainActor
@Observable
final class WorkoutManager {
    static let shared = WorkoutManager()

    var restEnd: Date?
    var restTotal: Int = 0
    var restLabel: String = ""
    var showActive = false
    /// Nach dem Abschließen: Zusammenfassung zeigen
    var finishedSessionID: UUID?

    // MARK: Starten

    func activeSession(_ context: ModelContext) -> WorkoutSession? {
        let all = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return all.filter { !$0.isFinished }.sorted { $0.startedAt > $1.startedAt }.first
    }

    @discardableResult
    func start(day: PlanDay?, context: ModelContext) -> WorkoutSession {
        if let running = activeSession(context) {
            showActive = true
            return running
        }
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let session = WorkoutSession(planID: day?.plan?.id, planName: day?.plan?.name ?? "",
                                     dayID: day?.id, dayName: day?.name ?? "")
        context.insert(session)
        if let day {
            for (i, item) in day.sortedItems.enumerated() {
                addEntry(to: session, order: i, exerciseID: item.exerciseID, name: item.exerciseName, muscleRaw: item.muscleRaw,
                         kindRaw: item.kindRaw, sets: item.sets, repMin: item.repMin, repMax: item.repMax,
                         restSeconds: item.restSeconds, perSide: item.perSide, durationMinutes: item.durationMinutes,
                         targetWeight: item.targetWeight, planNote: item.note, sessions: sessions, context: context)
            }
        }
        save(context)
        Task { await Self.requestNotifications() }
        showActive = true
        return session
    }

    /// Übung spontan zum laufenden Training hinzufügen (ändert den Plan nicht)
    func add(_ exercise: Exercise, to session: WorkoutSession, context: ModelContext, sets: Int = 3, repMin: Int = 10, repMax: Int = 12) {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let order = (session.exercises.map(\.order).max() ?? -1) + 1
        let profile = UserProfile.current(context)
        addEntry(to: session, order: order, exerciseID: exercise.id, name: exercise.name, muscleRaw: exercise.muscleRaw,
                 kindRaw: exercise.kindRaw, sets: exercise.kind == .duration ? 1 : sets, repMin: repMin, repMax: repMax,
                 restSeconds: profile.defaultRest, perSide: false, durationMinutes: exercise.kind == .duration ? 30 : 0,
                 targetWeight: 0, planNote: "", sessions: sessions, context: context)
        save(context)
    }

    /// Übung im laufenden Training ersetzen – bereits erledigte Sätze bleiben erhalten, wenn vorhanden.
    func replace(_ entry: SessionExercise, with exercise: Exercise, in session: WorkoutSession, context: ModelContext) {
        if entry.completedSets.isEmpty && !entry.isDone {
            let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
            let order = entry.order
            let s = entry.targetSets, mn = entry.repMin, mx = entry.repMax, rest = entry.restSeconds
            context.delete(entry)
            addEntry(to: session, order: order, exerciseID: exercise.id, name: exercise.name, muscleRaw: exercise.muscleRaw,
                     kindRaw: exercise.kindRaw, sets: exercise.kind == .duration ? 1 : s, repMin: mn, repMax: mx, restSeconds: rest,
                     perSide: false, durationMinutes: exercise.kind == .duration ? 30 : 0, targetWeight: 0, planNote: "",
                     sessions: sessions.filter { $0.id != session.id }, context: context)
        } else {
            // Erledigte Sätze behalten, neue Übung dahinter einfügen
            for e in session.exercises where e.order > entry.order { e.order += 1 }
            let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
            for s in entry.sets where !s.completed { context.delete(s) }
            addEntry(to: session, order: entry.order + 1, exerciseID: exercise.id, name: exercise.name, muscleRaw: exercise.muscleRaw,
                     kindRaw: exercise.kindRaw, sets: entry.targetSets, repMin: entry.repMin, repMax: entry.repMax,
                     restSeconds: entry.restSeconds, perSide: false, durationMinutes: 0, targetWeight: 0, planNote: "",
                     sessions: sessions, context: context)
        }
        save(context)
    }

    private func addEntry(to session: WorkoutSession, order: Int, exerciseID: UUID, name: String, muscleRaw: String, kindRaw: String,
                          sets: Int, repMin: Int, repMax: Int, restSeconds: Int, perSide: Bool, durationMinutes: Int,
                          targetWeight: Double, planNote: String, sessions: [WorkoutSession], context: ModelContext) {
        let entry = SessionExercise(order: order, exerciseID: exerciseID, name: name, muscleRaw: muscleRaw, kindRaw: kindRaw,
                                    targetSets: max(sets, 1), repMin: repMin, repMax: repMax, restSeconds: restSeconds,
                                    perSide: perSide, durationMinutes: durationMinutes, planNote: planNote)
        entry.session = session
        context.insert(entry)
        let kind = ExerciseKind(rawValue: kindRaw) ?? .weighted
        guard kind != .duration else { return }
        let last = Analytics.lastEntry(exerciseID, in: sessions, excluding: session.id)
        let lastSets = last?.completedSets ?? []
        for i in 0..<max(sets, 1) {
            var w: Double = 0
            if targetWeight > 0 { w = targetWeight }
            else if i < lastSets.count { w = lastSets[i].weight }
            else if let l = lastSets.last { w = l.weight }
            let set = SetLog(index: i, weight: w, targetMin: repMin, targetMax: repMax, restSeconds: restSeconds)
            set.entry = entry
            context.insert(set)
        }
    }

    func addSet(to entry: SessionExercise, context: ModelContext) {
        let last = entry.sortedSets.last
        let set = SetLog(index: (last?.index ?? -1) + 1, weight: last?.weight ?? 0, targetMin: entry.repMin,
                         targetMax: entry.repMax, restSeconds: entry.restSeconds)
        set.entry = entry
        context.insert(set)
        save(context)
    }

    func removeSet(_ set: SetLog, context: ModelContext) {
        context.delete(set)
        save(context)
    }

    // MARK: Sätze

    func toggle(_ set: SetLog, in entry: SessionExercise, context: ModelContext) {
        if set.completed {
            set.completed = false
            set.completedAt = nil
            set.isPR = false
        } else {
            if set.reps == 0 { set.reps = max(set.targetMax, set.targetMin) }
            set.completed = true
            set.completedAt = Date()
            Haptics.success()
            let hasMore = entry.sortedSets.contains { !$0.completed } || nextEntry(after: entry) != nil
            if hasMore && set.restSeconds > 0 { startRest(set.restSeconds, label: entry.name) }
        }
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        Analytics.refreshPRs(entry, sessions: sessions)
        entry.session?.updatedAt = Date()
        save(context)
    }

    private func nextEntry(after entry: SessionExercise) -> SessionExercise? {
        entry.session?.sortedExercises.first { $0.order > entry.order && !$0.isComplete }
    }

    // MARK: Pausieren / Abschließen

    func pause(_ session: WorkoutSession, context: ModelContext) {
        guard session.status == .active else { return }
        session.status = .paused
        session.pausedAt = Date()
        cancelRest()
        save(context)
    }

    func resume(_ session: WorkoutSession, context: ModelContext) {
        guard session.status == .paused else { return }
        if let p = session.pausedAt { session.pausedSeconds += Date().timeIntervalSince(p) }
        session.pausedAt = nil
        session.status = .active
        save(context)
    }

    func finish(_ session: WorkoutSession, context: ModelContext) {
        if session.status == .paused, let p = session.pausedAt { session.pausedSeconds += Date().timeIntervalSince(p) }
        session.pausedAt = nil
        session.endedAt = Date()
        session.status = .finished
        session.updatedAt = Date()
        // Unerledigte, leere Sätze entfernen – erledigte bleiben vollständig erhalten
        for e in session.exercises {
            for s in e.sets where !s.completed { context.delete(s) }
        }
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        for e in session.exercises { Analytics.refreshPRs(e, sessions: sessions) }
        cancelRest()
        save(context)
        showActive = false
        finishedSessionID = session.id
        Cloud.shared.scheduleBackup(context)
    }

    func discard(_ session: WorkoutSession, context: ModelContext) {
        context.delete(session)
        cancelRest()
        save(context)
        showActive = false
    }

    func save(_ context: ModelContext) {
        do { try context.save() } catch { print("Speichern fehlgeschlagen: \(error)") }
    }

    // MARK: Pausentimer

    var restRemaining: Double {
        guard let restEnd else { return 0 }
        return max(0, restEnd.timeIntervalSinceNow)
    }

    func startRest(_ seconds: Int, label: String) {
        restTotal = seconds
        restLabel = label
        restEnd = Date().addingTimeInterval(TimeInterval(seconds))
        scheduleRestNotification(seconds)
    }

    func extendRest(_ seconds: Int) {
        guard let end = restEnd else { return }
        let newEnd = max(Date(), end).addingTimeInterval(TimeInterval(seconds))
        restEnd = newEnd
        restTotal += seconds
        scheduleRestNotification(Int(newEnd.timeIntervalSinceNow.rounded()))
    }

    func cancelRest() {
        restEnd = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
    }

    private func scheduleRestNotification(_ seconds: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        guard seconds > 0, UserDefaults.standard.object(forKey: "restNotifications") as? Bool ?? true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Pause vorbei"
        content.body = restLabel.isEmpty ? "Weiter geht’s mit dem nächsten Satz." : "Nächster Satz: \(restLabel)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: "rest", content: content, trigger: trigger))
    }

    static func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}
