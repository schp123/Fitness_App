import Foundation
import SwiftData

/// Übungskatalog und Startplan (wird nur beim allerersten Start angelegt).
enum Seed {
    struct Def {
        var name: String
        var muscle: MuscleGroup
        var secondary: [MuscleGroup] = []
        var kind: ExerciseKind = .weighted
        var increment: Double = 2.5
        var technique: String = ""
    }

    static let catalog: [Def] = [
        Def(name: "Hip Thrust", muscle: .glutes, secondary: [.hamstrings, .core], increment: 5,
            technique: "Schulterblätter auf der Bankkante, Füße hüftbreit, Schienbeine oben senkrecht. Kinn zur Brust, Rippen unten lassen. Aus den Fersen hochdrücken, oben 1 s Po fest anspannen, Becken leicht nach hinten kippen. Kein Hohlkreuz."),
        Def(name: "Abduktoren (Maschine)", muscle: .abductors, secondary: [.glutes], increment: 5,
            technique: "Oberkörper leicht nach vorn lehnen für mehr Gluteus-medius-Aktivierung. Kontrolliert öffnen, außen kurz halten, langsam zurück (2–3 s)."),
        Def(name: "Cable Kickbacks", muscle: .glutes, secondary: [.hamstrings], increment: 1.25,
            technique: "Leicht nach vorn gebeugt, Rumpf stabil. Bein aus der Hüfte nach hinten-oben führen, ohne ins Hohlkreuz zu gehen. Oben Po anspannen, langsam zurück."),
        Def(name: "Romanian Deadlift", muscle: .hamstrings, secondary: [.glutes, .lowerBack], increment: 2.5,
            technique: "Knie leicht gebeugt, Hüfte nach hinten schieben, Stange nah an den Beinen. Rücken neutral, runter bis Dehnung in den Beinbeugern. Mit Po nach vorn hochkommen."),
        Def(name: "Bulgarian Split Squats", muscle: .glutes, secondary: [.quads, .adductors], increment: 2,
            technique: "Hinterer Fuß auf der Bank, vorderer Fuß weit genug vorn. Oberkörper leicht nach vorn = mehr Gluteus. Kontrolliert tief, über die ganze Fußsohle hochdrücken."),
        Def(name: "Lat Pulldown", muscle: .lats, secondary: [.biceps, .upperBack], increment: 2.5,
            technique: "Brust raus, Schultern weg von den Ohren. Stange zur oberen Brust ziehen, Ellbogen nach unten-hinten. Langsam nach oben führen."),
        Def(name: "Seated Cable Row", muscle: .upperBack, secondary: [.lats, .biceps], increment: 2.5,
            technique: "Aufrecht sitzen, Griff zum Bauch ziehen, Schulterblätter zusammen. Kein Schwung aus dem Oberkörper."),
        Def(name: "Leg Press", muscle: .quads, secondary: [.glutes, .adductors], increment: 5,
            technique: "Füße hoch und etwas breiter auf der Platte = mehr Gluteus. Tief gehen, ohne dass das Becken abrollt. Knie nicht ganz durchstrecken."),
        Def(name: "Bizepscurls", muscle: .biceps, increment: 1,
            technique: "Ellbogen am Körper, kein Schwung. Oben kurz halten, langsam ablassen."),
        Def(name: "Trizepsdrücken (Kabel)", muscle: .triceps, increment: 1.25,
            technique: "Ellbogen fixiert am Körper, nur Unterarme bewegen. Unten voll strecken."),
        Def(name: "Schulterdrücken", muscle: .shoulders, secondary: [.triceps], increment: 1,
            technique: "Rumpf fest, kein Hohlkreuz. Gewichte über den Kopf drücken, kontrolliert auf Kinnhöhe absenken."),
        Def(name: "Core-Kurs", muscle: .core, kind: .duration, increment: 0,
            technique: "Kurs – Dauer eintragen."),
        // Alternativen & Ergänzungen
        Def(name: "Glute Bridge", muscle: .glutes, secondary: [.hamstrings], increment: 5),
        Def(name: "Kniebeuge", muscle: .quads, secondary: [.glutes, .adductors, .core], increment: 2.5),
        Def(name: "Sumo Deadlift", muscle: .glutes, secondary: [.adductors, .hamstrings, .lowerBack], increment: 2.5),
        Def(name: "Hyperextension (Glute-Fokus)", muscle: .glutes, secondary: [.hamstrings, .lowerBack], kind: .bodyweight, increment: 2.5,
            technique: "Rücken leicht rund, Füße nach außen gedreht, Bewegung aus der Hüfte. Oben Po anspannen, nicht überstrecken."),
        Def(name: "Cable Pull-Through", muscle: .glutes, secondary: [.hamstrings], increment: 2.5),
        Def(name: "Reverse Lunges", muscle: .glutes, secondary: [.quads], increment: 2),
        Def(name: "Step-ups", muscle: .glutes, secondary: [.quads], increment: 2),
        Def(name: "Abduktion am Kabel", muscle: .abductors, secondary: [.glutes], increment: 1.25),
        Def(name: "Frog Pumps", muscle: .glutes, kind: .bodyweight, increment: 0),
        Def(name: "Adduktoren (Maschine)", muscle: .adductors, increment: 5),
        Def(name: "Beinbeuger (Maschine)", muscle: .hamstrings, increment: 2.5),
        Def(name: "Klimmzüge (assistiert)", muscle: .lats, secondary: [.biceps], kind: .bodyweight, increment: 2.5),
        Def(name: "Einarmiges Kurzhantelrudern", muscle: .lats, secondary: [.upperBack, .biceps], increment: 2),
        Def(name: "Face Pulls", muscle: .upperBack, secondary: [.shoulders], increment: 1.25),
        Def(name: "Seitheben", muscle: .shoulders, increment: 1),
        Def(name: "Hammercurls", muscle: .biceps, increment: 1),
        Def(name: "Trizeps Overhead (Kabel)", muscle: .triceps, increment: 1.25),
        Def(name: "Kabel-Crunch", muscle: .core, increment: 2.5),
        Def(name: "Hanging Leg Raises", muscle: .core, kind: .bodyweight, increment: 0),
        Def(name: "Pallof Press", muscle: .core, increment: 1.25),
        Def(name: "Plank", muscle: .core, kind: .duration, increment: 0),
    ]

