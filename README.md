# Forma – Krafttraining & Glute Coach

Native SwiftUI-App für iPhone (iOS 17+). Trainingsdaten liegen lokal auf dem Gerät (SwiftData) und funktionieren offline im Studio. Supabase liefert Login, Cloud-Backup und den sicheren Server für den KI-Coach (Groq).

## Funktionen (Phase 1–3)

- **Trainingsplan & Editor**: mehrere Pläne anlegen, duplizieren, archivieren, aktivieren. Trainingstage hinzufügen, löschen, per Drag & Drop sortieren, Wochentag zuordnen. Übungen hinzufügen, ersetzen, entfernen, sortieren; Sätze, Wdh.-Bereich, Zielgewicht, Pause, „pro Seite“, Notiz. Eigene Übungen mit Haupt-/Nebenmuskeln und Technik-Hinweisen.
- **Trainingstagebuch**: Training starten, jeder Satz mit Gewicht, tatsächlichen Wdh., Zielwdh., Pause und Notiz. Automatisches Speichern bei jeder Eingabe, Pausieren/Fortsetzen (auch nach App-Neustart), Pausentimer mit Benachrichtigung. Letzte Gewichte werden vorbelegt, „Letztes Mal“ wird angezeigt. Übungen im laufenden Training spontan hinzufügen/ersetzen (Plan bleibt unverändert).
- **Historie**: jede Einheit wird als eigenständiger Snapshot gespeichert – Planänderungen verändern nie alte Trainings.
- **Progressive Overload**: Rekorde (Gewicht, e1RM, Wdh.), Vorschläge zur Gewichtserhöhung, Plateau-Erkennung. Vorschläge werden nur angezeigt; „Übernehmen“ setzt sie erst auf Fingertipp – und nur für das laufende Training.
- **Statistiken**: Trainingshäufigkeit, Volumen, Gluteus-Sätze pro Woche, Muskelbelastung je Region, Kraftentwicklung pro Übung, Monatsübersicht, Vergleich zweier Einheiten.
- **KI-Coach**: Analyse nach jedem Training, Wochenanalyse, Plan-Check, Übungserklärungen, freier Chat – auf Basis deiner echten Daten. Der Groq-Schlüssel liegt nur auf dem Server.
- **Daten**: Export als JSON (komplettes Backup) und CSV (alle Sätze), Import, Cloud-Backup und -Wiederherstellung.
- **Design**: Creme, Beige, Schwarz, Rosé; Hell-/Dunkelmodus.

Phase 4 (Körpertracking, Ernährung, Badminton) folgt als Update – Bundle-ID bleibt gleich, Daten bleiben erhalten.

## Einrichtung (einmalig)

### 1. Supabase
1. Neues Projekt auf supabase.com anlegen.
2. **SQL Editor** → Inhalt von `supabase/schema.sql` einfügen → **Run**.
3. **Authentication → Sign In / Providers → Email**: aktiviert lassen. Wenn du keine Bestätigungs-Mail willst: „Confirm email“ ausschalten.
4. **Edge Functions → Deploy a new function → Via Editor**: Name `coach`, Inhalt von `supabase/functions/coach/index.ts` einfügen → **Deploy**.
5. **Edge Functions → Secrets**: `GROQ_API_KEY` = dein Schlüssel von console.groq.com. Optional `GROQ_MODEL` (Standard: `openai/gpt-oss-120b`, Ausweichmodell `llama-3.3-70b-versatile`).
6. **Project Settings → API**: Project URL und anon/publishable key kopieren.

### 2. App verbinden
Entweder in der App unter **Profil → Konto & Cloud** URL + Schlüssel eintragen, oder im GitHub-Repo unter *Settings → Secrets and variables → Actions → Variables* `SUPABASE_URL` und `SUPABASE_ANON_KEY` anlegen – dann sind sie ab dem nächsten Build fest eingebaut. Danach Konto erstellen bzw. anmelden.

### 3. Installation über SideStore
SideStore → Quellen → hinzufügen:
`https://raw.githubusercontent.com/schp123/Fitness_App/main/altsource.json`

Neueste IPA direkt: https://github.com/schp123/Fitness_App/releases/latest/download/Forma.ipa

## Bauen
Jeder Push auf `main` baut über GitHub Actions (macOS) eine unsignierte IPA, veröffentlicht sie als Release und aktualisiert `altsource.json`. Die Versionsnummer zählt automatisch hoch, die Bundle-ID `de.egler.forma` bleibt gleich.

Lokal auf dem Mac: `brew install xcodegen && xcodegen generate && open Forma.xcodeproj`.

## Sicherheit
- Groq-API-Key nur als Supabase-Secret, nie in der App oder im Repo.
- Edge Function prüft den Login jedes Aufrufs; Datenbankzeilen sind per Row Level Security nur für den eigenen Account lesbar.
- Der KI-Coach liefert ausschließlich Text – er kann keine Trainingsdaten verändern.
