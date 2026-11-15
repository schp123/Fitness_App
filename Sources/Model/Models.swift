import Foundation
import SwiftData

// MARK: - Aufzählungen (als String gespeichert)

enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case glutes, hamstrings, quads, abductors, adductors, lats, upperBack, lowerBack, chest, shoulders, biceps, triceps, core, calves, cardio, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .glutes: "Gluteus"
        case .hamstrings: "Beinbeuger"
        case .quads: "Beinstrecker"
        case .abductors: "Abduktoren"
        case .adductors: "Adduktoren"
        case .lats: "Latissimus"
        case .upperBack: "Oberer Rücken"
        case .lowerBack: "Unterer Rücken"
        case .chest: "Brust"
        case .shoulders: "Schultern"
        case .biceps: "Bizeps"
        case .triceps: "Trizeps"
        case .core: "Core"
        case .calves: "Waden"
        case .cardio: "Ausdauer"
        case .other: "Sonstiges"
        }
    }
    /// Grobe Region für Statistiken
    var region: BodyRegion {
        switch self {
        case .glutes, .abductors: .glutes
        case .hamstrings, .quads, .adductors, .calves: .legs
        case .lats, .upperBack, .lowerBack: .back
        case .chest, .shoulders: .shoulders
        case .biceps, .triceps: .arms
        case .core: .core
        case .cardio, .other: .other
        }
    }
}

enum BodyRegion: String, CaseIterable, Identifiable {
    case glutes, legs, back, arms, shoulders, core, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .glutes: "Gluteus"
        case .legs: "Beine"
        case .back: "Rücken"
        case .arms: "Arme"
        case .shoulders: "Schultern/Brust"
        case .core: "Core"
        case .other: "Sonstiges"
        }
    }
    /// Orientierung: harte Sätze pro Woche (Aufbau)
    var weeklyTarget: ClosedRange<Double> {
        switch self {
        case .glutes: 12...20
        case .legs: 6...14
        case .back: 8...16
        case .arms: 6...12
        case .shoulders: 4...10
        case .core: 4...12
        case .other: 0...0
        }
    }
}

enum ExerciseKind: String, CaseIterable, Identifiable, Codable {
    case weighted, bodyweight, duration
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weighted: "Mit Gewicht"
        case .bodyweight: "Körpergewicht"
        case .duration: "Zeit (Kurs/Cardio)"
        }
    }
}

enum SessionStatus: String, Codable { case active, paused, finished }

// MARK: - Übung (Katalog)

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var muscleRaw: String = MuscleGroup.glutes.rawValue
    /// Sekundäre Muskeln, kommagetrennt (rawValues)
    var secondaryRaw: String = ""
    var kindRaw: String = ExerciseKind.weighted.rawValue
    var increment: Double = 2.5
    var technique: String = ""
    var isCustom: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = Date()
    /// Schlüssel der Bewegungsanimation ("" = Standard nach Name bzw. keine)
    var animationKey: String = ""

    init(id: UUID = UUID(), name: String, muscle: MuscleGroup, secondary: [MuscleGroup] = [], kind: ExerciseKind = .weighted,
         increment: Double = 2.5, technique: String = "", isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.muscleRaw = muscle.rawValue
        self.secondaryRaw = secondary.map(\.rawValue).joined(separator: ",")
        self.kindRaw = kind.rawValue
        self.increment = increment
        self.technique = technique
        self.isCustom = isCustom
    }

    var muscle: MuscleGroup {
        get { MuscleGroup(rawValue: muscleRaw) ?? .other }
        set { muscleRaw = newValue.rawValue }
    }
    var secondary: [MuscleGroup] {
        get { secondaryRaw.split(separator: ",").compactMap { MuscleGroup(rawValue: String($0)) } }
        set { secondaryRaw = newValue.map(\.rawValue).joined(separator: ",") }
    }
    var kind: ExerciseKind {
        get { ExerciseKind(rawValue: kindRaw) ?? .weighted }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Trainingsplan

@Model
final class TrainingPlan {
    var id: UUID = UUID()
    var name: String = ""
    var note: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isActive: Bool = false
    var isArchived: Bool = false
    var archivedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \PlanDay.plan) var days: [PlanDay] = []

    init(id: UUID = UUID(), name: String, note: String = "") {
        self.id = id
        self.name = name
        self.note = note
    }

    var sortedDays: [PlanDay] { days.sorted { $0.order < $1.order } }
}

@Model
final class PlanDay {
    var id: UUID = UUID()
    var name: String = ""
    /// 0 = flexibel, 1 = Montag … 7 = Sonntag
    var weekday: Int = 0
    var order: Int = 0
    var note: String = ""
    var plan: TrainingPlan?
    @Relationship(deleteRule: .cascade, inverse: \PlanItem.day) var items: [PlanItem] = []

