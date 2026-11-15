import SwiftUI
import SwiftData
import Charts

struct FortschrittView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]
    @State private var tab = 0
    @State private var weeksBack = 12

    private var catalog: [UUID: Exercise] { Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var finished: [WorkoutSession] { sessions.filter(\.isFinished) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("", selection: $tab) {
                        Text("Übersicht").tag(0)
                        Text("Übungen").tag(1)
                        Text("Rekorde").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if finished.isEmpty {
                        Card { EmptyHint(icon: "chart.line.uptrend.xyaxis", title: "Noch keine Daten",
                                         text: "Nach deinem ersten abgeschlossenen Training siehst du hier deine Entwicklung.") }
                    } else {
                        switch tab {
                        case 0: overview
                        case 1: exerciseList
                        default: recordList
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Fortschritt")
        }
    }

    // MARK: Übersicht

    @ViewBuilder
    private var overview: some View {
        let weeks = Analytics.weeks(sessions, count: weeksBack, catalog: catalog)
        let target = profiles.first?.weeklyTarget ?? 3
        Picker("Zeitraum", selection: $weeksBack) {
            Text("8 Wochen").tag(8)
            Text("12 Wochen").tag(12)
            Text("6 Monate").tag(26)
        }
        .pickerStyle(.segmented)

        HStack(spacing: 10) {
            StatTile(value: "\(weeks.reduce(0) { $0 + $1.sessions })", label: "Einheiten", icon: "dumbbell")
            StatTile(value: Fmt.volume(weeks.reduce(0) { $0 + $1.volume }), label: "Volumen", icon: "scalemass")
            StatTile(value: Fmt.num((Double(weeks.reduce(0) { $0 + $1.sessions }) / Double(max(weeks.count, 1)) * 10).rounded() / 10, emptyZero: false),
                     label: "Ø pro Woche", icon: "calendar")
        }

        Card {
            SectionTitle(text: "Trainingshäufigkeit", trailing: "Ziel \(target)×")
            Chart {
                ForEach(weeks) { w in
                    BarMark(x: .value("Woche", w.start, unit: .weekOfYear), y: .value("Einheiten", w.sessions))
                        .foregroundStyle(w.sessions >= target ? Theme.rose : Theme.rose.opacity(0.45))
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Ziel", target)).foregroundStyle(Theme.ink.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: weeksBack > 12 ? 4 : 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.twoDigits)) } }
            .frame(height: 150)
        }

        Card {
            SectionTitle(text: "Trainingsvolumen", trailing: "kg pro Woche")
            Chart(weeks) { w in
                BarMark(x: .value("Woche", w.start, unit: .weekOfYear), y: .value("Volumen", w.volume))
                    .foregroundStyle(Theme.chart[1])
                    .cornerRadius(4)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: weeksBack > 12 ? 4 : 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.twoDigits)) } }
            .frame(height: 150)
        }

        Card {
            SectionTitle(text: "Gluteus-Fortschritt", trailing: "Sätze pro Woche")
            Chart {
                RuleMark(y: .value("min", 12)).foregroundStyle(Theme.rose.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                RuleMark(y: .value("max", 20)).foregroundStyle(Theme.rose.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ForEach(weeks) { w in
                    BarMark(x: .value("Woche", w.start, unit: .weekOfYear), y: .value("Sätze", w.gluteSets))
                        .foregroundStyle(Theme.rose)
                        .cornerRadius(4)
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: weeksBack > 12 ? 4 : 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.twoDigits)) } }
            .frame(height: 150)
            Text("Gestrichelte Linien = empfohlener Bereich für Muskelaufbau (12–20 harte Sätze). Nebenmuskel-Sätze zählen halb.")
                .font(.caption).foregroundStyle(Theme.muted)
            gluteExercises
        }

        muscleLoad

        Card {
            SectionTitle(text: "Monate")
            ForEach(Analytics.months(sessions, count: 6).reversed()) { m in
                HStack {
                    Text(m.start.formatted(.dateTime.month(.wide).year().locale(Fmt.de))).font(.subheadline)
                    Spacer()
                    Text("\(m.sessions)×").font(.subheadline.weight(.semibold)).frame(width: 40, alignment: .trailing)
                    Text(Fmt.volume(m.volume)).font(.caption).foregroundStyle(Theme.muted).frame(width: 70, alignment: .trailing)
                    Text("\(m.prs) ★").font(.caption).foregroundStyle(Theme.roseInk).frame(width: 40, alignment: .trailing)
                }
            }
        }

        NavigationLink { CompareView() } label: { Label("Einheiten vergleichen", systemImage: "arrow.left.arrow.right") }
            .buttonStyle(SoftButtonStyle())
    }

    @ViewBuilder
    private var gluteExercises: some View {
        let gluteIDs = exercises.filter { $0.muscle.region == .glutes && $0.kind != .duration }.map(\.id)
        let trained = gluteIDs.compactMap { id -> Trend? in
            let h = Analytics.history(for: id, in: sessions)
            guard let f = h.first, let l = h.last, h.count >= 2 else { return nil }
            return Trend(id: id, name: catalog[id]?.name ?? "", first: f, last: l)
        }
        if !trained.isEmpty {
            Divider()
            ForEach(trained) { t in
                HStack {
                    Text(t.name).font(.subheadline)
                    Spacer()
                    Text("\(Fmt.kg(t.first.topWeight)) → \(Fmt.kg(t.last.topWeight))").font(.subheadline.weight(.semibold))
                    let d = t.last.bestE1RM - t.first.bestE1RM
                    Image(systemName: d > 0 ? "arrow.up.right" : (d < 0 ? "arrow.down.right" : "arrow.right"))
                        .foregroundStyle(d > 0 ? Theme.good : (d < 0 ? Theme.warn : Theme.muted))
                }
            }
        }
    }

    private var muscleLoad: some View {
        let regions = Analytics.regionSets(Analytics.sessionsInLast(days: 7, sessions), catalog: catalog)
        let rows = BodyRegion.allCases.filter { $0 != .other }
        return Card {
            SectionTitle(text: "Muskelbelastung", trailing: "letzte 7 Tage")
            ForEach(rows) { r in
                let v = regions[r] ?? 0
                let range = r.weeklyTarget
                let ratio = min(v / max(range.upperBound, 1), 1.3)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(r.label).font(.subheadline)
                        Spacer()
                        Text("\(Fmt.num((v * 2).rounded() / 2, emptyZero: false)) Sätze").font(.subheadline.weight(.semibold))
                        Text("Ziel \(Int(range.lowerBound))–\(Int(range.upperBound))").font(.caption).foregroundStyle(Theme.muted)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.beige)
                            Capsule().fill(v < range.lowerBound ? Theme.rose.opacity(0.5) : (v > range.upperBound ? Theme.warn : Theme.good))
                                .frame(width: geo.size.width * min(ratio, 1))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    // MARK: Übungen

    struct Trend: Identifiable { var id: UUID; var name: String; var first: Analytics.ExercisePoint; var last: Analytics.ExercisePoint }
    struct Trained: Identifiable { var id: UUID; var name: String; var count: Int; var last: Date }

    private var exerciseList: some View {
        var counts: [UUID: Trained] = [:]
        for s in finished {
            for e in s.exercises where e.kind != .duration && !e.completedSets.isEmpty {
                let cur = counts[e.exerciseID]
                counts[e.exerciseID] = Trained(id: e.exerciseID, name: catalog[e.exerciseID]?.name ?? e.name,
                                               count: (cur?.count ?? 0) + 1, last: max(cur?.last ?? .distantPast, s.startedAt))
            }
        }
        let list = counts.values.sorted { $0.count > $1.count }
        return VStack(spacing: 10) {
            ForEach(list) { item in
                NavigationLink { ExerciseProgressView(exerciseID: item.id, name: item.name) } label: {
                    let h = Analytics.history(for: item.id, in: sessions)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                            Text("\(item.count)× trainiert · zuletzt \(Fmt.relative(item.last))").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if let l = h.last { Text(Fmt.kg(l.topWeight)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink) }
                        if h.count >= 2, let f = h.first, let l = h.last {
                            let d = l.bestE1RM - f.bestE1RM
                            Image(systemName: d > 0 ? "arrow.up.right" : (d < 0 ? "arrow.down.right" : "arrow.right"))
                                .foregroundStyle(d > 0 ? Theme.good : (d < 0 ? Theme.warn : Theme.muted))
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Rekorde

    private var recordList: some View {
        let records = Analytics.allRecords(sessions)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(BodyRegion.allCases) { region in
                let list = records.filter { $0.muscle.region == region }
                if !list.isEmpty {
                    Card {
                        SectionTitle(text: region.label)
                        ForEach(list) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).font(.subheadline.weight(.medium))
                                    Text(Fmt.short(r.date) + (r.e1RM > 0 ? " · e1RM \(Fmt.kg(r.e1RM.rounded()))" : ""))
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text(r.weight > 0 ? "\(Fmt.kg(r.weight)) × \(r.reps)" : "\(r.reps) Wdh.")
                                    .font(Theme.serif(.headline)).foregroundStyle(Theme.roseInk)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Einzelne Übung

struct ExerciseProgressView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]
    var exerciseID: UUID
    var name: String
    @State private var metric = 0

    var body: some View {
        let h = Analytics.history(for: exerciseID, in: sessions)
        let rec = Analytics.records(for: exerciseID, in: sessions)
        let ex = exercises.first { $0.id == exerciseID }
        let lastEntry = Analytics.lastEntry(exerciseID, in: sessions)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let anim = ex?.animation {
                    ExerciseAnimationView(animation: anim)
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                HStack(spacing: 10) {
                    StatTile(value: rec.maxWeight > 0 ? "\(Fmt.kg(rec.maxWeight))" : "\(rec.maxReps)",
                             label: rec.maxWeight > 0 ? "Bestes Gewicht (× \(rec.maxWeightReps))" : "Meiste Wdh.", icon: "star")
                    StatTile(value: Fmt.kg(rec.maxE1RM.rounded()), label: "Geschätztes 1RM", icon: "bolt")
                    StatTile(value: "\(h.count)", label: "Einheiten", icon: "calendar")
                }
                if let ex, let le = lastEntry,
                   let a = Analytics.advice(exerciseID: exerciseID, kind: ex.kind, repMin: le.repMin, repMax: le.repMax,
                                            targetSets: le.targetSets, increment: ex.increment, sessions: sessions) {
                    Card {
                        Label(a.title, systemImage: a.icon).font(Theme.serif(.headline)).foregroundStyle(a.kind == .increase ? Theme.good : Theme.roseInk)
                        Text(a.detail).font(.subheadline).foregroundStyle(Theme.ink)
                        Text("Vorschlag – wird nicht automatisch übernommen.").font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                if h.count >= 1 {
                    Card {
                        Picker("", selection: $metric) {
                            Text("Gewicht").tag(0)
                            Text("e1RM").tag(1)
                            Text("Volumen").tag(2)
                        }
                        .pickerStyle(.segmented)
                        Chart(h) { p in
                            let y: Double = metric == 0 ? p.topWeight : (metric == 1 ? p.bestE1RM : p.volume)
                            if metric == 2 {
                                BarMark(x: .value("Datum", p.date, unit: .day), y: .value("Wert", y))
                                    .foregroundStyle(Theme.chart[1])
                            } else {
                                LineMark(x: .value("Datum", p.date), y: .value("Wert", y))
                                    .interpolationMethod(.catmullRom).foregroundStyle(Theme.rose)
                                PointMark(x: .value("Datum", p.date), y: .value("Wert", y)).foregroundStyle(Theme.rose)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: metric == 2))
                        .frame(height: 180)
                    }
                }
                if let t = ex?.technique, !t.isEmpty {
                    Card {
                        Text("Technik").font(Theme.serif(.headline))
                        Text(t).font(.footnote).foregroundStyle(Theme.ink)
                    }
                }
                Card {
                    SectionTitle(text: "Verlauf")
                    ForEach(h.reversed()) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(Fmt.day(p.date)).font(.subheadline.weight(.medium))
                                Spacer()
                                Text("Vol. \(Fmt.volume(p.volume))").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Text(p.setsText).font(.footnote).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Button {
                    Router.shared.coachRequest = CoachRequest(mode: "technique", label: "Erkläre mir \(name)", exerciseName: name)
                    Router.shared.tab = .coach
                } label: { Label("Coach zu dieser Übung fragen", systemImage: "sparkles") }
                    .buttonStyle(SoftButtonStyle())
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
