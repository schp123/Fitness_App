import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var sessions: [WorkoutSession]
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            if let p = profiles.first {
                form(p)
            } else {
                ProgressView().onAppear { _ = UserProfile.current(context) }
            }
        }
    }

    private func form(_ profile: UserProfile) -> some View {
        @Bindable var p = profile
        return Form {
            Section("Über dich") {
                TextField("Dein Name", text: $p.name)
                Stepper("Einheiten pro Woche: \(p.weeklyTarget)", value: $p.weeklyTarget, in: 1...7)
                HStack {
                    Text("Körpergewicht")
                    Spacer()
                    DecimalField(value: $p.bodyweight, placeholder: "–").frame(width: 70)
                    Text("kg").foregroundStyle(Theme.muted)
                }
            }
            Section {
                TextField("Deine Ziele", text: $p.goals, axis: .vertical).lineLimit(3...10)
            } header: { Text("Ziele") } footer: { Text("Der Coach richtet seine Analysen danach aus.") }

            Section("Training") {
                Picker("Standard-Pause", selection: $p.defaultRest) {
                    ForEach([30, 45, 60, 75, 90, 120, 150, 180], id: \.self) { Text(Fmt.rest($0)).tag($0) }
                }
                Toggle("Hinweis, wenn die Pause vorbei ist", isOn: $p.restNotifications)
                    .onChange(of: p.restNotifications) { _, v in UserDefaults.standard.set(v, forKey: "restNotifications") }
                Toggle("Coach-Analyse nach jedem Training", isOn: $p.autoReview)
                NavigationLink("Trainingspläne") { PlanListView() }
                NavigationLink("Übungsbibliothek") { ExerciseLibraryView() }
            }

            Section("Darstellung") {
                Picker("Modus", selection: $p.appearance) {
                    Text("System").tag("system")
                    Text("Hell").tag("light")
                    Text("Dunkel").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Konto & Cloud") {
                NavigationLink {
                    AccountView()
                } label: {
                    HStack {
                        Text("Konto & Cloud-Backup")
                        Spacer()
                        Text(Cloud.shared.isSignedIn ? Cloud.shared.email : "nicht angemeldet")
                            .font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
            }

            Section {
                Button { export { try BackupStore.exportJSON(context) } } label: { Label("Backup exportieren (JSON)", systemImage: "square.and.arrow.up") }
                Button { export { try BackupStore.exportCSV(context) } } label: { Label("Sätze exportieren (CSV/Excel)", systemImage: "tablecells") }
                Button { importing = true } label: { Label("Backup importieren", systemImage: "square.and.arrow.down") }
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
            } header: { Text("Daten") } footer: {
                Text("\(sessions.filter(\.isFinished).count) Einheiten gespeichert. Import ergänzt nur – vorhandene Einheiten werden nie überschrieben.")
            }

            Section {
                LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
            }
        }
        .screenBackground()
        .navigationTitle("Profil")
        .onChange(of: p.goals) { _, _ in p.updatedAt = Date() }
        .onDisappear { p.updatedAt = Date(); try? context.save() }
        .sheet(item: Binding(get: { exportURL.map { ShareURL(url: $0) } }, set: { exportURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let file = try BackupCoding.decoder.decode(BackupFile.self, from: data)
                    let r = try BackupStore.merge(file, into: context)
                    message = "Importiert: \(r.sessions) Einheiten, \(r.plans) Pläne, \(r.exercises) Übungen."
                    Cloud.shared.scheduleBackup(context)
                } catch {
                    message = "Import fehlgeschlagen: \(error.localizedDescription)"
                }
            case .failure(let e):
                message = e.localizedDescription
            }
        }
    }

    private func export(_ make: () throws -> URL) {
        do { exportURL = try make() } catch { message = "Export fehlgeschlagen: \(error.localizedDescription)" }
    }
}

struct ShareURL: Identifiable { var url: URL; var id: String { url.absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Konto & Cloud

struct AccountView: View {
    @Environment(\.modelContext) private var context
    private var cloud: Cloud { Cloud.shared }
    @State private var url = ""
    @State private var key = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var info: String?
    @State private var error: String?
    @State private var confirmRestore = false

    var body: some View {
        Form {
            if !cloud.isConfigured || !url.isEmpty {
                Section {
                    TextField("https://xxxx.supabase.co", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("anon / publishable key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Verbindung speichern") {
                        let c = CloudConfig(url: url.trimmingCharacters(in: .whitespaces), key: key.trimmingCharacters(in: .whitespaces))
                        if c.isValid { cloud.setConfig(c); url = ""; key = ""; info = "Verbindung gespeichert."; error = nil }
                        else { error = "Bitte gültige URL und Schlüssel eintragen." }
                    }
                } header: { Text("Supabase-Verbindung") } footer: {
                    Text("Supabase → Project Settings → API. Der Schlüssel ist öffentlich-sicher; der Groq-Schlüssel bleibt auf dem Server.")
                }
            }

            if cloud.isConfigured {
                if cloud.isSignedIn {
                    Section("Angemeldet") {
                        LabeledContent("E-Mail", value: cloud.email)
                        Button("Abmelden", role: .destructive) { cloud.signOut() }
                    }
                    Section {
                        Button {
                            Task { busy = true; await cloud.backup(context, full: true); busy = false
                                info = cloud.lastError == nil ? "Backup vollständig hochgeladen." : nil }
                        } label: { Label("Jetzt sichern", systemImage: "icloud.and.arrow.up") }
                        Button { confirmRestore = true } label: { Label("Aus Cloud wiederherstellen", systemImage: "icloud.and.arrow.down") }
                        if let last = cloud.lastBackup {
                            LabeledContent("Letztes Backup", value: "\(Fmt.short(last)) \(Fmt.time(last))")
                        }
                        if let e = cloud.lastError { Text(e).font(.footnote).foregroundStyle(Theme.warn) }
                    } header: { Text("Backup") } footer: {
                        Text("Nach jedem Training und beim Schließen der App wird automatisch gesichert.")
                    }
                } else {
                    Section {
                        TextField("E-Mail", text: $email)
                            .keyboardType(.emailAddress).textContentType(.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Passwort (mind. 6 Zeichen)", text: $password).textContentType(.password)
                        Button("Anmelden") { run { try await cloud.signIn(email: email, password: password); info = "Angemeldet." } }
                            .disabled(email.isEmpty || password.count < 6)
                        Button("Neues Konto erstellen") {
                            run {
                                let needsConfirm = try await cloud.signUp(email: email, password: password)
                                info = needsConfirm ? "Konto erstellt. Öffne den Bestätigungslink in deiner E-Mail und melde dich dann hier an."
                                                    : "Konto erstellt und angemeldet."
                            }
                        }
                        .disabled(email.isEmpty || password.count < 6)
                    } header: { Text("Anmelden") } footer: {
                        Text("Dein Konto schützt Cloud-Backup und KI-Coach. Training funktioniert auch ohne Anmeldung offline.")
                    }
                }
                Section {
                    Button("Verbindung ändern") {
                        url = cloud.config?.url ?? ""
                        key = cloud.config?.key ?? ""
                    }
                }
            }

            if busy { Section { HStack { ProgressView(); Text("Bitte warten …") } } }
            if let info { Section { Text(info).font(.footnote).foregroundStyle(Theme.good) } }
            if let error { Section { Text(error).font(.footnote).foregroundStyle(Theme.warn) } }
        }
        .screenBackground()
        .navigationTitle("Konto & Cloud")
        .onChange(of: cloud.isSignedIn) { _, signedIn in if signedIn { Task { await cloud.backup(context) } } }
        .confirmationDialog("Daten aus der Cloud holen?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Wiederherstellen") {
                run {
                    let r = try await cloud.restore(context)
                    info = "Wiederhergestellt: \(r.sessions) Einheiten, \(r.plans) Pläne, \(r.exercises) Übungen."
                }
            }
        } message: { Text("Fehlende Einheiten, Pläne und Übungen werden ergänzt. Lokale Daten bleiben erhalten.") }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true
        error = nil
        info = nil
        Task {
            do { try await op() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
