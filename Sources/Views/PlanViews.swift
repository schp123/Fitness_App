import SwiftUI
import SwiftData

enum PlanOps {
    @MainActor
    static func activate(_ plan: TrainingPlan, context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        for p in all { p.isActive = (p.id == plan.id) }
        plan.isArchived = false
        plan.archivedAt = nil
        plan.updatedAt = Date()
        try? context.save()
    }

    @MainActor
    @discardableResult
    static func duplicate(_ plan: TrainingPlan, context: ModelContext) -> TrainingPlan {
        let copy = TrainingPlan(name: "\(plan.name) (Kopie)", note: plan.note)
        context.insert(copy)
        for d in plan.sortedDays {
            let day = PlanDay(name: d.name, weekday: d.weekday, order: d.order, note: d.note)
            day.plan = copy
            context.insert(day)
            for i in d.sortedItems {
                let item = PlanItem(id: UUID(), order: i.order, exerciseID: i.exerciseID, exerciseName: i.exerciseName,
                                    muscleRaw: i.muscleRaw, kindRaw: i.kindRaw)
                item.sets = i.sets; item.repMin = i.repMin; item.repMax = i.repMax; item.targetWeight = i.targetWeight
                item.restSeconds = i.restSeconds; item.perSide = i.perSide; item.durationMinutes = i.durationMinutes; item.note = i.note
                item.day = day
                context.insert(item)
            }
        }
        try? context.save()
        return copy
    }

    @MainActor
    static func archive(_ plan: TrainingPlan, context: ModelContext) {
        plan.isArchived = true
        plan.archivedAt = Date()
        plan.isActive = false
        plan.updatedAt = Date()
        try? context.save()
    }

    @MainActor
    static func touch(_ plan: TrainingPlan?, context: ModelContext) {
        plan?.updatedAt = Date()
        try? context.save()
        Cloud.shared.scheduleBackup(context)
    }
}

// MARK: - Liste aller Pläne

struct PlanListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlan.createdAt) private var plans: [TrainingPlan]
    @State private var newPlan: TrainingPlan?
    @State private var deleting: TrainingPlan?

    var body: some View {
        List {
            section("Aktiver Plan", plans.filter { $0.isActive && !$0.isArchived })
            section("Weitere Pläne", plans.filter { !$0.isActive && !$0.isArchived })
            section("Archiv", plans.filter(\.isArchived))
            Section {
                Text("Abgeschlossene Trainings bleiben immer erhalten – auch wenn du Pläne änderst, archivierst oder löschst.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .screenBackground()
        .navigationTitle("Trainingspläne")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let p = TrainingPlan(name: "Neuer Plan")
                    if plans.allSatisfy({ !$0.isActive || $0.isArchived }) { p.isActive = true }
                    context.insert(p)
                    let d = PlanDay(name: "Tag 1", order: 0)
                    d.plan = p
                    context.insert(d)
                    try? context.save()
                    newPlan = p
                } label: { Label("Neuer Plan", systemImage: "plus") }
            }
        }
        .navigationDestination(item: $newPlan) { p in PlanDetailView(plan: p) }
        .confirmationDialog("Plan „\(deleting?.name ?? "")“ endgültig löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Plan löschen", role: .destructive) {
                if let p = deleting {
                    Cloud.shared.noteDeleted(kind: "plan", id: p.id)
                    context.delete(p)
                    try? context.save()
                }
                deleting = nil
            }
        } message: { Text("Deine Trainingshistorie bleibt vollständig erhalten.") }
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [TrainingPlan]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { p in
                    NavigationLink { PlanDetailView(plan: p) } label: { PlanRow(plan: p) }
                        .swipeActions(edge: .trailing) {
                            if p.isArchived {
                                Button("Löschen", role: .destructive) { deleting = p }
                                Button("Zurückholen") { p.isArchived = false; p.archivedAt = nil; PlanOps.touch(p, context: context) }.tint(Theme.good)
                            } else {
                                Button("Archiv") { PlanOps.archive(p, context: context) }.tint(Theme.muted)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Kopieren") { PlanOps.duplicate(p, context: context) }.tint(Theme.rose)
                            if !p.isActive { Button("Aktivieren") { PlanOps.activate(p, context: context) }.tint(Theme.ink) }
                        }
                }
            }
        }
    }
}

