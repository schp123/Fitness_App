import SwiftUI
import SwiftData

@MainActor
enum CoachService {
    /// Kurzanalyse einer Einheit – speichert nur den Text, verändert keine Trainingsdaten.
    static func review(_ session: WorkoutSession, context: ModelContext) async throws {
        let ctx = CoachContext.build(context, focus: session)
        let text = try await Cloud.shared.coach(mode: "review", context: ctx)
        session.aiReview = text
        session.aiReviewAt = Date()
        try? context.save()
        Cloud.shared.scheduleBackup(context)
    }
}

struct MarkdownText: View {
    var text: String
    var body: some View {
        if let a = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(a)
        } else {
            Text(text)
        }
    }
}

// MARK: - Analyse-Karte

struct ReviewCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: WorkoutSession
    var autoStart: Bool = false
    @State private var loading = false
    @State private var error: String?
    private var cloud: Cloud { Cloud.shared }

    var body: some View {
        Card {
            HStack {
                Label("Coach-Analyse", systemImage: "sparkles").font(Theme.serif(.headline)).foregroundStyle(Theme.roseInk)
                Spacer()
                if !session.aiReview.isEmpty && !loading {
                    Button { Task { await run() } } label: { Image(systemName: "arrow.clockwise") }
                        .foregroundStyle(Theme.muted)
                }
            }
            if loading {
                HStack(spacing: 10) { ProgressView(); Text("Coach analysiert dein Training …").font(.footnote).foregroundStyle(Theme.muted) }
            } else if !session.aiReview.isEmpty {
                MarkdownText(text: session.aiReview).font(.subheadline).foregroundStyle(Theme.ink)
                Text("Vorschläge – du entscheidest, was du übernimmst.").font(.caption2).foregroundStyle(Theme.muted)
            } else if !cloud.isSignedIn {
                Text("Melde dich unter Profil → Konto & Cloud an, um Analysen vom KI-Coach zu bekommen.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            } else {
                Button { Task { await run() } } label: { Text("Analyse erstellen") }.buttonStyle(SoftButtonStyle())
            }
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.warn) }
        }
        .task {
            if autoStart && session.aiReview.isEmpty && cloud.isSignedIn && UserProfile.current(context).autoReview { await run() }
        }
    }

    private func run() async {
        loading = true
        error = nil
        do { try await CoachService.review(session, context: context) } catch { self.error = error.localizedDescription }
        loading = false
    }
}

// MARK: - Zusammenfassung direkt nach dem Training

struct SessionSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [WorkoutSession]
    var sessionID: UUID

    init(sessionID: UUID) {
        self.sessionID = sessionID
        _sessions = Query(filter: #Predicate<WorkoutSession> { $0.id == sessionID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = sessions.first {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Stark gemacht! 💪").font(Theme.serif(.largeTitle, .semibold)).foregroundStyle(Theme.ink)
                        Text("\(s.title) · \(Fmt.dayLong(s.startedAt))").foregroundStyle(Theme.muted)
                        HStack(spacing: 10) {
                            StatTile(value: Fmt.minutes(s.activeDuration()), label: "Dauer", icon: "timer")
                            StatTile(value: "\(s.completedSets.count)", label: "Sätze", icon: "checkmark.circle")
                            StatTile(value: Fmt.volume(s.volume), label: "Volumen", icon: "scalemass")
                        }
                        let prs = s.sortedExercises.filter { $0.completedSets.contains(where: \.isPR) }
                        if !prs.isEmpty {
                            Card {
                                Label("Neue Rekorde", systemImage: "star.fill").font(Theme.serif(.headline)).foregroundStyle(Theme.roseInk)
                                ForEach(prs) { e in
                                    let best = e.completedSets.filter(\.isPR).max { $0.weight < $1.weight }
                                    HStack {
                                        Text(e.name)
                                        Spacer()
                                        if let best { Text("\(Fmt.kg(best.weight)) × \(best.reps)").font(.body.weight(.semibold)) }
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                        ReviewCard(session: s, autoStart: true)
                    }
                    .padding(16)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

// MARK: - Einheit im Detail

struct SessionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkoutSession
    @State private var confirmDelete = false
    @State private var showCompare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Fmt.dayLong(session.startedAt) + " · " + Fmt.time(session.startedAt)).font(.footnote).foregroundStyle(Theme.muted)
                    if !session.planName.isEmpty { Text("Plan: \(session.planName)").font(.footnote).foregroundStyle(Theme.muted) }
                }
                HStack(spacing: 10) {
                    StatTile(value: Fmt.minutes(session.activeDuration()), label: "Dauer", icon: "timer")
                    StatTile(value: "\(session.completedSets.count)", label: "Sätze", icon: "checkmark.circle")
                    StatTile(value: Fmt.volume(session.volume), label: "Volumen", icon: "scalemass")
                }
                ForEach(session.sortedExercises) { e in
                    Card {
                        HStack {
                            Text(e.name).font(Theme.serif(.headline)).foregroundStyle(Theme.ink)
                            Spacer()
                            Pill(text: e.muscle.label)
                        }
                        if e.kind == .duration {
                            Text(e.isDone ? "\(e.doneMinutes > 0 ? e.doneMinutes : e.durationMinutes) Minuten" : "nicht erledigt")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        } else if e.completedSets.isEmpty {
                            Text("Keine Sätze erledigt").font(.subheadline).foregroundStyle(Theme.muted)
                        } else {
                            ForEach(e.completedSets) { s in
                                HStack {
                                    Text("Satz \(s.index + 1)").foregroundStyle(Theme.muted)
                                    if s.isPR { Image(systemName: "star.fill").foregroundStyle(Theme.rose).font(.caption) }
                                    Spacer()
                                    Text(s.weight > 0 ? "\(Fmt.kg(s.weight)) × \(s.reps)" : "\(s.reps) Wdh.").font(.body.weight(.medium).monospacedDigit())
                                    Text("Ziel \(Fmt.reps(s.targetMin, s.targetMax))").font(.caption).foregroundStyle(Theme.muted)
                                        .frame(width: 70, alignment: .trailing)
                                }
                                .font(.subheadline)
                            }
                            Text("Volumen \(Fmt.volume(e.volume)) · e1RM \(Fmt.kg(e.bestE1RM.rounded()))").font(.caption).foregroundStyle(Theme.muted)
                        }
                        if !e.note.isEmpty { Text(e.note).font(.footnote).foregroundStyle(Theme.ink).italic() }
                    }
                }
                Card {
                    Text("Notiz").font(Theme.serif(.headline))
                    TextField("Wie lief das Training?", text: $session.note, axis: .vertical)
                        .onSubmit { try? context.save() }
                    if session.feeling > 0 {
                        Text("Gefühl: " + ["😮‍💨", "😕", "🙂", "💪", "🔥"][min(max(session.feeling, 1), 5) - 1])
                    }
                }
                ReviewCard(session: session)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { showCompare = true } label: { Label("Vergleichen", systemImage: "arrow.left.arrow.right") }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Einheit löschen", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .navigationDestination(isPresented: $showCompare) { CompareView(preselectB: session.id) }
        .onDisappear { try? context.save() }
        .confirmationDialog("Diese Einheit endgültig löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Cloud.shared.noteDeleted(kind: "session", id: session.id)
                context.delete(session)
                try? context.save()
                dismiss()
            }
        } message: { Text("Das lässt sich nicht rückgängig machen. Statistiken und Rekorde werden neu berechnet.") }
    }
}

