import SwiftUI
import SwiftData

/// Übung auswählen (mit Suche und „Eigene Übung erstellen“)
struct ExercisePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    var title: String
    var onPick: (Exercise) -> Void
    @State private var search = ""
    @State private var creating = false

    private var filtered: [Exercise] {
        exercises.filter { !$0.isArchived && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.muscle.label.localizedCaseInsensitiveContains(search)) }
    }

    struct MuscleSection: Identifiable { var id: MuscleGroup; var items: [Exercise] }

    private var groups: [MuscleSection] {
        let dict = Dictionary(grouping: filtered, by: { $0.muscle })
        return MuscleGroup.allCases.compactMap { m in dict[m].map { MuscleSection(id: m, items: $0) } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { creating = true } label: { Label("Eigene Übung erstellen", systemImage: "plus.circle.fill") }
                        .foregroundStyle(Theme.roseInk)
                }
                ForEach(groups) { group in
                    Section(group.id.label) {
                        ForEach(group.items) { e in
                            Button {
                                onPick(e)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.name).foregroundStyle(Theme.ink)
                                        if !e.secondary.isEmpty {
                                            Text(e.secondary.map(\.label).joined(separator: ", ")).font(.caption).foregroundStyle(Theme.muted)
                                        }
                                    }
                                    Spacer()
                                    if e.isCustom { Pill(text: "Eigene") }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Übung oder Muskel suchen")
            .screenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .sheet(isPresented: $creating) {
                ExerciseEditor(exercise: nil, prefillName: search) { e in
                    onPick(e)
                    dismiss()
                }
            }
        }
    }
}

/// Eigene Übung anlegen oder bearbeiten
struct ExerciseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var exercise: Exercise?
    var prefillName: String = ""
    var onSave: ((Exercise) -> Void)? = nil

    @State private var name = ""
    @State private var muscle: MuscleGroup = .glutes
    @State private var secondary: Set<MuscleGroup> = []
    @State private var kind: ExerciseKind = .weighted
    @State private var increment: Double = 2.5
    @State private var technique = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name der Übung", text: $name)
                    Picker("Hauptmuskel", selection: $muscle) {
                        ForEach(MuscleGroup.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Art", selection: $kind) {
                        ForEach(ExerciseKind.allCases) { Text($0.label).tag($0) }
                    }
                    if kind != .duration {
                        HStack {
                            Text("Steigerung")
                            Spacer()
                            DecimalField(value: $increment, placeholder: "2,5").frame(width: 70)
                            Text("kg").foregroundStyle(Theme.muted)
                        }
                    }
                }
                Section("Nebenmuskeln") {
                    ForEach(MuscleGroup.allCases.filter { $0 != muscle }) { m in
                        Button {
                            if secondary.contains(m) { secondary.remove(m) } else { secondary.insert(m) }
                        } label: {
                            HStack {
                                Text(m.label).foregroundStyle(Theme.ink)
                                Spacer()
                                if secondary.contains(m) { Image(systemName: "checkmark").foregroundStyle(Theme.rose) }
                            }
                        }
                    }
                }
                Section("Technik-Hinweise") {
                    TextField("Ausführung, Tipps …", text: $technique, axis: .vertical).lineLimit(3...8)
                }
            }
            .screenBackground()
            .navigationTitle(exercise == nil ? "Neue Übung" : "Übung bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let e = exercise {
                    name = e.name; muscle = e.muscle; secondary = Set(e.secondary); kind = e.kind
                    increment = e.increment; technique = e.technique
                } else {
                    name = prefillName
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let e: Exercise
        if let exercise {
            e = exercise
            e.name = trimmed
            e.muscle = muscle
            e.kind = kind
        } else {
            e = Exercise(name: trimmed, muscle: muscle, kind: kind, isCustom: true)
            context.insert(e)
        }
        e.secondary = MuscleGroup.allCases.filter { secondary.contains($0) && $0 != muscle }
        e.increment = kind == .duration ? 0 : increment
        e.technique = technique
        // Name in Plänen aktualisieren (Historie behält den damaligen Namen)
        if exercise != nil {
            let items = (try? context.fetch(FetchDescriptor<PlanItem>())) ?? []
            for i in items where i.exerciseID == e.id { i.assign(e) }
        }
        try? context.save()
        onSave?(e)
        dismiss()
    }
}

/// Übungsbibliothek (Profil)
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var editing: Exercise?
    @State private var creating = false
    @State private var showArchived = false

    var body: some View {
        List {
            Section {
                Button { creating = true } label: { Label("Eigene Übung erstellen", systemImage: "plus.circle.fill") }
                    .foregroundStyle(Theme.roseInk)
                Toggle("Archivierte zeigen", isOn: $showArchived)
            }
            ForEach(MuscleGroup.allCases) { m in
                let list = exercises.filter { $0.muscle == m && (showArchived || !$0.isArchived) }
                if !list.isEmpty {
                    Section(m.label) {
                        ForEach(list) { e in
                            Button { editing = e } label: {
                                HStack {
                                    Text(e.name).foregroundStyle(e.isArchived ? Theme.muted : Theme.ink)
                                    Spacer()
                                    if e.isCustom { Pill(text: "Eigene") }
                                    if e.isArchived { Pill(text: "Archiv", color: Theme.beige, ink: Theme.muted) }
                                }
                            }
                            .swipeActions {
                                Button(e.isArchived ? "Aktivieren" : "Archivieren") {
                                    e.isArchived.toggle()
                                    try? context.save()
                                }
                                .tint(e.isArchived ? Theme.good : Theme.muted)
                            }
                        }
                    }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Übungen")
        .sheet(item: $editing) { e in ExerciseEditor(exercise: e) }
        .sheet(isPresented: $creating) { ExerciseEditor(exercise: nil) }
    }
}