struct PlanRow: View {
    var plan: TrainingPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(plan.name).font(Theme.serif(.headline)).foregroundStyle(Theme.ink)
                if plan.isActive { Pill(text: "Aktiv", color: Theme.goodSoft, ink: Theme.good) }
            }
            Text(plan.sortedDays.map(\.name).joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Plan bearbeiten

struct PlanDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var plan: TrainingPlan
    @State private var openDay: PlanDay?

    var body: some View {
        List {
            Section {
                TextField("Name des Plans", text: $plan.name).font(Theme.serif(.title3, .medium))
                TextField("Notiz (optional)", text: $plan.note, axis: .vertical).foregroundStyle(Theme.muted)
            }
            Section {
                ForEach(plan.sortedDays) { d in
                    NavigationLink { DayEditorView(day: d) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(d.name).foregroundStyle(Theme.ink).font(.body.weight(.medium))
                                Spacer()
                                Text(d.weekdayLabel).font(.caption).foregroundStyle(Theme.muted)
                            }
                            Text(d.sortedItems.map(\.exerciseName).joined(separator: ", "))
                                .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                        }
                    }
                }
                .onMove(perform: moveDays)
                .onDelete(perform: deleteDays)
                Button {
                    let d = PlanDay(name: "Tag \(plan.days.count + 1)", order: (plan.days.map(\.order).max() ?? -1) + 1)
                    d.plan = plan
                    context.insert(d)
                    PlanOps.touch(plan, context: context)
                    openDay = d
                } label: { Label("Trainingstag hinzufügen", systemImage: "plus") }
                    .foregroundStyle(Theme.roseInk)
            } header: {
                Text("Trainingstage")
            } footer: {
                Text("Halten & ziehen zum Sortieren, nach links wischen zum Löschen.")
            }
            Section {
                if !plan.isActive {
                    Button("Als aktiven Plan verwenden") { PlanOps.activate(plan, context: context) }
                }
                Button("Plan duplizieren") { PlanOps.duplicate(plan, context: context) }
                if !plan.isArchived {
                    Button("Archivieren", role: .destructive) { PlanOps.archive(plan, context: context) }
                }
            }
        }
        .screenBackground()
        .navigationTitle(plan.name.isEmpty ? "Plan" : plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .navigationDestination(item: $openDay) { d in DayEditorView(day: d) }
        .onDisappear { PlanOps.touch(plan, context: context) }
    }

    private func moveDays(_ from: IndexSet, _ to: Int) {
        var arr = plan.sortedDays
        arr.move(fromOffsets: from, toOffset: to)
        for (i, d) in arr.enumerated() { d.order = i }
        PlanOps.touch(plan, context: context)
    }

    private func deleteDays(_ offsets: IndexSet) {
        let arr = plan.sortedDays
        for i in offsets { context.delete(arr[i]) }
        PlanOps.touch(plan, context: context)
    }
}

// MARK: - Trainingstag bearbeiten

