import Foundation
import SwiftData
import CryptoKit

// MARK: - Austauschformat (Export, Import, Cloud-Backup)

struct ExerciseDTO: Codable {
    var id: UUID; var name: String; var muscle: String; var secondary: String; var kind: String
    var increment: Double; var technique: String; var isCustom: Bool; var isArchived: Bool; var createdAt: Date
    var animationKey: String?
}
struct PlanItemDTO: Codable {
    var id: UUID; var order: Int; var exerciseID: UUID; var exerciseName: String; var muscle: String; var kind: String
    var sets: Int; var repMin: Int; var repMax: Int; var targetWeight: Double; var restSeconds: Int; var perSide: Bool
    var durationMinutes: Int; var note: String
}
struct PlanDayDTO: Codable {
    var id: UUID; var name: String; var weekday: Int; var order: Int; var note: String; var items: [PlanItemDTO]
}
struct PlanDTO: Codable {
    var id: UUID; var name: String; var note: String; var createdAt: Date; var updatedAt: Date
    var isActive: Bool; var isArchived: Bool; var archivedAt: Date?; var days: [PlanDayDTO]
}
struct SetDTO: Codable {
    var id: UUID; var index: Int; var weight: Double; var reps: Int; var targetMin: Int; var targetMax: Int
    var restSeconds: Int; var completed: Bool; var completedAt: Date?; var isPR: Bool; var note: String
}
struct EntryDTO: Codable {
    var id: UUID; var order: Int; var exerciseID: UUID; var name: String; var muscle: String; var kind: String
    var targetSets: Int; var repMin: Int; var repMax: Int; var restSeconds: Int; var perSide: Bool
    var durationMinutes: Int; var doneMinutes: Int; var isDone: Bool; var note: String; var planNote: String; var sets: [SetDTO]
}
struct SessionDTO: Codable {
    var id: UUID; var startedAt: Date; var endedAt: Date?; var status: String; var pausedSeconds: Double
    var planID: UUID?; var planName: String; var dayID: UUID?; var dayName: String; var note: String
    var feeling: Int; var aiReview: String; var aiReviewAt: Date?; var updatedAt: Date; var exercises: [EntryDTO]
}
struct ProfileDTO: Codable {
    var id: UUID; var name: String; var goals: String; var weeklyTarget: Int; var bodyweight: Double
    var appearance: String; var autoReview: Bool; var restNotifications: Bool; var defaultRest: Int; var updatedAt: Date
}
struct BackupFile: Codable {
    var app: String = "Forma"
    var version: Int = 1
    var exportedAt: Date = Date()
    var exercises: [ExerciseDTO]
    var plans: [PlanDTO]
    var sessions: [SessionDTO]
    var profile: ProfileDTO?
}

enum BackupCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    static let pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

// MARK: - Modell → DTO

extension Exercise {
    var dto: ExerciseDTO {
        ExerciseDTO(id: id, name: name, muscle: muscleRaw, secondary: secondaryRaw, kind: kindRaw, increment: increment,
                    technique: technique, isCustom: isCustom, isArchived: isArchived, createdAt: createdAt,
                    animationKey: animationKey)
    }
}
extension TrainingPlan {
    var dto: PlanDTO {
        PlanDTO(id: id, name: name, note: note, createdAt: createdAt, updatedAt: updatedAt, isActive: isActive,
                isArchived: isArchived, archivedAt: archivedAt,
                days: sortedDays.map { d in
                    PlanDayDTO(id: d.id, name: d.name, weekday: d.weekday, order: d.order, note: d.note,
                               items: d.sortedItems.map { i in
                                   PlanItemDTO(id: i.id, order: i.order, exerciseID: i.exerciseID, exerciseName: i.exerciseName,
                                               muscle: i.muscleRaw, kind: i.kindRaw, sets: i.sets, repMin: i.repMin, repMax: i.repMax,
                                               targetWeight: i.targetWeight, restSeconds: i.restSeconds, perSide: i.perSide,
                                               durationMinutes: i.durationMinutes, note: i.note)
                               })
                })
    }
}
extension WorkoutSession {
    var dto: SessionDTO {
        SessionDTO(id: id, startedAt: startedAt, endedAt: endedAt, status: statusRaw, pausedSeconds: pausedSeconds,
                   planID: planID, planName: planName, dayID: dayID, dayName: dayName, note: note, feeling: feeling,
                   aiReview: aiReview, aiReviewAt: aiReviewAt, updatedAt: updatedAt,
                   exercises: sortedExercises.map { e in
                       EntryDTO(id: e.id, order: e.order, exerciseID: e.exerciseID, name: e.name, muscle: e.muscleRaw, kind: e.kindRaw,
                                targetSets: e.targetSets, repMin: e.repMin, repMax: e.repMax, restSeconds: e.restSeconds,
                                perSide: e.perSide, durationMinutes: e.durationMinutes, doneMinutes: e.doneMinutes, isDone: e.isDone,
                                note: e.note, planNote: e.planNote,
                                sets: e.sortedSets.map { s in
                                    SetDTO(id: s.id, index: s.index, weight: s.weight, reps: s.reps, targetMin: s.targetMin,
                                           targetMax: s.targetMax, restSeconds: s.restSeconds, completed: s.completed,
                                           completedAt: s.completedAt, isPR: s.isPR, note: s.note)
                                })
                   })
    }
}
extension UserProfile {
    var dto: ProfileDTO {
        ProfileDTO(id: id, name: name, goals: goals, weeklyTarget: weeklyTarget, bodyweight: bodyweight, appearance: appearance,
                   autoReview: autoReview, restNotifications: restNotifications, defaultRest: defaultRest, updatedAt: updatedAt)
    }
}

