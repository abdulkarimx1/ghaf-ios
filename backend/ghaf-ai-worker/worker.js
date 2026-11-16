// Ghaf AI cloud proxy for Cloudflare Workers (free plan).
// Holds the Gemini API key server-side so it is never in the app. Every Ghaf install sends a random
// device ID (X-Ghaf-Device); the Worker allows FREE_DAILY_LIMIT questions per device per day and
// GLOBAL_DAILY_LIMIT across all devices, counted in KV. Only those daily counters are stored;
// questions and replies are not. The developer's APP_TOKEN (X-Ghaf-Token) skips the limits.
//
// Secrets: GEMINI_API_KEY, APP_TOKEN (optional). Vars: GEMINI_MODEL, FREE_DAILY_LIMIT, GLOBAL_DAILY_LIMIT.

const MAX_BODY = 16_000; // bytes; the app sends a question and a short summary, never full history

export default {
  async fetch(request, env) {
    if (request.method !== "POST" || new URL(request.url).pathname !== "/chat") {
      return json({ error: "not_found" }, 404);
    }
    const developer = env.APP_TOKEN && request.headers.get("X-Ghaf-Token") === env.APP_TOKEN;
    const device = request.headers.get("X-Ghaf-Device") || "";
    if (!developer && !/^[0-9A-F-]{36}$/i.test(device)) return json({ error: "unauthorized" }, 401);

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

    if (!developer) {
      const limited = await overLimit(env, device);
      if (limited) return json({ error: "limit", scope: limited }, 429);
    }

    const request_ = JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents,
      generationConfig: { temperature: 0.4, maxOutputTokens: 400 }
    });
    // Busy (429/503) on the main model: try the lighter one before giving up.
    const models = [env.GEMINI_MODEL || "gemini-flash-latest", "gemini-flash-lite-latest"];
    let upstream, detail = "";
    for (const model of models) {
      upstream = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
        body: request_
      });
      if (upstream.ok || ![429, 503].includes(upstream.status)) break;
    }
    if (upstream.ok) {
      const data = await upstream.json();
      const text = data?.candidates?.[0]?.content?.parts?.map(p => p.text).join("") ?? "";
      if (text) return json({ reply: text, engine: "gemini" });
    } else {
      // Google's own message (e.g. location not supported); it never contains the key itself.
      detail = (await upstream.json().catch(() => null))?.error?.message ?? "";
    }

    // Gemini refused (region, quota, busy): Cloudflare Workers AI, free daily allowance, no key.
    if (env.AI) {
      try {
        const result = await env.AI.run(env.FALLBACK_MODEL || "@cf/google/gemma-4-26b-a4b-it", {
          messages: [
            { role: "system", content: system },
            ...contents.map(c => ({ role: c.role === "model" ? "assistant" : "user", content: c.parts[0].text }))
          ],
          // Gemma 4 reasons before answering; switch that off for short replies, with headroom if it ignores it.
          chat_template_kwargs: { enable_thinking: false },
          max_tokens: 1200,
          temperature: 0.4
        });
        const text = result?.response ?? result?.choices?.[0]?.message?.content ?? "";
        if (text) return json({ reply: String(text).trim(), engine: "workers-ai" });
        detail = `${detail} | workers-ai returned no text`;
      } catch (error) {
        detail = `${detail} | workers-ai: ${String(error).slice(0, 120)}`;
      }
    }
    return json({ error: "upstream", status: upstream.status, detail: String(detail).slice(0, 240) }, 502);
  }
};

// Counts this request and reports which daily limit, if any, it would exceed.
// KV is eventually consistent, so a burst can overshoot slightly; good enough for a free-quota guard.
async function overLimit(env, device) {
  const day = new Date().toISOString().slice(0, 10);
  const deviceKey = `d:${day}:${device}`, globalKey = `g:${day}`;
  const [used, all] = await Promise.all([env.USAGE.get(deviceKey), env.USAGE.get(globalKey)]);
  const deviceCount = Number(used || 0), globalCount = Number(all || 0);
  if (deviceCount >= Number(env.FREE_DAILY_LIMIT || 20)) return "device";
  if (globalCount >= Number(env.GLOBAL_DAILY_LIMIT || 1000)) return "global";
  const ttl = { expirationTtl: 172800 };
  await Promise.all([env.USAGE.put(deviceKey, String(deviceCount + 1), ttl), env.USAGE.put(globalKey, String(globalCount + 1), ttl)]);
  return null;
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}
