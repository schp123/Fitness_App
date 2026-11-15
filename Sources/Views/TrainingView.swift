import SwiftUI
import SwiftData

struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlan.createdAt) private var plans: [TrainingPlan]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var mode = 0

    private var activePlan: TrainingPlan? { plans.first { $0.isActive && !$0.isArchived } }
    private var finished: [WorkoutSession] { sessions.filter(\.isFinished) }
    private var running: WorkoutSession? { sessions.first { !$0.isFinished } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("", selection: $mode) {
                        Text("Plan").tag(0)
                        Text("Verlauf").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if mode == 0 { planSection } else { historySection }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Training")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { PlanListView() } label: { Label("Pläne", systemImage: "list.bullet.rectangle") }
                }
            }
        }
    }

    @ViewBuilder
    private var planSection: some View {
        if let running {
            ResumeBanner(session: running)
        }
        if let plan = activePlan {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aktiver Plan").font(.caption).foregroundStyle(Theme.muted)
                    Text(plan.name).font(Theme.serif(.title2, .semibold)).foregroundStyle(Theme.ink)
                }
                Spacer()
                NavigationLink { PlanDetailView(plan: plan) } label: { Text("Bearbeiten") }
                    .buttonStyle(SoftButtonStyle())
            }
            ForEach(plan.sortedDays) { day in
                DayCard(day: day, lastDone: finished.first { $0.dayID == day.id }?.startedAt, isToday: day.weekday == Fmt.isoWeekday(Date()))
            }
        } else {
            Card {
                EmptyHint(icon: "list.bullet.rectangle", title: "Kein aktiver Plan", text: "Lege einen Plan an oder aktiviere einen vorhandenen.")
                NavigationLink { PlanListView() } label: { Text("Pläne verwalten") }.buttonStyle(PrimaryButtonStyle())
            }
        }
        Button {
            WorkoutManager.shared.start(day: nil, context: context)
        } label: { Label("Freies Training starten", systemImage: "plus.circle") }
            .buttonStyle(SoftButtonStyle())
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var historySection: some View {
        if finished.isEmpty {
            Card { EmptyHint(icon: "clock", title: "Noch keine Einheiten", text: "Abgeschlossene Trainings erscheinen hier – dauerhaft gespeichert.") }
        } else {
            NavigationLink { CompareView() } label: {
                Label("Einheiten vergleichen", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(SoftButtonStyle())
            let groups = Dictionary(grouping: finished) { Calendar.current.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt }
            ForEach(groups.keys.sorted(by: >), id: \.self) { month in
                Text(month.formatted(.dateTime.month(.wide).year().locale(Fmt.de)))
                    .font(Theme.serif(.headline)).foregroundStyle(Theme.muted)
                    .padding(.top, 4)
                ForEach(groups[month] ?? []) { s in
                    NavigationLink { SessionDetailView(session: s) } label: { SessionRow(session: s) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ResumeBanner: View {
    @Environment(\.modelContext) private var context
    var session: WorkoutSession
    var body: some View {
        Button { WorkoutManager.shared.showActive = true } label: {
            HStack(spacing: 12) {
                Image(systemName: session.status == .paused ? "pause.circle.fill" : "figure.strengthtraining.traditional")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.status == .paused ? "Training pausiert" : "Training läuft").font(.headline)
                    Text("\(session.title) · \(session.completedSets.count) Sätze erledigt").font(.caption).opacity(0.8)
                }
                Spacer()
                Text("Fortsetzen").font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
            }
            .padding(16)
            .foregroundStyle(Theme.onInk)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct DayCard: View {
    @Environment(\.modelContext) private var context
    var day: PlanDay
    var lastDone: Date?
    var isToday: Bool

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(day.weekdayLabel).font(.caption.weight(.semibold)).foregroundStyle(Theme.rose)
                        if isToday { Pill(text: "Heute") }
                    }
                    Text(day.name).font(Theme.serif(.title3, .semibold)).foregroundStyle(Theme.ink)
                }
                Spacer()
                if let lastDone { Text("zuletzt \(Fmt.relative(lastDone))").font(.caption).foregroundStyle(Theme.muted) }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(day.sortedItems) { i in
                    HStack {
                        Text(i.exerciseName).font(.subheadline).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(i.summary).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            HStack {
                NavigationLink { DayEditorView(day: day) } label: { Text("Anpassen") }
                    .buttonStyle(SoftButtonStyle())
                Spacer()
                Button {
                    WorkoutManager.shared.start(day: day, context: context)
                } label: {
                    Label("Starten", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.ink, in: Capsule())
                        .foregroundStyle(Theme.onInk)
                }
            }
            .padding(.top, 4)
        }
    }
}

struct SessionRow: View {
    var session: WorkoutSession
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(session.startedAt.formatted(.dateTime.day().locale(Fmt.de))).font(Theme.serif(.title3, .semibold))
                Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.de))).font(.caption2)
            }
            .frame(width: 44, height: 50)
            .background(Theme.roseSoft, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Theme.roseInk)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text("\(Fmt.minutes(session.activeDuration())) · \(session.completedSets.count) Sätze · \(Fmt.volume(session.volume))")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            if session.prCount > 0 { Pill(text: "\(session.prCount)", icon: "star.fill") }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 0.5))
    }
}
