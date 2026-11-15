// Forma – KI-Coach (Supabase Edge Function)
// Hält den Groq-API-Key serverseitig (Secret GROQ_API_KEY) und verwaltet alle Prompts zentral.
// Die App schickt nur: Modus, kompakten Trainingskontext und ggf. Chatverlauf.

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";
const MODELS = [
  Deno.env.get("GROQ_MODEL") ?? "",
  "openai/gpt-oss-120b",
  "llama-3.3-70b-versatile",
].filter((m, i, a) => m && a.indexOf(m) === i);

const MAX_CONTEXT = 24000; // Zeichen
const MAX_MESSAGES = 12;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const BASE = `Du bist „Forma Coach“, eine erfahrene, warmherzige Personal Trainerin für Krafttraining mit Schwerpunkt Gluteus-Aufbau.
Du sprichst Deutsch, duzt, bist motivierend, ehrlich und konkret.

Regeln:
- Stütze jede Aussage auf die mitgelieferten Trainingsdaten. Nenne konkrete Zahlen (kg, Wiederholungen, Sätze, Daten). Keine generischen Floskeln.
- Wenn Daten fehlen oder zu wenige Einheiten vorliegen, sag das offen statt zu raten.
- Gewichts-, Satz- und Planänderungen sind immer VORSCHLÄGE. Du kannst keine Daten verändern und behauptest das auch nie.
- Progressive Overload: erst Wiederholungen bis zur Obergrenze steigern, dann Gewicht in kleinen Schritten (Unterkörper meist +2,5 bis 5 kg, Oberkörper/Kabel +1 bis 2,5 kg).
- Achte auf Regeneration: Trainingsfrequenz, Abstand zwischen Einheiten derselben Muskelgruppe, Volumen pro Woche, Badminton als zusätzliche Belastung.
- Bei Schmerzen (nicht Muskelkater) rätst du zu Pause und ärztlicher Abklärung. Keine medizinischen Diagnosen.
- Formatierung: kurze Absätze, Aufzählungen mit „•“, keine Tabellen, keine Überschriften mit #. Fett nur sparsam mit **…**.`;

const MODES: Record<string, string> = {
  review: `Aufgabe: Kurze Analyse der zuletzt abgeschlossenen Trainingseinheit (max. ca. 150 Wörter).
Aufbau:
1) Ein Satz Gesamteindruck.
2) • 2–4 Beobachtungen mit Zahlen (Vergleich zum letzten Mal, neue Rekorde, Volumen).
3) „Nächstes Mal:“ 1–3 konkrete Vorschläge pro relevanter Übung (Gewicht/Wdh.).
4) Ein motivierender Schlusssatz.`,
  weekly: `Aufgabe: Wochen-/Verlaufsanalyse (max. ca. 220 Wörter): Kraftentwicklung pro Hauptübung, Gluteus-Volumen, Trainingsfrequenz, Schwächen und Verbesserungspotenzial, Anzeichen für Übertraining oder fehlende Regeneration, 3 konkrete Empfehlungen.`,
  plan: `Aufgabe: Prüfe den aktiven Trainingsplan im Hinblick auf das Ziel (Gluteus-Aufbau, definierter Rücken, Arme, Core). Bewerte Volumen pro Muskelgruppe, Übungsauswahl, Reihenfolge und Verteilung auf die Woche inkl. Badminton. Schlage max. 5 konkrete, begründete Optimierungen vor (als Vorschläge, die die Nutzerin selbst im Editor umsetzt).`,
  technique: `Aufgabe: Erkläre die genannte Übung: Zielmuskeln, Ausführung Schritt für Schritt, 3 typische Fehler, 2 Tipps für maximale Gluteus-Aktivierung (falls sinnvoll), passende Wiederholungsbereiche. Beziehe vorhandene Trainingsdaten zur Übung ein.`,
  chat: `Aufgabe: Beantworte die Frage der Nutzerin als ihr persönlicher Coach. Halte dich kurz (meist unter 180 Wörtern), außer es wird ausdrücklich mehr verlangt.`,
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

async function currentUser(auth: string | null, apikey: string | null): Promise<string | null> {
  if (!auth?.startsWith("Bearer ")) return null;
  const url = Deno.env.get("SUPABASE_URL");
  // Schlüssel der App (publishable oder anon) – sonst der vom Server bereitgestellte
  const key = apikey || Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (!url) return null;
  const r = await fetch(`${url}/auth/v1/user`, { headers: { Authorization: auth, apikey: key } });
  if (!r.ok) return null;
  const u = await r.json();
  return typeof u?.id === "string" ? u.id : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method", message: "Nur POST." }, 405);

  const userId = await currentUser(req.headers.get("Authorization"), req.headers.get("apikey"));
  if (!userId) return json({ error: "auth", message: "Bitte in der App neu anmelden." }, 401);

  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) return json({ error: "config", message: "GROQ_API_KEY ist auf dem Server nicht gesetzt." }, 500);

  let body: { mode?: string; context?: string; messages?: { role: string; content: string }[]; question?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "input", message: "Ungültige Anfrage." }, 400);
  }

  const mode = body.mode && MODES[body.mode] ? body.mode : "chat";
  const context = String(body.context ?? "").slice(0, MAX_CONTEXT);
  const history = (Array.isArray(body.messages) ? body.messages : [])
    .filter((m) => (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .slice(-MAX_MESSAGES)
    .map((m) => ({ role: m.role, content: m.content.slice(0, 4000) }));

  const messages = [
    { role: "system", content: `${BASE}\n\n${MODES[mode]}` },
    { role: "system", content: `Trainingsdaten der Nutzerin (Stand ${new Date().toISOString().slice(0, 10)}):\n${context || "(keine Daten)"}` },
    ...history,
  ];
  if (body.question) messages.push({ role: "user", content: String(body.question).slice(0, 4000) });
  if (messages[messages.length - 1].role !== "user") {
    messages.push({ role: "user", content: "Bitte erstelle die Analyse." });
  }

  let lastError = "";
  for (const model of MODELS) {
    const payload: Record<string, unknown> = { model, messages, temperature: 0.5, max_completion_tokens: 1400 };
    if (model.startsWith("openai/gpt-oss")) payload.reasoning_effort = "low";
    let r: Response;
    try {
      r = await fetch(GROQ_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
    } catch (e) {
      lastError = `Netzwerkfehler: ${e}`;
      continue;
    }
    if (r.status === 429) {
      const retry = r.headers.get("retry-after") ?? "";
      return json({ error: "rate_limit", retryAfter: retry, message: "Das KI-Limit (Groq Free Tier) ist gerade erreicht. Bitte in ein paar Minuten erneut versuchen." }, 429);
    }
    const text = await r.text();
    if (!r.ok) {
      lastError = `Groq ${r.status}: ${text.slice(0, 300)}`;
      // Modell nicht verfügbar → nächstes probieren; andere Fehler direkt melden
      if (r.status === 404 || r.status === 400 && /model/i.test(text)) continue;
      return json({ error: "groq", message: lastError }, 502);
    }
    try {
      const data = JSON.parse(text);
      const content = data?.choices?.[0]?.message?.content?.trim();
      if (!content) { lastError = "Leere Antwort"; continue; }
      return json({ text: content, model });
    } catch {
      lastError = "Antwort nicht lesbar";
    }
  }
  return json({ error: "groq", message: lastError || "Kein Modell verfügbar." }, 502);
});