    init(id: UUID = UUID(), name: String, weekday: Int = 0, order: Int = 0, note: String = "") {
        self.id = id
        self.name = name
        self.weekday = weekday
        self.order = order
        self.note = note
    }

    var sortedItems: [PlanItem] { items.sorted { $0.order < $1.order } }
    var weekdayLabel: String { (1...7).contains(weekday) ? Fmt.weekdaysLong[weekday - 1] : "Flexibel" }
}

@Model
final class PlanItem {
    var id: UUID = UUID()
    var order: Int = 0
    var exerciseID: UUID = UUID()
    var exerciseName: String = ""
    var muscleRaw: String = MuscleGroup.other.rawValue
    var kindRaw: String = ExerciseKind.weighted.rawValue
    var sets: Int = 3
    var repMin: Int = 10
    var repMax: Int = 12
    /// 0 = kein festes Zielgewicht (dann zählt das letzte Gewicht)
    var targetWeight: Double = 0
    var restSeconds: Int = 90
    var perSide: Bool = false
    var durationMinutes: Int = 0
    var note: String = ""
    var day: PlanDay?

    init(id: UUID = UUID(), order: Int, exercise: Exercise, sets: Int = 3, repMin: Int = 10, repMax: Int = 12,
         targetWeight: Double = 0, restSeconds: Int = 90, perSide: Bool = false, durationMinutes: Int = 0, note: String = "") {
        self.id = id
        self.order = order
        self.exerciseID = exercise.id
        self.exerciseName = exercise.name
        self.muscleRaw = exercise.muscleRaw
        self.kindRaw = exercise.kindRaw
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
        self.targetWeight = targetWeight
        self.restSeconds = restSeconds
        self.perSide = perSide
        self.durationMinutes = durationMinutes
        self.note = note
    }

    init(id: UUID, order: Int, exerciseID: UUID, exerciseName: String, muscleRaw: String, kindRaw: String) {
        self.id = id
        self.order = order
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.muscleRaw = muscleRaw
        self.kindRaw = kindRaw
    }

    var kind: ExerciseKind { ExerciseKind(rawValue: kindRaw) ?? .weighted }
    var muscle: MuscleGroup { MuscleGroup(rawValue: muscleRaw) ?? .other }

    func assign(_ e: Exercise) {
        exerciseID = e.id
        exerciseName = e.name
        muscleRaw = e.muscleRaw
        kindRaw = e.kindRaw
        if e.kind == .duration, durationMinutes == 0 { durationMinutes = 30 }
    }

    var summary: String {
        if kind == .duration { return "\(durationMinutes) min" }
        var s = "\(sets) × \(Fmt.reps(repMin, repMax))"
        if perSide { s += " pro Seite" }
        if targetWeight > 0 { s += " · \(Fmt.kg(targetWeight))" }
        return s
    }
}

// MARK: - Trainingseinheit (Historie – unabhängig vom Plan gespeichert)

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var statusRaw: String = SessionStatus.active.rawValue
    var pausedAt: Date?
    var pausedSeconds: Double = 0
    var planID: UUID?
    var planName: String = ""
    var dayID: UUID?
    var dayName: String = ""
    var note: String = ""
    /// 1–5, 0 = keine Angabe
    var feeling: Int = 0
    var aiReview: String = ""
    var aiReviewAt: Date?
    var updatedAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session) var exercises: [SessionExercise] = []

    init(id: UUID = UUID(), startedAt: Date = Date(), planID: UUID? = nil, planName: String = "", dayID: UUID? = nil, dayName: String = "") {
        self.id = id
        self.startedAt = startedAt
        self.planID = planID
        self.planName = planName
        self.dayID = dayID
        self.dayName = dayName
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .finished }
        set { statusRaw = newValue.rawValue }
    }
    var isFinished: Bool { status == .finished }
    var sortedExercises: [SessionExercise] { exercises.sorted { $0.order < $1.order } }
    var title: String { dayName.isEmpty ? "Freies Training" : dayName }

    /// Reine Trainingszeit ohne Pausen
    func activeDuration(now: Date = Date()) -> Double {
        let end = endedAt ?? now
        var paused = pausedSeconds
        if status == .paused, let p = pausedAt { paused += now.timeIntervalSince(p) }
        return max(0, end.timeIntervalSince(startedAt) - paused)
    }

    var completedSets: [SetLog] { exercises.flatMap { $0.sets.filter(\.completed) } }
    var volume: Double { exercises.reduce(0) { $0 + $1.volume } }
    var prCount: Int { completedSets.filter(\.isPR).count }
}

