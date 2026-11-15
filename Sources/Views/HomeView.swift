import SwiftUI
import SwiftData
import Charts

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlan.createdAt) private var plans: [TrainingPlan]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }
    private var catalog: [UUID: Exercise] { Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var activePlan: TrainingPlan? { plans.first { $0.isActive && !$0.isArchived } }
    private var finished: [WorkoutSession] { sessions.filter(\.isFinished) }
    private var running: WorkoutSession? { sessions.first { !$0.isFinished } }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let base = h < 11 ? "Guten Morgen" : (h < 18 ? "Hallo" : "Guten Abend")
        if let n = profile?.name, !n.isEmpty { return "\(base), \(n)" }
        return base
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Fmt.dayLong(Date())).font(.footnote).foregroundStyle(Theme.muted)
                        Text(greeting).font(Theme.serif(.largeTitle, .semibold)).foregroundStyle(Theme.ink)
                    }
                    .padding(.top, 8)

                    if let running { ResumeBanner(session: running) }
                    todaySection
                    weekCard
                    statsRow
                    recovery
                    gluteCard
                    lastSessionCard
                    recordsCard
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Heute

    @ViewBuilder
    private var todaySection: some View {
        let today = Fmt.isoWeekday(Date())
        if let plan = activePlan {
            let days = plan.sortedDays
            if let day = days.first(where: { $0.weekday == today }) {
                let doneToday = finished.contains { $0.dayID == day.id && Calendar.current.isDateInToday($0.startedAt) }
                if doneToday {
                    Card {
                        Label("Heute erledigt: \(day.name)", systemImage: "checkmark.seal.fill")
                            .font(Theme.serif(.headline)).foregroundStyle(Theme.good)
                        Text("Gönn dir Regeneration – Protein, Schlaf, Wasser.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                } else {
                    DayCard(day: day, lastDone: finished.first { $0.dayID == day.id }?.startedAt, isToday: true)
                }
            } else if let next = nextDay(days, after: today) {
                Card {
                    Text("Heute ist Ruhetag").font(Theme.serif(.title3, .semibold)).foregroundStyle(Theme.ink)
                    Text("Nächstes Training: \(next.weekdayLabel) – \(next.name)").font(.subheadline).foregroundStyle(Theme.muted)
                    HStack {
                        Button { WorkoutManager.shared.start(day: next, context: context) } label: { Text("Trotzdem jetzt starten") }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
            } else if let first = days.first {
                DayCard(day: first, lastDone: finished.first { $0.dayID == first.id }?.startedAt, isToday: false)
            }
        }
    }

    private func nextDay(_ days: [PlanDay], after weekday: Int) -> PlanDay? {
        let dated = days.filter { (1...7).contains($0.weekday) }
        return dated.first { $0.weekday > weekday } ?? dated.min { $0.weekday < $1.weekday }
    }

    // MARK: Woche

    private var weekCard: some View {
        let cal = Calendar.iso
        let start = cal.startOfWeek(Date())
        let inWeek = finished.filter { $0.startedAt >= start }
        let trainedDays = Set(inWeek.map { Fmt.isoWeekday($0.startedAt) })
        let planned = Set(activePlan?.days.map(\.weekday) ?? [])
        let target = profile?.weeklyTarget ?? 3
        return Card {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "Diese Woche")
                Spacer()
                Text("\(inWeek.count) / \(target) Einheiten").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.roseInk)
            }
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { d in
                    let done = trainedDays.contains(d)
                    let isToday = d == Fmt.isoWeekday(Date())
                    VStack(spacing: 6) {
                        Text(Fmt.weekdays[d - 1]).font(.caption2.weight(isToday ? .bold : .regular)).foregroundStyle(Theme.muted)
                        ZStack {
                            Circle().fill(done ? Theme.rose : (planned.contains(d) ? Theme.roseSoft : Theme.beige.opacity(0.6)))
                            if done { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                        }
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(isToday ? Theme.ink : .clear, lineWidth: 1.5))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            ProgressView(value: min(Double(inWeek.count) / Double(max(target, 1)), 1)).tint(Theme.rose)
        }
    }

    private var statsRow: some View {
        let last7 = Analytics.sessionsInLast(days: 7, sessions)
        let regions = Analytics.regionSets(last7, catalog: catalog)
        let glute = regions[.glutes] ?? 0
        let prs30 = Analytics.sessionsInLast(days: 30, sessions).reduce(0) { $0 + $1.prCount }
        let streak = Analytics.weekStreak(sessions, target: profile?.weeklyTarget ?? 3, catalog: catalog)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(value: "\(Int(glute.rounded()))", label: "Gluteus-Sätze (7 Tage, Ziel 12–20)", icon: "flame")
            StatTile(value: Fmt.volume(last7.reduce(0) { $0 + $1.volume }), label: "Volumen (7 Tage)", icon: "scalemass")
            StatTile(value: "\(prs30)", label: "Rekorde (30 Tage)", icon: "star")
            StatTile(value: "\(streak)", label: streak == 1 ? "Woche Ziel erreicht in Folge" : "Wochen Ziel erreicht in Folge", icon: "calendar")
        }
    }

    @ViewBuilder
    private var recovery: some View {
        let notes = Analytics.recoveryNotes(sessions, catalog: catalog, weeklyTarget: profile?.weeklyTarget ?? 3)
        if !notes.isEmpty {
            Card {
                Label("Regeneration", systemImage: "leaf").font(Theme.serif(.headline)).foregroundStyle(Theme.warn)
                ForEach(notes, id: \.self) { Text("• \($0)").font(.footnote).foregroundStyle(Theme.ink) }
            }
        }
    }

    // MARK: Gluteus-Fortschritt

    @ViewBuilder
    private var gluteCard: some View {
        let hip = exercises.first { $0.name == "Hip Thrust" }
        let points = hip.map { Analytics.history(for: $0.id, in: sessions) } ?? []
        if points.count >= 2, let first = points.first, let last = points.last {
            Card {
                HStack {
                    SectionTitle(text: "Hip Thrust")
                    Spacer()
                    let d = last.topWeight - first.topWeight
                    Pill(text: (d >= 0 ? "+" : "") + Fmt.num(d, emptyZero: false) + " kg", color: Theme.goodSoft, ink: Theme.good)
                }
                Chart(points) { p in
                    LineMark(x: .value("Datum", p.date), y: .value("kg", p.topWeight))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.rose)
                    PointMark(x: .value("Datum", p.date), y: .value("kg", p.topWeight))
                        .foregroundStyle(Theme.rose)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
                Text("\(Fmt.kg(first.topWeight)) am \(Fmt.short(first.date)) → \(Fmt.kg(last.topWeight)) am \(Fmt.short(last.date))")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder
    private var lastSessionCard: some View {
        if let s = finished.first {
            NavigationLink { SessionDetailView(session: s) } label: {
                Card {
                    HStack {
                        SectionTitle(text: "Letztes Training", trailing: Fmt.relative(s.startedAt))
                    }
                    Text("\(s.title) · \(Fmt.minutes(s.activeDuration())) · \(Fmt.volume(s.volume))")
                        .font(.subheadline).foregroundStyle(Theme.ink)
                    if !s.aiReview.isEmpty {
                        MarkdownText(text: s.aiReview).font(.footnote).foregroundStyle(Theme.muted).lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .buttonStyle(.plain)
        } else if running == nil {
            Card {
                EmptyHint(icon: "figure.strengthtraining.traditional", title: "Bereit für dein erstes Training?",
                          text: "Dein Plan ist angelegt. Starte oben oder im Tab „Training“ – alles wird automatisch gespeichert.")
            }
        }
    }

    struct RecentPR: Identifiable { var id: UUID; var name: String; var weight: Double; var reps: Int; var date: Date }

    @ViewBuilder
    private var recordsCard: some View {
        let all: [RecentPR] = finished.flatMap { s in
            s.exercises.flatMap { e in
                e.completedSets.filter(\.isPR).map { RecentPR(id: $0.id, name: e.name, weight: $0.weight, reps: $0.reps, date: s.startedAt) }
            }
        }
        let recent = Array(all.sorted { $0.date > $1.date }.prefix(4))
        if !recent.isEmpty {
            Card {
                SectionTitle(text: "Neueste Rekorde")
                ForEach(recent) { r in
                    HStack {
                        Image(systemName: "star.fill").foregroundStyle(Theme.rose).font(.caption)
                        Text(r.name).font(.subheadline)
                        Spacer()
                        Text(r.weight > 0 ? "\(Fmt.kg(r.weight)) × \(r.reps)" : "\(r.reps) Wdh.").font(.subheadline.weight(.semibold))
                        Text(Fmt.short(r.date)).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}