// MARK: - Vergleich zweier Einheiten

struct CompareView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var all: [WorkoutSession]
    var preselectB: UUID? = nil
    @State private var aID: UUID?
    @State private var bID: UUID?

    private var sessions: [WorkoutSession] { all.filter(\.isFinished) }
    private var a: WorkoutSession? { sessions.first { $0.id == aID } }
    private var b: WorkoutSession? { sessions.first { $0.id == bID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if sessions.count < 2 {
                    Card { EmptyHint(icon: "arrow.left.arrow.right", title: "Noch zu wenig Daten", text: "Nach zwei Trainings kannst du hier vergleichen.") }
                } else {
                    HStack(spacing: 10) {
                        picker("Vorher", selection: $aID)
                        picker("Nachher", selection: $bID)
                    }
                    if let a, let b { comparison(a, b) }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Vergleich")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: preset)
    }

    private func preset() {
        guard aID == nil else { return }
        let b0 = sessions.first { $0.id == preselectB } ?? sessions.first
        bID = b0?.id
        // gleicher Trainingstag davor, sonst einfach die vorherige Einheit
        if let b0 {
            let earlier = sessions.filter { $0.startedAt < b0.startedAt }
            aID = (earlier.first { $0.dayID != nil && $0.dayID == b0.dayID } ?? earlier.first)?.id
        }
    }

    private func picker(_ title: String, selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.muted)
            Menu {
                ForEach(sessions) { s in
                    Button("\(Fmt.short(s.startedAt)) – \(s.title)") { selection.wrappedValue = s.id }
                }
            } label: {
                let s = sessions.first { $0.id == selection.wrappedValue }
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.map { Fmt.short($0.startedAt) } ?? "wählen").font(.headline)
                    Text(s?.title ?? "").font(.caption).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Theme.ink)
            }
        }
    }

    private func comparison(_ a: WorkoutSession, _ b: WorkoutSession) -> some View {
        let ids = (b.sortedExercises + a.sortedExercises).map(\.exerciseID)
        var seen = Set<UUID>()
        let unique = ids.filter { seen.insert($0).inserted }
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                StatTile(value: delta(b.volume - a.volume, unit: " kg"), label: "Volumen (\(Fmt.volume(b.volume)))")
                StatTile(value: delta(Double(b.completedSets.count - a.completedSets.count), unit: ""), label: "Sätze")
                StatTile(value: Fmt.minutes(b.activeDuration()), label: "Dauer (vorher \(Fmt.minutes(a.activeDuration())))")
            }
            ForEach(unique, id: \.self) { id in
                let ea = a.exercises.first { $0.exerciseID == id }
                let eb = b.exercises.first { $0.exerciseID == id }
                Card {
                    HStack {
                        Text(eb?.name ?? ea?.name ?? "").font(Theme.serif(.headline))
                        Spacer()
                        if let ea, let eb, ea.topWeight > 0 || eb.topWeight > 0 {
                            let d = eb.topWeight - ea.topWeight
                            Pill(text: d == 0 ? "±0 kg" : delta(d, unit: " kg"),
                                 color: d > 0 ? Theme.goodSoft : (d < 0 ? Theme.warnSoft : Theme.beige),
                                 ink: d > 0 ? Theme.good : (d < 0 ? Theme.warn : Theme.muted))
                        }
                    }
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text(Fmt.short(a.startedAt)).font(.caption).foregroundStyle(Theme.muted)
                            Text(ea?.setsText ?? "–").font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(Fmt.short(b.startedAt)).font(.caption).foregroundStyle(Theme.muted)
                            Text(eb?.setsText ?? "–").font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func delta(_ v: Double, unit: String) -> String {
        (v > 0 ? "+" : (v < 0 ? "−" : "±")) + Fmt.num(abs(v.rounded()), emptyZero: false) + unit
    }
}
