import Foundation
import SwiftData

/// Baut aus den gespeicherten Daten einen kompakten Text für den KI-Coach (passt ins Groq-Free-Tier-Limit).
enum CoachContext {

    @MainActor
    static func build(_ context: ModelContext, focus: WorkoutSession? = nil, exerciseName: String? = nil) -> String {
        let profile = UserProfile.current(context)
        let all = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let sessions = Analytics.finished(all)
        let plans = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let catalog = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var out: [String] = []
        out.append("ZIELE:\n\(profile.goals.trimmingCharacters(in: .whitespacesAndNewlines))")
        var meta = "Geplante Einheiten pro Woche: \(profile.weeklyTarget)."
        if profile.bodyweight > 0 { meta += " Körpergewicht: \(Fmt.kg(profile.bodyweight))." }
        meta += " Zusätzlich Badminton (Details folgen in einer späteren Version)."
        out.append(meta)

        if let plan = plans.first(where: \.isActive) {
            var p = "AKTIVER PLAN „\(plan.name)“:"
            for d in plan.sortedDays {
                let items = d.sortedItems.map { "\($0.exerciseName) \($0.summary)" }.joined(separator: "; ")
                p += "\n- \(d.weekdayLabel) – \(d.name): \(items)"
            }
            out.append(p)
        }

        // Überblick
        let weeks = Analytics.weeks(all, count: 6, catalog: catalog)
        let weekLine = weeks.map { "\(Fmt.short($0.start)): \($0.sessions)× / \(Int($0.gluteSets.rounded())) Glute-Sätze / \(Fmt.volume($0.volume))" }
            .joined(separator: " | ")
        out.append("LETZTE 6 WOCHEN (Wochenstart: Einheiten / Gluteus-Sätze / Volumen):\n\(weekLine)")
        if let last = sessions.last {
            let days = Calendar.current.dateComponents([.day], from: last.startedAt, to: Date()).day ?? 0
            out.append("Letztes Training vor \(days) Tag(en). Trainingstage in Folge: \(Analytics.consecutiveDays(all)).")
        } else {
            out.append("Noch keine abgeschlossenen Trainingseinheiten.")
        }
        let regions = Analytics.regionSets(Analytics.sessionsInLast(days: 7, all), catalog: catalog)
        if !regions.isEmpty {
            out.append("SÄTZE PRO REGION (7 Tage): " + BodyRegion.allCases.compactMap { r in
                guard let v = regions[r], v > 0 else { return nil }
                return "\(r.label) \(Fmt.num((v * 2).rounded() / 2))"
            }.joined(separator: ", "))
        }
        let notes = Analytics.recoveryNotes(all, catalog: catalog, weeklyTarget: profile.weeklyTarget)
        if !notes.isEmpty { out.append("REGENERATIONS-HINWEISE: " + notes.joined(separator: " ")) }

        // Kraftentwicklung je Übung (max. 12 meisttrainierte)
        var counts: [UUID: Int] = [:]
        for s in sessions { for e in s.exercises where e.kind != .duration && !e.completedSets.isEmpty { counts[e.exerciseID, default: 0] += 1 } }
        let top = counts.sorted { $0.value > $1.value }.prefix(12)
        if !top.isEmpty {
            var t = "KRAFTENTWICKLUNG (erste → letzte Einheit, Top-Gewicht, e1RM, Rekord):"
            for (id, _) in top {
                let h = Analytics.history(for: id, in: all)
                guard let first = h.first, let last = h.last else { continue }
                let fallback = sessions.flatMap(\.exercises).first(where: { $0.exerciseID == id })?.name ?? "Übung"
                let name = catalog[id]?.name ?? fallback
                let rec = Analytics.records(for: id, in: all)
                t += "\n- \(name): \(h.count) Einheiten; \(Fmt.short(first.date)) \(Fmt.kg(first.topWeight)) → \(Fmt.short(last.date)) \(Fmt.kg(last.topWeight)); e1RM \(Fmt.num(first.bestE1RM.rounded())) → \(Fmt.num(last.bestE1RM.rounded())); Rekord \(Fmt.kg(rec.maxWeight))×\(rec.maxWeightReps); zuletzt \(last.setsText)"
            }
            out.append(t)
        }

        // Letzte Einheiten im Detail
        let recent = sessions.suffix(focus == nil ? 6 : 4)
        if !recent.isEmpty {
            var r = "LETZTE EINHEITEN:"
            for s in recent { r += "\n" + describe(s) }
            out.append(r)
        }

        if let focus {
            var f = "ZU ANALYSIERENDE EINHEIT:\n" + describe(focus)
            for e in focus.sortedExercises where e.kind != .duration {
                if let prev = Analytics.lastEntry(e.exerciseID, in: all, excluding: focus.id) {
                    f += "\n  Vergleich \(e.name): vorher (\(Fmt.short(prev.session?.startedAt ?? Date()))) \(prev.setsText) → jetzt \(e.setsText)"
                } else {
                    f += "\n  \(e.name): erstes Mal"
                }
                if let catalogItem = catalog[e.exerciseID],
                   let a = Analytics.advice(exerciseID: e.exerciseID, kind: e.kind, repMin: e.repMin, repMax: e.repMax,
                                            targetSets: e.targetSets, increment: catalogItem.increment, sessions: all) {
                    f += " · App-Vorschlag: \(a.title) – \(a.detail)"
                }
            }
            out.append(f)
        }

        if let exerciseName {
            let match = exercises.first { $0.name.localizedCaseInsensitiveCompare(exerciseName) == .orderedSame }
            if let match {
                let h = Analytics.history(for: match.id, in: all).suffix(6)
                out.append("ÜBUNG \(match.name) (\(match.muscle.label)): " + (h.isEmpty ? "noch nicht trainiert" :
                    h.map { "\(Fmt.short($0.date)) \($0.setsText)" }.joined(separator: " | ")))
            }
        }

        return out.joined(separator: "\n\n")
    }

    static func describe(_ s: WorkoutSession) -> String {
        var line = "• \(Fmt.short(s.startedAt)) \(s.title) (\(Fmt.minutes(s.activeDuration())), Volumen \(Fmt.volume(s.volume))"
        if s.prCount > 0 { line += ", \(s.prCount) Rekord(e)" }
        if s.feeling > 0 { line += ", Gefühl \(s.feeling)/5" }
        line += "): "
        line += s.sortedExercises.map { e in
            var t = "\(e.name) \(e.setsText)"
            if e.kind != .duration { t += " (Ziel \(e.targetSets)×\(Fmt.reps(e.repMin, e.repMax)))" }
            if !e.note.isEmpty { t += " [\(e.note)]" }
            return t
        }.joined(separator: "; ")
        if !s.note.isEmpty { line += " Notiz: \(s.note)" }
        return line
    }
}

// MARK: - Chatverlauf

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: String   // "user" | "assistant"
    var text: String
    var date = Date()
    var isError = false
}

enum ChatStore {
    static func load() -> [ChatMessage] {
        guard let d = UserDefaults.standard.data(forKey: "coach.chat"),
              let m = try? JSONDecoder().decode([ChatMessage].self, from: d) else { return [] }
        return m
    }
    static func save(_ m: [ChatMessage]) {
        if let d = try? JSONEncoder().encode(Array(m.suffix(60))) { UserDefaults.standard.set(d, forKey: "coach.chat") }
    }
}