@Model
final class SessionExercise {
    var id: UUID = UUID()
    var order: Int = 0
    var exerciseID: UUID = UUID()
    var name: String = ""
    var muscleRaw: String = MuscleGroup.other.rawValue
    var kindRaw: String = ExerciseKind.weighted.rawValue
    var targetSets: Int = 3
    var repMin: Int = 10
    var repMax: Int = 12
    var restSeconds: Int = 90
    var perSide: Bool = false
    var durationMinutes: Int = 0
    var doneMinutes: Int = 0
    var isDone: Bool = false
    var note: String = ""
    var planNote: String = ""
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \SetLog.entry) var sets: [SetLog] = []

    init(id: UUID = UUID(), order: Int, exerciseID: UUID, name: String, muscleRaw: String, kindRaw: String,
         targetSets: Int, repMin: Int, repMax: Int, restSeconds: Int, perSide: Bool, durationMinutes: Int, planNote: String = "") {
        self.id = id
        self.order = order
        self.exerciseID = exerciseID
        self.name = name
        self.muscleRaw = muscleRaw
        self.kindRaw = kindRaw
        self.targetSets = targetSets
        self.repMin = repMin
        self.repMax = repMax
        self.restSeconds = restSeconds
        self.perSide = perSide
        self.durationMinutes = durationMinutes
        self.planNote = planNote
    }

    var kind: ExerciseKind { ExerciseKind(rawValue: kindRaw) ?? .weighted }
    var muscle: MuscleGroup { MuscleGroup(rawValue: muscleRaw) ?? .other }
    var sortedSets: [SetLog] { sets.sorted { $0.index < $1.index } }
    var completedSets: [SetLog] { sortedSets.filter(\.completed) }
    var isComplete: Bool {
        kind == .duration ? isDone : (!sets.isEmpty && sets.allSatisfy(\.completed))
    }
    var volume: Double {
        let factor: Double = perSide ? 2 : 1
        return completedSets.reduce(0) { $0 + $1.weight * Double($1.reps) * factor }
    }
    var topWeight: Double { completedSets.map(\.weight).max() ?? 0 }
    var bestE1RM: Double { completedSets.map { Analytics.e1RM($0.weight, $0.reps) }.max() ?? 0 }
    var setsText: String {
        if kind == .duration { return isDone ? "\(doneMinutes > 0 ? doneMinutes : durationMinutes) min" : "–" }
        let done = completedSets
        if done.isEmpty { return "–" }
        return done.map { kind == .bodyweight && $0.weight == 0 ? "\($0.reps)" : "\(Fmt.num($0.weight))×\($0.reps)" }
            .joined(separator: ", ")
    }
}

@Model
final class SetLog {
    var id: UUID = UUID()
    var index: Int = 0
    var weight: Double = 0
    var reps: Int = 0
    var targetMin: Int = 0
    var targetMax: Int = 0
    var restSeconds: Int = 90
    var completed: Bool = false
    var completedAt: Date?
    var isPR: Bool = false
    var note: String = ""
    var entry: SessionExercise?

    init(id: UUID = UUID(), index: Int, weight: Double = 0, reps: Int = 0, targetMin: Int, targetMax: Int, restSeconds: Int) {
        self.id = id
        self.index = index
        self.weight = weight
        self.reps = reps
        self.targetMin = targetMin
        self.targetMax = targetMax
        self.restSeconds = restSeconds
    }
}

// MARK: - Profil & Einstellungen

@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""
    var goals: String = ""
    var weeklyTarget: Int = 3
    var bodyweight: Double = 0
    /// "system", "light", "dark"
    var appearance: String = "system"
    var autoReview: Bool = true
    var restNotifications: Bool = true
    var defaultRest: Int = 90
    var updatedAt: Date = Date()

    init() {}

    static let defaultGoals = """
    Hauptziel: Gluteus-Aufbau (größerer, runder Po).
    Zusätzlich: definierter Rücken, Arme und Core.
    Training: 3× pro Woche Kraft (Di, Do, So), zusätzlich Badminton.
    """

    @MainActor
    static func current(_ context: ModelContext) -> UserProfile {
        if let p = try? context.fetch(FetchDescriptor<UserProfile>()).first { return p }
        let p = UserProfile()
        p.goals = defaultGoals
        context.insert(p)
        try? context.save()
        return p
    }
}

/// Alle Modelle für den Container
enum Schema1 {
    static let models: [any PersistentModel.Type] = [
        Exercise.self, TrainingPlan.self, PlanDay.self, PlanItem.self,
        WorkoutSession.self, SessionExercise.self, SetLog.self, UserProfile.self,
    ]
}
