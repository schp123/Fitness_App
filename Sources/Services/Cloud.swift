import Foundation
import SwiftData
import Observation
import Security

// MARK: - Verbindung

struct CloudConfig: Codable, Equatable {
    var url: String
    var key: String

    var isValid: Bool { URL(string: base) != nil && url.lowercased().hasPrefix("http") && !key.isEmpty }
    var base: String { url.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n")) }

    /// In der App gespeichert – sonst die beim Bauen hinterlegten Werte
    static func load() -> CloudConfig? {
        if let d = UserDefaults.standard.data(forKey: "cloud.config"),
           let c = try? JSONDecoder().decode(CloudConfig.self, from: d), c.isValid { return c }
        let url = (Bundle.main.object(forInfoDictionaryKey: "FormaSupabaseURL") as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (Bundle.main.object(forInfoDictionaryKey: "FormaSupabaseKey") as? String ?? "").trimmingCharacters(in: .whitespaces)
        let c = CloudConfig(url: url, key: key)
        return c.isValid ? c : nil
    }

    static func save(_ c: CloudConfig?) {
        if let c, let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: "cloud.config") }
        else { UserDefaults.standard.removeObject(forKey: "cloud.config") }
    }
}

struct AuthSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String
}

enum Keychain {
    private static let service = "de.egler.forma"

    static func save(_ data: Data, for key: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecValueData as String: data,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load(_ key: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

enum CloudError: LocalizedError {
    case notConfigured, notSignedIn, http(Int, String), message(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase ist noch nicht verbunden (Profil → Konto & Cloud)."
        case .notSignedIn: return "Bitte zuerst anmelden (Profil → Konto & Cloud)."
        case .message(let m): return m
        case .http(let code, let body):
            if body.contains("Invalid login credentials") { return "E-Mail oder Passwort stimmt nicht." }
            if body.contains("Email not confirmed") { return "Bitte zuerst den Bestätigungslink in deiner E-Mail öffnen." }
            if body.contains("User already registered") { return "Für diese E-Mail gibt es schon ein Konto – bitte anmelden." }
            if body.contains("fitness_records") && (body.contains("does not exist") || code == 404) {
                return "Tabelle fehlt – bitte supabase/schema.sql im SQL-Editor ausführen."
            }
            if body.contains("Invalid API key") || body.contains("No API key") { return "Schlüssel ungültig – bitte den publishable/anon key aus Supabase → Project Settings → API Keys prüfen." }
            if code == 401 { return "Anmeldung abgelaufen – bitte neu anmelden." }
            if let d = body.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let msg = (obj["message"] ?? obj["msg"] ?? obj["error_description"]) as? String {
                return msg
            }
            return "Server-Fehler \(code): \(body.prefix(160))"
        }
    }
}

// MARK: - Cloud (Login, Backup, KI-Coach)

@MainActor
@Observable
final class Cloud {
    static let shared = Cloud()

    private(set) var config: CloudConfig? = CloudConfig.load()
    private(set) var session: AuthSession? = {
        guard let d = Keychain.load("auth") else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: d)
    }()
    private(set) var isBackingUp = false
    private(set) var lastBackup: Date? = UserDefaults.standard.object(forKey: "cloud.lastBackup") as? Date
    private(set) var lastError: String?

    @ObservationIgnored private var pending: Task<Void, Never>?

    var isConfigured: Bool { config != nil }
    var isSignedIn: Bool { session != nil }
    var email: String { session?.email ?? "" }

    func setConfig(_ c: CloudConfig?) {
        CloudConfig.save(c)
        config = CloudConfig.load()
    }

    // MARK: HTTP

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil,
                         token: String? = nil, prefer: String? = nil, timeout: TimeInterval = 25) throws -> URLRequest {
        guard let config, var comps = URLComponents(string: config.base) else { throw CloudError.notConfigured }
        comps.path = path
        comps.queryItems = query.isEmpty ? nil : query
        guard let url = comps.url else { throw CloudError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue(config.key, forHTTPHeaderField: "apikey")
        // Neue Schlüssel (sb_publishable_…) sind kein JWT und dürfen nicht als Bearer gesendet werden.
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if config.key.hasPrefix("eyJ") {
            req.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = body
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw CloudError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return data
    }

    // MARK: Anmeldung

    private func storeSession(from data: Data, fallbackEmail: String) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String else {
            throw CloudError.message("Antwort vom Server nicht verstanden.")
        }
        let expiresIn = (obj["expires_in"] as? Double) ?? Double(obj["expires_in"] as? Int ?? 3600)
        let user = obj["user"] as? [String: Any]
        let s = AuthSession(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn),
                            userID: user?["id"] as? String ?? "", email: user?["email"] as? String ?? fallbackEmail)
        if let d = try? JSONEncoder().encode(s) { Keychain.save(d, for: "auth") }
        session = s
    }

    func signIn(email: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await send(try request("/auth/v1/token", method: "POST",
                                              query: [URLQueryItem(name: "grant_type", value: "password")], body: body))
        try storeSession(from: data, fallbackEmail: email)
        lastError = nil
    }

