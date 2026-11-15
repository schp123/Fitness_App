import SwiftUI
import SwiftData

struct CoachView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Bindable private var router = Router.shared
    @State private var messages: [ChatMessage] = ChatStore.load()
    @State private var input = ""
    @State private var loading = false
    @State private var pickExercise = false
    @FocusState private var inputFocused: Bool
    private var cloud: Cloud { Cloud.shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if !cloud.isSignedIn { connectCard }
                            quickActions
                            if messages.isEmpty {
                                Card {
                                    Text("Ich bin dein Coach 🌸").font(Theme.serif(.title3, .semibold))
                                    Text("Ich kenne deinen Plan, deine Trainingshistorie und deine Ziele. Frag mich z. B.:\n• „Warum stagniert mein Hip Thrust?“\n• „Wie viele Sätze Gluteus pro Woche sind ideal?“\n• „Soll ich nach Badminton am nächsten Tag Beine trainieren?“")
                                        .font(.subheadline).foregroundStyle(Theme.muted)
                                }
                            }
                            ForEach(messages) { m in bubble(m).id(m.id) }
                            if loading {
                                HStack(spacing: 8) { ProgressView(); Text("Coach denkt nach …").font(.footnote).foregroundStyle(Theme.muted) }
                                    .id("loading")
                            }
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in
                        if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                    .onChange(of: loading) { _, l in if l { withAnimation { proxy.scrollTo("loading", anchor: .bottom) } } }
                }
                inputBar
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("KI-Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(role: .destructive) { messages = []; ChatStore.save([]) } label: { Label("Verlauf löschen", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .sheet(isPresented: $pickExercise) {
                ExercisePicker(title: "Welche Übung?") { e in
                    ask(mode: "technique", text: "Erkläre mir \(e.name)", exerciseName: e.name)
                }
            }
            .onAppear(perform: handleRequest)
            .onChange(of: router.coachRequest) { _, _ in handleRequest() }
        }
    }

    private var connectCard: some View {
        Card {
            Label("Coach noch nicht verbunden", systemImage: "lock").font(Theme.serif(.headline)).foregroundStyle(Theme.roseInk)
            Text("Der Coach läuft sicher über deinen Supabase-Server (dort liegt der Groq-Schlüssel). Melde dich unter Profil → Konto & Cloud an.")
                .font(.footnote).foregroundStyle(Theme.muted)
            Button("Zum Profil") { router.tab = .profile }.buttonStyle(SoftButtonStyle())
        }
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Letztes Training", "chart.bar.doc.horizontal") {
                    if let s = sessions.first(where: \.isFinished) {
                        ask(mode: "review", text: "Analysiere mein letztes Training (\(s.title), \(Fmt.short(s.startedAt))).", focus: s)
                    } else {
                        messages.append(ChatMessage(role: "assistant", text: "Du hast noch kein Training abgeschlossen – danach kann ich es analysieren.", isError: true))
                    }
                }
                chip("Wochenanalyse", "calendar") { ask(mode: "weekly", text: "Wie entwickle ich mich? Bitte analysiere meine letzten Wochen.") }
                chip("Plan prüfen", "list.bullet.clipboard") { ask(mode: "plan", text: "Prüfe meinen aktuellen Trainingsplan und schlage Optimierungen vor.") }
                chip("Übung erklären", "figure.strengthtraining.functional") { pickExercise = true }
            }
        }
        .disabled(loading || !cloud.isSignedIn)
        .opacity(cloud.isSignedIn ? 1 : 0.5)
    }

    private func chip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 0.5))
                .foregroundStyle(Theme.ink)
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.role == "user" { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                MarkdownText(text: m.text)
                    .font(.subheadline)
                    .foregroundStyle(m.role == "user" ? Theme.onInk : (m.isError ? Theme.warn : Theme.ink))
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(m.role == "user" ? Theme.ink : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(m.role == "user" ? .clear : Theme.line, lineWidth: 0.5))
            if m.role != "user" { Spacer(minLength: 24) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(cloud.isSignedIn ? "Frag deinen Coach …" : "Erst anmelden", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 0.5))
            Button {
                let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                input = ""
                ask(mode: "chat", text: t)
            } label: {
                Image(systemName: "arrow.up").font(.body.weight(.bold))
                    .frame(width: 40, height: 40)
                    .background(Theme.rose, in: Circle())
                    .foregroundStyle(.white)
            }
            .disabled(loading || !cloud.isSignedIn || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.bg)
        .disabled(!cloud.isSignedIn)
    }

    private func handleRequest() {
        guard let r = router.coachRequest else { return }
        router.coachRequest = nil
        let focus = r.sessionID.flatMap { id in sessions.first { $0.id == id } }
        ask(mode: r.mode, text: r.label, exerciseName: r.exerciseName, focus: focus)
    }

    private func ask(mode: String, text: String, exerciseName: String? = nil, focus: WorkoutSession? = nil) {
        guard cloud.isSignedIn else {
            messages.append(ChatMessage(role: "assistant", text: "Bitte melde dich zuerst unter Profil → Konto & Cloud an.", isError: true))
            return
        }
        messages.append(ChatMessage(role: "user", text: text))
        ChatStore.save(messages)
        let history = messages.filter { !$0.isError }.suffix(12).map { (role: $0.role, content: $0.text) }
        let ctx = CoachContext.build(context, focus: focus, exerciseName: exerciseName)
        loading = true
        Task {
            do {
                let answer = try await cloud.coach(mode: mode, context: ctx, messages: Array(history))
                messages.append(ChatMessage(role: "assistant", text: answer))
                if mode == "review", let focus, focus.aiReview.isEmpty {
                    focus.aiReview = answer
                    focus.aiReviewAt = Date()
                    try? context.save()
                }
            } catch {
                messages.append(ChatMessage(role: "assistant", text: error.localizedDescription, isError: true))
            }
            ChatStore.save(messages)
            loading = false
        }
    }
}
