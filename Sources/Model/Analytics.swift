import Foundation

/// Kraftentwicklung, Rekorde, Volumen und Progressive-Overload-Vorschläge.
/// Alle Berechnungen lesen nur – sie verändern keine Trainingsdaten.
enum Analytics {

    // MARK: Grundformeln

    /// Geschätztes 1-Wiederholungs-Maximum (Epley)
    static func e1RM(_ weight: Double, _ reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    static func finished(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.filter(\.isFinished).sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: Verlauf pro Übung

    struct ExercisePoint: Identifiable {
        var id: UUID
        var date: Date
        var topWeight: Double
        var bestE1RM: Double
        var volume: Double
        var bestReps: Int
        var totalReps: Int
        var setsText: String
    }

    static func entries(for exerciseID: UUID, in sessions: [WorkoutSession], excluding: UUID? = nil) -> [SessionExercise] {
        finished(sessions)
            .filter { $0.id != excluding }
            .flatMap { s in s.exercises.filter { $0.exerciseID == exerciseID && !$0.completedSets.isEmpty } }
    }

    static func history(for exerciseID: UUID, in sessions: [WorkoutSession]) -> [ExercisePoint] {
        finished(sessions).compactMap { s -> ExercisePoint? in
            let es = s.exercises.filter { $0.exerciseID == exerciseID }
            let sets = es.flatMap(\.completedSets)
            guard !sets.isEmpty else { return nil }
            return ExercisePoint(id: s.id, date: s.startedAt,
                                 topWeight: sets.map(\.weight).max() ?? 0,
                                 bestE1RM: sets.map { e1RM($0.weight, $0.reps) }.max() ?? 0,
                                 volume: es.reduce(0) { $0 + $1.volume },
                                 bestReps: sets.map(\.reps).max() ?? 0,
                                 totalReps: sets.reduce(0) { $0 + $1.reps },
                                 setsText: es.map(\.setsText).joined(separator: " | "))
        }
    }

    /// Letzter abgeschlossener Eintrag dieser Übung (für „Letztes Mal“ und Vorbelegung)
    static func lastEntry(_ exerciseID: UUID, in sessions: [WorkoutSession], excluding: UUID? = nil) -> SessionExercise? {
        entries(for: exerciseID, in: sessions, excluding: excluding).last
    }

    // MARK: Rekorde

    struct Records {
        var maxWeight: Double = 0
        var maxWeightReps: Int = 0
        var maxWeightDate: Date?
        var maxE1RM: Double = 0
        var maxE1RMDate: Date?
        var maxReps: Int = 0
        var maxVolume: Double = 0
        var sessionCount: Int = 0
    }

    static func records(for exerciseID: UUID, in sessions: [WorkoutSession], excluding: UUID? = nil) -> Records {
        var r = Records()
        let es = entries(for: exerciseID, in: sessions, excluding: excluding)
        r.sessionCount = Set(es.compactMap { $0.session?.id }).count
        for e in es {
            let date = e.session?.startedAt
            r.maxVolume = max(r.maxVolume, e.volume)
            for s in e.completedSets {
                if s.weight > r.maxWeight || (s.weight == r.maxWeight && s.reps > r.maxWeightReps) {
                    r.maxWeight = s.weight; r.maxWeightReps = s.reps; r.maxWeightDate = date
                }
                let est = e1RM(s.weight, s.reps)
                if est > r.maxE1RM { r.maxE1RM = est; r.maxE1RMDate = date }
                r.maxReps = max(r.maxReps, s.reps)
            }
        }
        return r
    }

    /// Markiert Rekordsätze eines Eintrags neu (gegen alle früheren Einheiten und frühere Sätze dieser Einheit).
    /// Beim allerersten Training einer Übung gibt es noch keine Rekorde.
    static func refreshPRs(_ entry: SessionExercise, sessions: [WorkoutSession]) {
        let past = records(for: entry.exerciseID, in: sessions, excluding: entry.session?.id)
        let hasHistory = past.sessionCount > 0
        var bestWeight = past.maxWeight
        var bestE1 = past.maxE1RM
        var bestReps = past.maxReps
        let bodyweight = entry.kind == .bodyweight
        for s in entry.sortedSets {
            guard s.completed, s.reps > 0, hasHistory else { s.isPR = false; continue }
            var pr = false
            if s.weight > 0 {
                let est = e1RM(s.weight, s.reps)
                if s.weight > bestWeight + 0.001 || est > bestE1 + 0.01 { pr = true }
                bestWeight = max(bestWeight, s.weight)
                bestE1 = max(bestE1, est)
            } else if bodyweight, s.reps > bestReps {
                pr = true
            }
            bestReps = max(bestReps, s.reps)
            s.isPR = pr
        }
    }

    struct PRItem: Identifiable {
        var id: UUID { exerciseID }
        var exerciseID: UUID
        var name: String
        var muscle: MuscleGroup
        var weight: Double
        var reps: Int
        var e1RM: Double
        var date: Date
    }

    /// Bestleistung (höchstes Gewicht) je Übung
    static func allRecords(_ sessions: [WorkoutSession]) -> [PRItem] {
        var best: [UUID: PRItem] = [:]
        for s in finished(sessions) {
            for e in s.exercises where e.kind != .duration {
                for set in e.completedSets {
                    let item = PRItem(exerciseID: e.exerciseID, name: e.name, muscle: e.muscle, weight: set.weight,
                                      reps: set.reps, e1RM: e1RM(set.weight, set.reps), date: s.startedAt)
                    if let cur = best[e.exerciseID] {
                        if set.weight > cur.weight || (set.weight == cur.weight && set.reps > cur.reps) { best[e.exerciseID] = item }
                    } else {
                        best[e.exerciseID] = item
                    }
                }
            }
        }
        return best.values.sorted { $0.date > $1.date }
    }

    // MARK: Progressive Overload

    enum AdviceKind { case first, increase, hold, reduce, plateau, reps }

    struct Advice {
        var kind: AdviceKind
        var title: String
        var detail: String
        var suggestedWeight: Double?
        var icon: String {
            switch kind {
            case .first: "sparkles"
            case .increase: "arrow.up.circle.fill"
            case .hold: "equal.circle.fill"
            case .reduce: "arrow.down.circle.fill"
            case .plateau: "pause.circle.fill"
            case .reps: "plus.circle.fill"
            }
        }
    }

    static func advice(exerciseID: UUID, kind: ExerciseKind, repMin: Int, repMax: Int, targetSets: Int, increment: Double,
                       sessions: [WorkoutSession], excluding: UUID? = nil) -> Advice? {
        guard kind != .duration else { return nil }
        let past = entries(for: exerciseID, in: sessions, excluding: excluding)
        let top = max(repMax, repMin)
        guard let last = past.last else {
            return Advice(kind: .first, title: "Erstes Mal",
                          detail: "Wähle ein Gewicht, mit dem du \(top) saubere Wiederholungen schaffst – mit 1–2 Wdh. Reserve.",
                          suggestedWeight: nil)
        }
        let done = last.completedSets
        let w = done.map(\.weight).max() ?? 0
        let step = increment > 0 ? increment : 2.5

        if w == 0 {
            if done.allSatisfy({ $0.reps >= top }) && done.count >= max(targetSets, 1) {
                return Advice(kind: .reps, title: "Steigern",
                              detail: "Alle Sätze mit \(top)+ Wdh. geschafft. Nächstes Mal 2 Wdh. mehr oder etwas Zusatzgewicht.",
                              suggestedWeight: nil)
            }
            return Advice(kind: .hold, title: "Wiederholungen steigern",
                          detail: "Letztes Mal: \(last.setsText). Ziel: alle Sätze mit \(top) Wdh.", suggestedWeight: nil)
        }

        let atTop = done.filter { $0.weight == w }
        let wanted = max(targetSets, 1)

        // Plateau: 3 Einheiten mit gleichem Gewicht und ohne mehr Wiederholungen
        if past.count >= 3 {
            let recent = past.suffix(3)
            let weights = recent.map(\.topWeight)
            let reps: [Int] = recent.map { e in
                let tw = e.topWeight
                return e.completedSets.filter { $0.weight == tw }.reduce(0) { $0 + $1.reps }
            }
            if Set(weights).count == 1, let first = reps.first, let lastR = reps.last, lastR <= first,
               !(atTop.count >= wanted && atTop.allSatisfy { $0.reps >= top }) {
                return Advice(kind: .plateau, title: "Plateau",
                              detail: "Seit 3 Einheiten \(Fmt.kg(w)) ohne mehr Wiederholungen. Probiere langsamere Abwärtsphase (3 s), 1 s Pause oben oder einen Satz mehr.",
                              suggestedWeight: w)
            }
        }

        if atTop.count >= wanted && atTop.allSatisfy({ $0.reps >= top }) {
            let next = w + step
            return Advice(kind: .increase, title: "Gewicht erhöhen",
                          detail: "Letztes Mal \(atTop.count) × \(top)+ mit \(Fmt.kg(w)) geschafft. Vorschlag: \(Fmt.kg(next)) und \(max(repMin, 1)) Wdh. anpeilen.",
                          suggestedWeight: next)
        }
        let below = done.filter { $0.reps < repMin }
        let avgReps = Double(done.reduce(0) { $0 + $1.reps }) / Double(max(done.count, 1))
        if below.count >= 2 && avgReps < Double(repMin) - 2 {
            let lower = max(0, w - step)
            return Advice(kind: .reduce, title: "Etwas leichter",
                          detail: "Letztes Mal im Schnitt \(Int(avgReps.rounded())) Wdh. bei \(Fmt.kg(w)) (Ziel \(Fmt.reps(repMin, repMax))). Vorschlag: \(Fmt.kg(lower)) mit sauberer Technik.",
                          suggestedWeight: lower)
        }
        return Advice(kind: .hold, title: "Gewicht halten",
                      detail: "Bleib bei \(Fmt.kg(w)) und bring alle \(wanted) Sätze auf \(top) Wdh. Letztes Mal: \(last.setsText).",
                      suggestedWeight: w)
    }

    // MARK: Muskelgruppen & Wochen

    /// Harte Sätze je Region (Hauptmuskel 1, Nebenmuskel 0,5; Kurse: 1 Satz je 10 Minuten)
    static func regionSets(_ sessions: [WorkoutSession], catalog: [UUID: Exercise]) -> [BodyRegion: Double] {
        var out: [BodyRegion: Double] = [:]
        for s in sessions {
            for e in s.exercises {
                if e.kind == .duration {
                    guard e.isDone else { continue }
                    let mins = e.doneMinutes > 0 ? e.doneMinutes : e.durationMinutes
                    out[e.muscle.region, default: 0] += Double(mins) / 10
                    continue
                }
                let n = Double(e.completedSets.count)
                guard n > 0 else { continue }
                let primary = e.muscle.region
                out[primary, default: 0] += n
                let secondary = Set((catalog[e.exerciseID]?.secondary ?? []).map(\.region)).subtracting([primary])
                for r in secondary { out[r, default: 0] += n * 0.5 }
            }
        }
        return out
    }

    struct WeekStat: Identifiable {
        var id: Date { start }
        var start: Date
        var sessions: Int
        var volume: Double
        var minutes: Double
        var sets: Int
        var gluteSets: Double
    }

    static func weeks(_ sessions: [WorkoutSession], count: Int, catalog: [UUID: Exercise], now: Date = Date()) -> [WeekStat] {
        let cal = Calendar.iso
        let thisWeek = cal.startOfWeek(now)
        let done = finished(sessions)
        return (0..<count).reversed().compactMap { offset -> WeekStat? in
            guard let start = cal.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = cal.date(byAdding: .day, value: 7, to: start) else { return nil }
            let inWeek = done.filter { $0.startedAt >= start && $0.startedAt < end }
            let regions = regionSets(inWeek, catalog: catalog)
            return WeekStat(start: start, sessions: inWeek.count,
                            volume: inWeek.reduce(0) { $0 + $1.volume },
                            minutes: inWeek.reduce(0) { $0 + $1.activeDuration() } / 60,
                            sets: inWeek.reduce(0) { $0 + $1.completedSets.count },
                            gluteSets: regions[.glutes] ?? 0)
        }
    }

    struct MonthStat: Identifiable {
        var id: Date { start }
        var start: Date
        var sessions: Int
        var volume: Double
        var prs: Int
    }

    static func months(_ sessions: [WorkoutSession], count: Int, now: Date = Date()) -> [MonthStat] {
        let cal = Calendar.iso
        guard let thisMonth = cal.dateInterval(of: .month, for: now)?.start else { return [] }
        let done = finished(sessions)
        return (0..<count).reversed().compactMap { offset -> MonthStat? in
            guard let start = cal.date(byAdding: .month, value: -offset, to: thisMonth),
                  let end = cal.date(byAdding: .month, value: 1, to: start) else { return nil }
            let inMonth = done.filter { $0.startedAt >= start && $0.startedAt < end }
            return MonthStat(start: start, sessions: inMonth.count,
                             volume: inMonth.reduce(0) { $0 + $1.volume },
                             prs: inMonth.reduce(0) { $0 + $1.prCount })
        }
    }

    static func sessionsInLast(days: Int, _ sessions: [WorkoutSession], now: Date = Date()) -> [WorkoutSession] {
        let from = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return finished(sessions).filter { $0.startedAt >= from }
    }

    /// Trainingstage in Folge ohne Ruhetag (bis heute)
    static func consecutiveDays(_ sessions: [WorkoutSession], now: Date = Date()) -> Int {
        let cal = Calendar.current
        let days = Set(finished(sessions).map { cal.startOfDay(for: $0.startedAt) })
        var count = 0
        var d = cal.startOfDay(for: now)
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
        while days.contains(d) {
            count += 1
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return count
    }

    /// Wochen in Folge mit Ziel-Trainingsanzahl erreicht
    static func weekStreak(_ sessions: [WorkoutSession], target: Int, catalog: [UUID: Exercise]) -> Int {
        let ws = weeks(sessions, count: 52, catalog: catalog)
        var streak = 0
        for (i, w) in ws.reversed().enumerated() {
            if w.sessions >= max(target, 1) { streak += 1 }
            else if i == 0 { continue } // laufende Woche zählt nicht gegen dich
            else { break }
        }
        return streak
    }

    // MARK: Hinweise zur Regeneration

    static func recoveryNotes(_ sessions: [WorkoutSession], catalog: [UUID: Exercise], weeklyTarget: Int) -> [String] {
        var notes: [String] = []
        let streak = consecutiveDays(sessions)
        if streak >= 3 { notes.append("\(streak) Trainingstage in Folge – plane einen Ruhetag ein.") }
        let last7 = sessionsInLast(days: 7, sessions)
        let regions = regionSets(last7, catalog: catalog)
        for r in [BodyRegion.glutes, .back, .legs] {
            let v = regions[r] ?? 0
            if v > r.weeklyTarget.upperBound * 1.25 {
                notes.append("\(r.label): \(Int(v.rounded())) Sätze in 7 Tagen – über dem empfohlenen Bereich, achte auf Regeneration.")
            }
        }
        // Zwei Gluteus-Einheiten innerhalb von 24 h
        let glute = finished(sessions).filter { s in s.exercises.contains { $0.muscle.region == .glutes && !$0.completedSets.isEmpty } }
        if glute.count >= 2 {
            let a = glute[glute.count - 2].startedAt, b = glute[glute.count - 1].startedAt
            if b.timeIntervalSince(a) < 24 * 3600 && Date().timeIntervalSince(b) < 3 * 24 * 3600 {
                notes.append("Zwei Gluteus-Einheiten innerhalb von 24 h – mindestens 48 h Pause bringen meist mehr Wachstum.")
            }
        }
        if last7.count > weeklyTarget + 2 { notes.append("Mehr Einheiten als geplant diese Woche – gut, aber Schlaf und Ernährung im Blick behalten.") }
        return notes
    }
}