struct DayEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var day: PlanDay
    @State private var adding = false
    @State private var editing: PlanItem?
    @Query private var profiles: [UserProfile]

    var body: some View {
        List {
            Section {
                TextField("Name (z. B. Gluteus & Rücken)", text: $day.name).font(.body.weight(.medium))
                Picker("Wochentag", selection: $day.weekday) {
                    Text("Flexibel").tag(0)
                    ForEach(1...7, id: \.self) { Text(Fmt.weekdaysLong[$0 - 1]).tag($0) }
                }
                TextField("Notiz (optional)", text: $day.note, axis: .vertical)
            }
            Section {
                ForEach(day.sortedItems) { item in
                    Button { editing = item } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.exerciseName).foregroundStyle(Theme.ink)
                                Text(item.summary + (item.kind == .duration ? "" : " · Pause \(Fmt.rest(item.restSeconds))"))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.muted)
                        }
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: delete)
                Button { adding = true } label: { Label("Übung hinzufügen", systemImage: "plus") }
                    .foregroundStyle(Theme.roseInk)
            } header: {
                Text("Übungen")
            } footer: {
                Text("Antippen zum Anpassen von Sätzen, Wiederholungen, Gewicht und Pause. Halten & ziehen zum Sortieren.")
            }
            Section {
                Button {
                    WorkoutManager.shared.start(day: day, context: context)
                } label: { Label("Diesen Tag jetzt trainieren", systemImage: "play.fill") }
                    .foregroundStyle(Theme.ink)
            }
        }
        .screenBackground()
        .navigationTitle(day.name.isEmpty ? "Trainingstag" : day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $adding) {
            ExercisePicker(title: "Übung hinzufügen") { ex in
                let item = PlanItem(order: (day.items.map(\.order).max() ?? -1) + 1, exercise: ex,
                                    sets: ex.kind == .duration ? 1 : 3, repMin: 10, repMax: 12,
                                    restSeconds: profiles.first?.defaultRest ?? 90,
                                    durationMinutes: ex.kind == .duration ? 30 : 0)
                item.day = day
                context.insert(item)
                PlanOps.touch(day.plan, context: context)
            }
        }
        .sheet(item: $editing) { item in PlanItemEditor(item: item) }
        .onDisappear { PlanOps.touch(day.plan, context: context) }
    }

    private func move(_ from: IndexSet, _ to: Int) {
        var arr = day.sortedItems
        arr.move(fromOffsets: from, toOffset: to)
        for (i, it) in arr.enumerated() { it.order = i }
        PlanOps.touch(day.plan, context: context)
    }

    private func delete(_ offsets: IndexSet) {
        let arr = day.sortedItems
        for i in offsets { context.delete(arr[i]) }
        PlanOps.touch(day.plan, context: context)
    }
}

// MARK: - Übung im Plan anpassen

struct PlanItemEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: PlanItem
    @State private var replacing = false
    @State private var confirmDelete = false

    private let restOptions = [0, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(item.exerciseName).font(Theme.serif(.headline))
                        Spacer()
                        Button("Ersetzen") { replacing = true }.font(.subheadline)
                    }
                }
                if item.kind == .duration {
                    Section("Dauer") {
                        Stepper("\(item.durationMinutes) Minuten", value: $item.durationMinutes, in: 5...180, step: 5)
                    }
                } else {
                    Section("Sätze & Wiederholungen") {
                        Stepper("Sätze: \(item.sets)", value: $item.sets, in: 1...10)
                        Stepper("Wdh. von: \(item.repMin)", value: Binding(get: { item.repMin }, set: {
                            item.repMin = $0
                            if item.repMax < $0 { item.repMax = $0 }
                        }), in: 1...50)
                        Stepper("Wdh. bis: \(item.repMax)", value: Binding(get: { item.repMax }, set: {
                            item.repMax = max($0, item.repMin)
                        }), in: 1...50)
                        Toggle("Pro Seite / pro Bein", isOn: $item.perSide)
                    }
                    Section {
                        HStack {
                            Text("Zielgewicht")
                            Spacer()
                            DecimalField(value: $item.targetWeight, placeholder: "auto").frame(width: 80)
                            Text("kg").foregroundStyle(Theme.muted)
                        }
                        Picker("Pause", selection: $item.restSeconds) {
                            ForEach(restOptions, id: \.self) { Text($0 == 0 ? "Keine" : Fmt.rest($0)).tag($0) }
                        }
                    } footer: {
                        Text("Leer lassen = beim Training wird automatisch dein letztes Gewicht vorgeschlagen.")
                    }
                }
                Section("Notiz") {
                    TextField("z. B. Füße hoch, langsam ablassen", text: $item.note, axis: .vertical)
                }
                Section {
                    Button("Aus dem Trainingstag entfernen", role: .destructive) { confirmDelete = true }
                }
            }
            .screenBackground()
            .navigationTitle("Übung anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        PlanOps.touch(item.day?.plan, context: context)
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Fertig") { hideKeyboard() } }
            }
            .sheet(isPresented: $replacing) {
                ExercisePicker(title: "Ersetzen durch …") { ex in
                    item.assign(ex)
                    PlanOps.touch(item.day?.plan, context: context)
                }
            }
            .confirmationDialog("Übung entfernen?", isPresented: $confirmDelete) {
                Button("Entfernen", role: .destructive) {
                    let plan = item.day?.plan
                    context.delete(item)
                    PlanOps.touch(plan, context: context)
                    dismiss()
                }
            }
        }
    }
}