// MARK: - Export / Import

enum BackupStore {
    @MainActor
    static func snapshot(_ context: ModelContext) -> BackupFile {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let plans = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return BackupFile(exercises: exercises.map(\.dto), plans: plans.map(\.dto),
                          sessions: sessions.filter(\.isFinished).sorted { $0.startedAt < $1.startedAt }.map(\.dto),
                          profile: UserProfile.current(context).dto)
    }

    @MainActor
    static func exportJSON(_ context: ModelContext) throws -> URL {
        let data = try BackupCoding.pretty.encode(snapshot(context))
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Forma-Backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Alle Sätze als CSV (für Excel/Numbers)
    @MainActor
    static func exportCSV(_ context: ModelContext) throws -> URL {
        let sessions = Analytics.finished((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? [])
        var lines = ["Datum;Einheit;Plan;Übung;Satz;Gewicht kg;Wdh.;Ziel Wdh.;Pause s;Rekord;Notiz"]
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        for s in sessions {
            let date = s.startedAt.formatted(.iso8601.year().month().day())
            for e in s.sortedExercises {
                if e.kind == .duration {
                    lines.append([date, esc(s.title), esc(s.planName), esc(e.name), "", "", "", "", "",
                                  "", esc("\(e.doneMinutes > 0 ? e.doneMinutes : e.durationMinutes) min")].joined(separator: ";"))
                    continue
                }
                for set in e.completedSets {
                    lines.append([date, esc(s.title), esc(s.planName), esc(e.name), "\(set.index + 1)",
                                  Fmt.num(set.weight, emptyZero: false), "\(set.reps)", Fmt.reps(set.targetMin, set.targetMax),
                                  "\(set.restSeconds)", set.isPR ? "ja" : "", esc(e.note)].joined(separator: ";"))
                }
            }
        }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Forma-Saetze-\(stamp).csv")
        try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    struct ImportResult { var exercises = 0, plans = 0, sessions = 0 }

    /// Fügt fehlende Daten hinzu. Bereits vorhandene Einheiten werden nie überschrieben,
    /// Pläne nur, wenn die importierte Version neuer ist.
    @MainActor
    static func merge(_ file: BackupFile, into context: ModelContext) throws -> ImportResult {
        var result = ImportResult()
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var exByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for d in file.exercises {
            if let e = exByID[d.id] {
                if d.isCustom { e.name = d.name; e.technique = d.technique }
                if let k = d.animationKey, !k.isEmpty, e.animationKey.isEmpty { e.animationKey = k }
                continue
            }
            let e = Exercise(id: d.id, name: d.name, muscle: MuscleGroup(rawValue: d.muscle) ?? .other,
                             kind: ExerciseKind(rawValue: d.kind) ?? .weighted, increment: d.increment,
                             technique: d.technique, isCustom: d.isCustom)
            e.secondaryRaw = d.secondary
            e.animationKey = d.animationKey ?? ""
            e.isArchived = d.isArchived
            e.createdAt = d.createdAt
            context.insert(e)
            exByID[d.id] = e
            result.exercises += 1
        }

        let plans = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        let planByID = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in file.plans {
            if let existing = planByID[p.id] {
                guard p.updatedAt > existing.updatedAt.addingTimeInterval(1) else { continue }
                context.delete(existing)
            }
            insertPlan(p, context: context)
            result.plans += 1
        }
        if !((try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []).contains(where: \.isActive),
           let first = ((try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []).first(where: { !$0.isArchived }) {
            first.isActive = true
        }

        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let sessionByID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for s in file.sessions {
            if let existing = sessionByID[s.id] {
                if existing.aiReview.isEmpty && !s.aiReview.isEmpty { existing.aiReview = s.aiReview; existing.aiReviewAt = s.aiReviewAt }
                continue
            }
            insertSession(s, context: context)
            result.sessions += 1
        }

        if let pd = file.profile {
            let p = UserProfile.current(context)
            if pd.updatedAt > p.updatedAt {
                p.name = pd.name; p.goals = pd.goals; p.weeklyTarget = pd.weeklyTarget; p.bodyweight = pd.bodyweight
                p.appearance = pd.appearance; p.autoReview = pd.autoReview; p.restNotifications = pd.restNotifications
                p.defaultRest = pd.defaultRest; p.updatedAt = pd.updatedAt
            }
        }
        try context.save()
        return result
    }

    @MainActor
    private static func insertPlan(_ p: PlanDTO, context: ModelContext) {
        let plan = TrainingPlan(id: p.id, name: p.name, note: p.note)
        plan.createdAt = p.createdAt; plan.updatedAt = p.updatedAt
        plan.isActive = p.isActive; plan.isArchived = p.isArchived; plan.archivedAt = p.archivedAt
        context.insert(plan)
        for d in p.days {
            let day = PlanDay(id: d.id, name: d.name, weekday: d.weekday, order: d.order, note: d.note)
            day.plan = plan
            context.insert(day)
            for i in d.items {
                let item = PlanItem(id: i.id, order: i.order, exerciseID: i.exerciseID, exerciseName: i.exerciseName,
                                    muscleRaw: i.muscle, kindRaw: i.kind)
                item.sets = i.sets; item.repMin = i.repMin; item.repMax = i.repMax
                item.targetWeight = i.targetWeight; item.restSeconds = i.restSeconds; item.perSide = i.perSide
                item.durationMinutes = i.durationMinutes; item.note = i.note
                item.day = day
                context.insert(item)
            }
        }
    }

    @MainActor
    private static func insertSession(_ s: SessionDTO, context: ModelContext) {
        let session = WorkoutSession(id: s.id, startedAt: s.startedAt, planID: s.planID, planName: s.planName,
                                     dayID: s.dayID, dayName: s.dayName)
        session.endedAt = s.endedAt; session.statusRaw = SessionStatus.finished.rawValue; session.pausedSeconds = s.pausedSeconds
        session.note = s.note; session.feeling = s.feeling; session.aiReview = s.aiReview; session.aiReviewAt = s.aiReviewAt
        session.updatedAt = s.updatedAt
        context.insert(session)
        for e in s.exercises {
            let entry = SessionExercise(id: e.id, order: e.order, exerciseID: e.exerciseID, name: e.name, muscleRaw: e.muscle,
                                        kindRaw: e.kind, targetSets: e.targetSets, repMin: e.repMin, repMax: e.repMax,
                                        restSeconds: e.restSeconds, perSide: e.perSide, durationMinutes: e.durationMinutes,
                                        planNote: e.planNote)
            entry.doneMinutes = e.doneMinutes; entry.isDone = e.isDone; entry.note = e.note
            entry.session = session
            context.insert(entry)
            for st in e.sets {
                let set = SetLog(id: st.id, index: st.index, weight: st.weight, reps: st.reps, targetMin: st.targetMin,
                                 targetMax: st.targetMax, restSeconds: st.restSeconds)
                set.completed = st.completed; set.completedAt = st.completedAt; set.isPR = st.isPR; set.note = st.note
                set.entry = entry
                context.insert(set)
            }
        }
    }

    // MARK: Datensätze für das Cloud-Backup

    struct Record { var kind: String; var id: UUID; var data: Data; var hash: String }

    @MainActor
    static func records(_ context: ModelContext) -> [Record] {
        let snap = snapshot(context)
        var out: [Record] = []
        func add<T: Encodable>(_ kind: String, _ id: UUID, _ value: T) {
            guard let d = try? BackupCoding.encoder.encode(value) else { return }
            out.append(Record(kind: kind, id: id, data: d, hash: BackupCoding.hash(d)))
        }
        for e in snap.exercises { add("exercise", e.id, e) }
        for p in snap.plans { add("plan", p.id, p) }
        for s in snap.sessions { add("session", s.id, s) }
        if let p = snap.profile { add("profile", p.id, p) }
        return out
    }

    /// Cloud-Datensätze wieder zu einer Sicherung zusammensetzen
    static func file(from rows: [(kind: String, data: Data)]) -> BackupFile {
        var f = BackupFile(exercises: [], plans: [], sessions: [], profile: nil)
        for r in rows {
            switch r.kind {
            case "exercise": if let v = try? BackupCoding.decoder.decode(ExerciseDTO.self, from: r.data) { f.exercises.append(v) }
            case "plan": if let v = try? BackupCoding.decoder.decode(PlanDTO.self, from: r.data) { f.plans.append(v) }
            case "session": if let v = try? BackupCoding.decoder.decode(SessionDTO.self, from: r.data) { f.sessions.append(v) }
            case "profile": if let v = try? BackupCoding.decoder.decode(ProfileDTO.self, from: r.data) { f.profile = v }
            default: break
            }
        }
        return f
    }
}
