// Ghaf AI cloud proxy for Cloudflare Workers (free plan).
// Holds the Gemini API key server-side so it is never in the app. The app must send the access
// token you chose (APP_TOKEN) in the X-Ghaf-Token header. Nothing is stored: each request is
// forwarded to Gemini and the reply is returned.
//
// Secrets (wrangler secret put): GEMINI_API_KEY, APP_TOKEN. Optional var: GEMINI_MODEL.

const MAX_BODY = 16_000; // bytes; the app sends a question and a short summary, never full history

export default {
  async fetch(request, env) {
    if (request.method !== "POST" || new URL(request.url).pathname !== "/chat") {
      return json({ error: "not_found" }, 404);
    }
    if (!env.APP_TOKEN || request.headers.get("X-Ghaf-Token") !== env.APP_TOKEN) {
      return json({ error: "unauthorized" }, 401);
    }
    const raw = await request.text();
    if (raw.length > MAX_BODY) return json({ error: "too_large" }, 413);

    let body;
    try { body = JSON.parse(raw); } catch { return json({ error: "bad_json" }, 400); }
    const { question, facts = "", direct = "", language = "en", history = [] } = body;
    if (typeof question !== "string" || !question.trim()) return json({ error: "missing_question" }, 400);

    const system = [
      "You are Ghaf AI, a warm, concise personal finance assistant in a UAE money app.",
      "Answer only from the FACTS and the DIRECT ANSWER. Quote amounts exactly with their currency.",
      "Never invent transactions or balances and never add amounts in different currencies.",
      "If a DIRECT ANSWER is given, keep every number in it and add at most one short, useful tip.",
      "If the message is not about money, reply in one light, friendly line, then offer one thing you can do.",
      `Reply in ${language === "ar" ? "Arabic (Gulf-friendly Modern Standard Arabic)" : "English"}, in 1-4 short sentences.`,
      "",
      "FACTS:", String(facts).slice(0, 8000),
      direct ? `\nDIRECT ANSWER FROM THE LEDGER: ${direct}` : ""
    ].join("\n");

    const contents = [
      ...history.slice(-6).map(m => ({ role: m.isUser ? "user" : "model", parts: [{ text: String(m.text).slice(0, 600) }] })),
      { role: "user", parts: [{ text: question.slice(0, 600) }] }
    ];

    const model = env.GEMINI_MODEL || "gemini-2.5-flash";
    const upstream = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: system }] },
          contents,
          generationConfig: { temperature: 0.4, maxOutputTokens: 400 }
        })
      }
    );
    if (!upstream.ok) return json({ error: "upstream", status: upstream.status }, 502);
    const data = await upstream.json();
    const text = data?.candidates?.[0]?.content?.parts?.map(p => p.text).join("") ?? "";
    if (!text) return json({ error: "empty" }, 502);
    return json({ reply: text });
  }
};

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}
