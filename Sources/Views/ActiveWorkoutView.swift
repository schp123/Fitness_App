import SwiftUI
import SwiftData

struct ActiveWorkoutContainer: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.statusRaw != "finished" }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var active: [WorkoutSession]

    var body: some View {
        if let s = active.first {
            ActiveWorkoutView(session: s)
        } else {
            VStack(spacing: 16) {
                EmptyHint(icon: "checkmark.circle", title: "Kein laufendes Training", text: "Starte ein Training im Tab „Training“.")
                Button("Schließen") { WorkoutManager.shared.showActive = false }.buttonStyle(SoftButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
        }
    }
}

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: WorkoutSession
    @Query private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]
    @Bindable private var manager = WorkoutManager.shared

    @State private var showAdd = false
    @State private var replacing: SessionExercise?
    @State private var showFinish = false

    private var catalog: [UUID: Exercise] { Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    if session.status == .paused { pausedBanner }
                    ForEach(session.sortedExercises) { entry in
                        ExerciseLogCard(entry: entry, session: session, sessions: sessions, catalogItem: catalog[entry.exerciseID],
                                        onReplace: { replacing = entry })
                    }
                    Button { showAdd = true } label: {
                        Label("Übung hinzufügen", systemImage: "plus")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .padding(.top, 4)
                    Button { showFinish = true } label: { Text("Training beenden") }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, manager.restEnd == nil ? 30 : 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .overlay(alignment: .bottom) { if manager.restEnd != nil { RestTimerBar() } }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { manager.showActive = false } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Minimieren")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if session.status == .paused {
                        Button { manager.resume(session, context: context) } label: { Label("Fortsetzen", systemImage: "play.fill") }
                    } else {
                        Button { manager.pause(session, context: context) } label: { Label("Pausieren", systemImage: "pause.fill") }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { hideKeyboard() }
                }
            }
            .sheet(isPresented: $showAdd) {
                ExercisePicker(title: "Übung hinzufügen") { ex in
                    manager.add(ex, to: session, context: context)
                }
            }
            .sheet(item: $replacing) { entry in
                ExercisePicker(title: "\(entry.name) ersetzen") { ex in
                    manager.replace(entry, with: ex, in: session, context: context)
                }
            }
            .sheet(isPresented: $showFinish) {
                FinishWorkoutSheet(session: session)
                    .presentationDetents([.medium, .large])
            }
        }
        .tint(Theme.rose)
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let done = session.completedSets.count
            let total = session.exercises.reduce(0) { $0 + ($1.kind == .duration ? 0 : $1.sets.count) }
            HStack(spacing: 10) {
                StatTile(value: Fmt.duration(session.activeDuration(now: ctx.date)), label: "Trainingszeit", icon: "timer")
                StatTile(value: "\(done)/\(total)", label: "Sätze", icon: "checkmark.circle")
                StatTile(value: Fmt.volume(session.volume), label: "Volumen", icon: "scalemass")
            }
        }
        .padding(.top, 8)
    }

    private var pausedBanner: some View {
        HStack {
            Image(systemName: "pause.circle.fill").foregroundStyle(Theme.warn)
            Text("Training pausiert – alles ist gespeichert.").font(.subheadline)
            Spacer()
            Button("Weiter") { manager.resume(session, context: context) }.buttonStyle(SoftButtonStyle())
        }
        .padding(12)
        .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Übungskarte im Training

struct ExerciseLogCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var entry: SessionExercise
    var session: WorkoutSession
    var sessions: [WorkoutSession]
    var catalogItem: Exercise?
    var onReplace: () -> Void
    @State private var showNote = false
    @State private var confirmRemove = false
    @State private var showDemo = false

    private var last: SessionExercise? { Analytics.lastEntry(entry.exerciseID, in: sessions, excluding: session.id) }
    private var advice: Analytics.Advice? {
        Analytics.advice(exerciseID: entry.exerciseID, kind: entry.kind, repMin: entry.repMin, repMax: entry.repMax,
                         targetSets: entry.targetSets, increment: catalogItem?.increment ?? 2.5, sessions: sessions, excluding: session.id)
    }
    private var step: Double { max(catalogItem?.increment ?? 2.5, 0.5) }

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                if let anim = catalogItem?.animation {
                    Button { showDemo = true } label: {
                        ExerciseThumb(animation: anim, animated: !entry.isComplete, width: 76)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 9, weight: .bold)).padding(4)
                                    .background(Theme.card.opacity(0.9), in: Circle()).padding(3)
                                    .foregroundStyle(Theme.muted)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ausführung ansehen")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(Theme.serif(.title3, .semibold)).foregroundStyle(Theme.ink)
                    HStack(spacing: 6) {
                        Pill(text: entry.muscle.label)
                        if entry.kind != .duration {
                            Text("\(entry.targetSets) × \(Fmt.reps(entry.repMin, entry.repMax))\(entry.perSide ? " pro Seite" : "") · Pause \(Fmt.rest(entry.restSeconds))")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Spacer()
                if entry.isComplete { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.good).font(.title3) }
                menu
            }

            if !entry.planNote.isEmpty {
                Text(entry.planNote).font(.footnote).foregroundStyle(Theme.muted)
            }

            if entry.kind == .duration {
                durationRow
            } else {
                if let last {
                    Text("Letztes Mal (\(Fmt.short(last.session?.startedAt ?? Date()))): \(last.setsText)")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                if let advice { adviceRow(advice) }
                VStack(spacing: 8) {
                    HStack {
                        Text("Satz").frame(width: 34, alignment: .leading)
                        Text("Gewicht").frame(maxWidth: .infinity)
                        Text("Wdh.").frame(width: 70)
                        Color.clear.frame(width: 44, height: 1)
                    }
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                    ForEach(entry.sortedSets) { set in
                        SetRow(set: set, entry: entry, step: step, bodyweight: entry.kind == .bodyweight)
                    }
                }
                HStack {
                    Button { WorkoutManager.shared.addSet(to: entry, context: context) } label: {
                        Label("Satz", systemImage: "plus").font(.footnote.weight(.semibold))
                    }
                    Spacer()
                    Button { showNote.toggle() } label: {
                        Label(entry.note.isEmpty ? "Notiz" : "Notiz bearbeiten", systemImage: "square.and.pencil").font(.footnote)
                    }
                }
                .foregroundStyle(Theme.roseInk)
            }
            if showNote || !entry.note.isEmpty {
                TextField("Notiz zur Übung (z. B. Technik, Gefühl)", text: $entry.note, axis: .vertical)
                    .font(.footnote)
                    .padding(10)
                    .background(Theme.beige.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(isPresented: $showDemo) {
            ExerciseDemoSheet(name: entry.name, animation: catalogItem?.animation, muscle: entry.muscle,
                              secondary: catalogItem?.secondary ?? [], technique: catalogItem?.technique ?? "")
        }
        .confirmationDialog("\(entry.name) aus diesem Training entfernen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                context.delete(entry)
                try? context.save()
            }
        } message: {
            Text("Der Trainingsplan bleibt unverändert.")
        }
    }

    private var menu: some View {
        Menu {
            Button { onReplace() } label: { Label("Übung ersetzen", systemImage: "arrow.triangle.2.circlepath") }
            Button {
                Router.shared.coachRequest = CoachRequest(mode: "technique", label: "Erkläre mir \(entry.name)", exerciseName: entry.name)
                Router.shared.tab = .coach
                WorkoutManager.shared.showActive = false
            } label: { Label("Technik erklären (Coach)", systemImage: "sparkles") }
            Button { showDemo = true } label: { Label("Ausführung ansehen", systemImage: "play.rectangle") }
            Button(role: .destructive) { confirmRemove = true } label: { Label("Aus Training entfernen", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.muted)
                .frame(width: 36, height: 36)
        }
    }

    private func adviceRow(_ a: Analytics.Advice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: a.icon).foregroundStyle(a.kind == .increase ? Theme.good : Theme.rose)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(a.detail).font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if let w = a.suggestedWeight, w > 0, entry.sortedSets.contains(where: { !$0.completed && $0.weight != w }) {
                Button("Übernehmen") {
                    for s in entry.sets where !s.completed { s.weight = w }
                    try? context.save()
                    Haptics.tap()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
            }
        }
        .padding(10)
        .background(a.kind == .increase ? Theme.goodSoft : Theme.roseSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private var durationRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("Dauer").font(.caption).foregroundStyle(Theme.muted)
                HStack(spacing: 4) {
                    IntField(value: Binding(get: { entry.doneMinutes > 0 ? entry.doneMinutes : entry.durationMinutes },
                                            set: { entry.doneMinutes = $0 }), placeholder: "\(entry.durationMinutes)")
                        .frame(width: 60)
                        .padding(8)
                        .background(Theme.beige.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    Text("min").foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Button {
                entry.isDone.toggle()
                if entry.isDone, entry.doneMinutes == 0 { entry.doneMinutes = entry.durationMinutes }
                try? context.save()
                if entry.isDone { Haptics.success() }
            } label: {
                Label(entry.isDone ? "Erledigt" : "Abhaken", systemImage: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(entry.isDone ? Theme.good : Theme.beige, in: Capsule())
                    .foregroundStyle(entry.isDone ? Color.white : Theme.ink)
            }
        }
    }
}

// MARK: - Satzzeile

struct SetRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var set: SetLog
    var entry: SessionExercise
    var step: Double
    var bodyweight: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(set.completed ? Theme.ink : Theme.beige).frame(width: 30, height: 30)
                if set.isPR {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.rose)
                } else {
                    Text("\(set.index + 1)").font(.footnote.weight(.semibold)).foregroundStyle(set.completed ? Theme.onInk : Theme.ink)
                }
            }
            .frame(width: 34, alignment: .leading)
            .contextMenu {
                Button(role: .destructive) { WorkoutManager.shared.removeSet(set, context: context) } label: {
                    Label("Satz löschen", systemImage: "trash")
                }
            }

            HStack(spacing: 2) {
                stepButton("minus") { set.weight = max(0, set.weight - step) }
                DecimalField(value: $set.weight, placeholder: bodyweight ? "KG" : "0")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 44)
                stepButton("plus") { set.weight += step }
            }
            .padding(4)
            .background(Theme.beige.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity)

            IntField(value: $set.reps, placeholder: "\(max(set.targetMax, set.targetMin))")
                .font(.body.weight(.semibold).monospacedDigit())
                .padding(.vertical, 8)
                .frame(width: 70)
                .background(Theme.beige.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))

            Button {
                hideKeyboard()
                WorkoutManager.shared.toggle(set, in: entry, context: context)
            } label: {
                Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30))
                    .foregroundStyle(set.completed ? Theme.good : Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(set.completed ? "Satz rückgängig" : "Satz abhaken")
        }
        .opacity(set.completed ? 0.85 : 1)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            try? context.save()
            Haptics.tap()
        } label: {
            Image(systemName: icon).font(.caption.weight(.bold)).frame(width: 28, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
    }
}