    /// true = Konto angelegt, Bestätigungs-Mail muss noch geöffnet werden
    func signUp(email: String, password: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await send(try request("/auth/v1/signup", method: "POST", body: body))
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], obj["access_token"] != nil {
            try storeSession(from: data, fallbackEmail: email)
            return false
        }
        return true
    }

    func signOut() {
        Keychain.delete("auth")
        session = nil
    }

    func validToken() async throws -> String {
        guard isConfigured else { throw CloudError.notConfigured }
        guard let s = session else { throw CloudError.notSignedIn }
        if s.expiresAt.timeIntervalSinceNow > 90 { return s.accessToken }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
        do {
            let data = try await send(try request("/auth/v1/token", method: "POST",
                                                  query: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: body))
            try storeSession(from: data, fallbackEmail: s.email)
            return session?.accessToken ?? s.accessToken
        } catch CloudError.http(let code, let msg) where code == 400 || code == 401 {
            signOut()
            throw CloudError.http(401, msg)
        }
    }

    // MARK: Backup

    private var syncState: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: "cloud.hashes") as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "cloud.hashes") }
    }

    private var pendingDeletes: [String] {
        get { UserDefaults.standard.stringArray(forKey: "cloud.deletes") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "cloud.deletes") }
    }

    /// Vom Nutzer endgültig gelöschte Einträge auch in der Cloud als gelöscht markieren
    func noteDeleted(kind: String, id: UUID) {
        pendingDeletes.append("\(kind):\(id.uuidString)")
    }

    func scheduleBackup(_ context: ModelContext) {
        guard isSignedIn else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self.backup(context)
        }
    }

    func backup(_ context: ModelContext, full: Bool = false) async {
        guard isSignedIn, !isBackingUp else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        do {
            let token = try await validToken()
            let records = BackupStore.records(context)
            var state = full ? [:] : syncState
            var rows: [[String: Any]] = []
            var newState = state
            for r in records {
                let key = "\(r.kind):\(r.id.uuidString)"
                guard state[key] != r.hash else { continue }
                let obj = (try? JSONSerialization.jsonObject(with: r.data)) ?? [String: Any]()
                rows.append(["user_id": session?.userID ?? "", "kind": r.kind, "id": r.id.uuidString.lowercased(),
                             "data": obj, "deleted": false])
                newState[key] = r.hash
            }
            let deletes = pendingDeletes
            for d in deletes {
                let parts = d.split(separator: ":")
                guard parts.count == 2 else { continue }
                rows.append(["user_id": session?.userID ?? "", "kind": String(parts[0]), "id": String(parts[1]).lowercased(),
                             "data": [String: Any](), "deleted": true])
                newState.removeValue(forKey: d)
            }
            var start = 0
            while start < rows.count {
                let chunk = Array(rows[start..<min(start + 50, rows.count)])
                let body = try JSONSerialization.data(withJSONObject: chunk)
                _ = try await send(try request("/rest/v1/fitness_records", method: "POST",
                                               query: [URLQueryItem(name: "on_conflict", value: "user_id,id")],
                                               body: body, token: token, prefer: "resolution=merge-duplicates,return=minimal"))
                start += 50
            }
            state = newState
            syncState = state
            pendingDeletes = []
            lastBackup = Date()
            UserDefaults.standard.set(lastBackup, forKey: "cloud.lastBackup")
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Holt alle Daten aus der Cloud und ergänzt sie lokal (nichts Lokales wird gelöscht).
    func restore(_ context: ModelContext) async throws -> BackupStore.ImportResult {
        let token = try await validToken()
        var rows: [(kind: String, data: Data)] = []
        var offset = 0
        while true {
            let q = [URLQueryItem(name: "select", value: "kind,data,deleted"),
                     URLQueryItem(name: "deleted", value: "eq.false"),
                     URLQueryItem(name: "order", value: "updated_at.asc"),
                     URLQueryItem(name: "limit", value: "500"),
                     URLQueryItem(name: "offset", value: "\(offset)")]
            let data = try await send(try request("/rest/v1/fitness_records", query: q, token: token))
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { break }
            for row in arr {
                guard let kind = row["kind"] as? String, let obj = row["data"], JSONSerialization.isValidJSONObject(obj),
                      let d = try? JSONSerialization.data(withJSONObject: obj) else { continue }
                rows.append((kind, d))
            }
            if arr.count < 500 { break }
            offset += 500
        }
        let file = BackupStore.file(from: rows)
        let result = try BackupStore.merge(file, into: context)
        syncState = [:]
        await backup(context)
        return result
    }

    // MARK: KI-Coach

    func coach(mode: String, context: String, messages: [(role: String, content: String)] = [], question: String? = nil) async throws -> String {
        let token = try await validToken()
        var payload: [String: Any] = ["mode": mode, "context": context,
                                      "messages": messages.map { ["role": $0.role, "content": $0.content] }]
        if let question { payload["question"] = question }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try request("/functions/v1/coach", method: "POST", body: body, token: token, timeout: 60)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if (200..<300).contains(code), let text = obj?["text"] as? String { return text }
        if code == 404 { throw CloudError.message("Coach-Funktion nicht gefunden – bitte Edge Function „coach“ in Supabase anlegen.") }
        if let msg = obj?["message"] as? String { throw CloudError.message(msg) }
        throw CloudError.http(code, String(data: data, encoding: .utf8) ?? "")
    }
}