    @MainActor
    static func runIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        guard count == 0, !UserDefaults.standard.bool(forKey: "seed.done") else {
            UserDefaults.standard.set(true, forKey: "seed.done")
            return
        }
        var byName: [String: Exercise] = [:]
        for d in catalog {
            let e = Exercise(name: d.name, muscle: d.muscle, secondary: d.secondary, kind: d.kind, increment: d.increment, technique: d.technique)
            e.animationKey = ExerciseAnimation.defaultKeys[d.name] ?? ""
            context.insert(e)
            byName[d.name] = e
        }

        let plan = TrainingPlan(name: "Glute Focus", note: "Startplan – 3× pro Woche + Badminton")
        plan.isActive = true
        context.insert(plan)

        func day(_ name: String, _ weekday: Int, _ order: Int, _ items: [(String, Int, Int, Int, Int, Bool, Int)]) {
            let d = PlanDay(name: name, weekday: weekday, order: order)
            d.plan = plan
            context.insert(d)
            for (i, it) in items.enumerated() {
                guard let e = byName[it.0] else { continue }
                let item = PlanItem(order: i, exercise: e, sets: it.1, repMin: it.2, repMax: it.3, restSeconds: it.4,
                                    perSide: it.5, durationMinutes: it.6)
                item.day = d
                context.insert(item)
            }
        }
        // (Name, Sätze, Wdh. min, Wdh. max, Pause s, pro Seite, Minuten)
        day("Core & Gluteus", 2, 0, [
            ("Core-Kurs", 1, 0, 0, 0, false, 30),
            ("Hip Thrust", 3, 10, 12, 120, false, 0),
            ("Abduktoren (Maschine)", 3, 15, 15, 75, false, 0),
            ("Cable Kickbacks", 2, 15, 15, 60, true, 0),
        ])
        day("Gluteus & Rücken", 4, 1, [
            ("Romanian Deadlift", 3, 10, 10, 120, false, 0),
            ("Bulgarian Split Squats", 3, 10, 10, 90, true, 0),
            ("Lat Pulldown", 3, 12, 12, 90, false, 0),
            ("Seated Cable Row", 3, 12, 12, 90, false, 0),
        ])
        day("Gluteus & Arme", 7, 2, [
            ("Hip Thrust", 3, 10, 12, 120, false, 0),
            ("Leg Press", 3, 12, 12, 120, false, 0),
            ("Bizepscurls", 3, 12, 12, 60, false, 0),
            ("Trizepsdrücken (Kabel)", 3, 12, 12, 60, false, 0),
            ("Schulterdrücken", 2, 12, 12, 75, false, 0),
        ])
        _ = UserProfile.current(context)
        try? context.save()
        UserDefaults.standard.set(true, forKey: "seed.done")
    }
}