// MARK: - Pausentimer

struct RestTimerBar: View {
    @Bindable private var manager = WorkoutManager.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let remaining = max(0, (manager.restEnd ?? ctx.date).timeIntervalSince(ctx.date))
            let progress = manager.restTotal > 0 ? 1 - remaining / Double(manager.restTotal) : 1
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(remaining > 0 ? "Pause" : "Pause vorbei").font(.caption).foregroundStyle(Theme.onInk.opacity(0.7))
                        Text(Fmt.duration(remaining)).font(.system(.title, design: .serif).weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.onInk)
                    }
                    Spacer()
                    Button("+30 s") { manager.extendRest(30) }.buttonStyle(.bordered).tint(Theme.onInk)
                    Button(remaining > 0 ? "Überspringen" : "Weiter") { manager.cancelRest() }
                        .buttonStyle(.borderedProminent).tint(Theme.rose)
                }
                ProgressView(value: min(max(progress, 0), 1)).tint(Theme.rose)
            }
            .padding(16)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .onChange(of: remaining <= 0) { _, over in if over { Haptics.warning() } }
        }
    }
}

// MARK: - Abschließen

struct FinishWorkoutSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkoutSession
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let open = session.exercises.filter { !$0.isComplete }.count
                    LabeledContent("Erledigte Sätze", value: "\(session.completedSets.count)")
                    LabeledContent("Volumen", value: Fmt.volume(session.volume))
                    if open > 0 {
                        Text("\(open) Übung(en) noch nicht vollständig. Nicht abgehakte Sätze werden nicht gespeichert.")
                            .font(.footnote).foregroundStyle(Theme.warn)
                    }
                }
                Section("Wie war’s?") {
                    HStack {
                        ForEach(1...5, id: \.self) { i in
                            Button {
                                session.feeling = session.feeling == i ? 0 : i
                            } label: {
                                Text(["😮‍💨", "😕", "🙂", "💪", "🔥"][i - 1])
                                    .font(.title2)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(session.feeling == i ? Theme.roseSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("Notiz zum Training", text: $session.note, axis: .vertical)
                }
                Section {
                    Button {
                        dismiss()
                        WorkoutManager.shared.finish(session, context: context)
                    } label: { Text("Training speichern & beenden").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    Button("Training verwerfen", role: .destructive) { confirmDiscard = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Training beenden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zurück") { dismiss() } } }
            .confirmationDialog("Training wirklich verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) {
                    dismiss()
                    WorkoutManager.shared.discard(session, context: context)
                }
            } message: { Text("Alle Einträge dieses Trainings werden gelöscht.") }
        }
    }
}
