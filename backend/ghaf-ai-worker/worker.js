// Ghaf AI cloud proxy for Cloudflare Workers (free plan).
// Holds the Gemini API key server-side so it is never in the app. Every Ghaf install sends a random
// device ID (X-Ghaf-Device); the Worker enforces tiered daily quotas per device and
// GLOBAL_DAILY_LIMIT across all devices, counted in KV. Questions, replies and audio are never stored;
// only counters and anonymous usage metadata are kept. APP_TOKEN skips the limits.
//
// Secrets: GEMINI_API_KEY, ELEVENLABS_API_KEY (optional; with vars ELEVEN_VOICE_HAMAD, ELEVEN_VOICE_MARIAM, ELEVEN_MODEL, MONTHLY_VOICE_CHARS, YEARLY_VOICE_CHARS), APP_TOKEN (optional), ACCESS_CODE_HASHES (comma-separated SHA-256 hex hashes). Vars: GEMINI_MODEL, FREE_DAILY_LIMIT, ESSENTIALS_DAILY_VOICE_LIMIT, COMPLETE_DAILY_VOICE_LIMIT, GLOBAL_DAILY_LIMIT,
// LIVE_DAILY_CALLS, LIVE_GLOBAL_DAILY_CALLS, LIVE_VOICE_AR, LIVE_VOICE_EN.

const MAX_BODY = 16_000; // bytes; the app sends a question and a short summary, never full history

export default {
  async fetch(request, env, ctx) {
    const path = new URL(request.url).pathname;
    const endpoint = ({ "/chat": "chat", "/speak": "speak", "/live-token": "live-token", "/voice-usage": "voice-usage", "/voice-turn": "voice-turn", "/redeem": "redeem", "/health": "health", "/tips": "tips" })[path] || "other";
    const buildHeader = request.headers.get("X-Ghaf-Build");
    const usage = { endpoint, model: "", outcome: "error", lang: "other", device: request.headers.get("X-Ghaf-Device") || "", developer: Boolean(env.APP_TOKEN && request.headers.get("X-Ghaf-Token") === env.APP_TOKEN), errorKind: "", build: ["release", "debug", "simulator"].includes(buildHeader) ? buildHeader : "unknown", input: 0, output: 0 };
    const started = Date.now();
    let response;
    try {
      response = await handle(request, env, usage);
      const path = new URL(request.url).pathname;
      if (["/chat", "/live-token", "/voice-turn"].includes(path)
          && /^[0-9A-F-]{36}$/i.test(usage.device) && response.headers.get("Content-Type")?.includes("application/json")) {
        const tier = normalizeTier(usage.tier);
        const counters = path === "/chat"
          ? await questionUsage(env, usage.device, tier)
          : await voiceUsage(env, usage.device, tier);
        const payload = await response.json();
        response = json({ ...payload, ...counters }, response.status);
      }
      if (response.status === 429) {
        if (!usage.outcome.startsWith("limited_")) usage.outcome = "limited_global";
      } else if (response.status >= 400) usage.outcome = "error";
      else if (usage.outcome === "error") usage.outcome = "ok";
      return response;
    } catch (error) {
      usage.errorKind = error?.name === "AbortError" ? "timeout" : error instanceof SyntaxError ? "parse" : "upstream_5xx";
      throw error;
    } finally {
      if (response?.status >= 500 && !usage.errorKind) usage.errorKind = "upstream_5xx";
      writeUsage(env, ctx, usage, Date.now() - started);
    }
  }
}

async function handle(request, env, usage) {
    const path = new URL(request.url).pathname;
    if (request.method === "GET" && path === "/health") return json({ ok: true });
    if (request.method === "GET" && path === "/announcement") return announcement(request, env);
    if (request.method === "GET" && path === "/tips") return json({ version: 1, tips: MONEY_TIPS });
    if (request.method === "GET" && path === "/voice-usage") {
      const auth = authorize(request, env);
      if (!auth) return json({ error: "unauthorized" }, 401);
      const codeTier = await accessCodeTier(request, env, auth.device);
      if (codeTier === false) return json({ error: "invalid_access_code" }, 401);
      const tier = codeTier || normalizeTier(request.headers.get("X-Ghaf-Tier"));
      if (usage) { usage.tier = tier; usage.model = "voice-usage-v1"; }
      return json(await voiceUsage(env, auth.device, tier));
    }
    if (request.method !== "POST" || !["/chat", "/speak", "/live-token", "/voice-turn", "/redeem"].includes(path)) {
      return json({ error: "not_found" }, 404);
    }
    const auth = authorize(request, env);
    if (!auth) return json({ error: "unauthorized" }, 401);
    const { developer, device } = auth;

    const raw = await request.text();
    if (raw.length > MAX_BODY) return json({ error: "too_large" }, 413);

    let body;
    try { body = JSON.parse(raw); } catch { return json({ error: "bad_json" }, 400); }
    if (path === "/redeem") return redeemAccessCode(body, env, device, usage);
    const codeTier = await accessCodeTier(request, env, device);
    if (codeTier === false) return json({ error: "invalid_access_code" }, 401);
    if (codeTier) body.tier = codeTier;
    usage.tier = normalizeTier(body.tier);
    if (!developer && usage.tier === "free" && ["/chat", "/speak", "/live-token", "/voice-turn"].includes(path)) {
      if (usage) usage.outcome = "limited_device";
      return json({ error: "pro_required", code: "pro_required" }, 429);
    }
    if (path === "/voice-turn") {
      const tier = normalizeTier(body.tier);
      if (!developer) {
        const usageState = await incrementVoiceUsage(env, device, tier);
        if (!usageState.allowed) { if (usage) usage.outcome = "limited_device"; return json({ error: "daily_limit", ...usageState.usage }, 429); }
        if (usage) { usage.model = "voice-turn-counter-v1"; usage.outcome = "ok"; usage.lang = body.language === "ar" ? "ar" : "en"; }
        return json(usageState.usage);
      }
      if (usage) { usage.model = "voice-turn-counter-v1"; usage.outcome = "ok"; }
      return json(await voiceUsage(env, device, tier));
    }
    if (path === "/speak") {
      if (usage) usage.lang = detectLanguage(String(body.text || ""));
      if (!developer) {
        const tier = normalizeTier(body.tier);
        const reservation = await incrementVoiceUsage(env, device, tier);
        if (!reservation.allowed) {
          if (usage) usage.outcome = "limited_device";
          return json({ error: "daily_limit", ...reservation.usage }, 429);
        }
      }
      return speak(body, env, developer, device, usage);
    }
    if (path === "/live-token") return liveToken(body, env, developer, device, usage);
    const { question, facts = "", direct = "", language = "en", history = [], mode = "chat" } = body;
    if (typeof question !== "string" || !question.trim()) return json({ error: "missing_question" }, 400);

    // shortcut: tier is client-reported until App Attest/receipt validation at launch.
    const tier = ["pro_monthly", "pro_yearly"].includes(body.tier) ? body.tier : "free";
    const detectedLanguage = detectLanguage(question);
    const replyLanguage = detectedLanguage === "ar" || detectedLanguage === "en" ? detectedLanguage : language;
    if (!developer && tier === "pro_yearly") {
      const inputTokens = Math.ceil((question.length + String(facts).length + String(direct).length + JSON.stringify(history).length) / 4);
      if (!await reserveYearlyBudget(env, device, inputTokens, 400, 0)) { if (usage) usage.outcome = "limited_device"; return json({ error: "limit", scope: "budget" }, 429); }
    }

    const system = [
      "You are Ghaf AI, a warm, concise personal finance assistant in a UAE money app.",
      "Answer only from the FACTS and the DIRECT ANSWER. Quote amounts exactly with their currency.",
      "Never invent transactions or balances and never add amounts in different currencies.",
      "If a DIRECT ANSWER is given, keep every number in it and add at most one short, useful tip.",
      "Ghaf draws inline charts, including petal charts, using show_chart; never claim you cannot create a chart.",
      "When the DIRECT ANSWER contains newline-separated list rows, preserve that readable list format.",
      "If the message is not about money, reply in one light, friendly line, then offer one thing you can do.",
      `Per-turn language hint: ${replyLanguage === "ar" ? "Arabic (natural Gulf Arabic)" : "English"}. Reply only in this language, including spoken numbers. Do not introduce yourself or mix languages unless the user did so in their latest turn.`,
      `Reply in ${replyLanguage === "ar" ? "Arabic (Gulf-friendly Modern Standard Arabic)" : "English"}, in 1-4 short sentences.`,
      mode === "voice" ? "This reply is spoken aloud in a live voice conversation: 1-2 short, natural sentences, no lists, symbols or currency codes (say 'dirhams'), and end with a brief follow-up question when it helps the person continue." : "",
      "",
      "FACTS:", String(facts).slice(0, 8000),
      direct ? `\nDIRECT ANSWER FROM THE LEDGER: ${direct}` : ""
    ].join("\n");

    const contents = [
      ...history.slice(-6).map(m => ({ role: m.isUser ? "user" : "model", parts: [{ text: String(m.text).slice(0, 600) }] })),
      { role: "user", parts: [{ text: question.slice(0, 600) }] }
    ];
    if (usage) {
      const lastUserText = [...history].reverse().find(m => m?.isUser)?.text ?? question;
      usage.lang = detectLanguage(String(lastUserText));
    }

    if (!developer) {
      const cap = tier === "pro_yearly" ? 200 : tier === "pro_monthly" ? 60 : Number(env.FREE_DAILY_LIMIT ?? 0);
      const limited = await overLimit(env, device, `d:${tier}`, cap, Number(env.GLOBAL_DAILY_LIMIT || 1000));
      if (limited) { if (usage) usage.outcome = `limited_${limited}`; return json({ error: "limit", scope: limited }, 429); }
    }

    const request_ = JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents,
      generationConfig: { temperature: 0.4, maxOutputTokens: 400 }
    });
    // Busy (429/503) on the main model: try the lighter one before giving up.
    const needsReasoning = /chart|compare|comparison|advice|forecast|trend|مخطط|قارن|نصيحة|توقع/i.test(question);
    const models = needsReasoning
      ? [env.REASONING_MODEL || "gemini-3.8-flash", env.GEMINI_MODEL || "gemini-3.5-flash-lite"]
      : [env.GEMINI_MODEL || "gemini-3.5-flash-lite"];
    let upstream, detail = "", usedModel = models[0];
    for (const model of models) {
      usedModel = model;
      upstream = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
        body: request_
      });
      if (upstream.ok || upstream.status !== 503) break;
    }
    if (upstream.ok) {
      const data = await upstream.json();
      if (usage) {
        usage.input = Number(data?.usageMetadata?.promptTokenCount) || 0;
        usage.output = Number(data?.usageMetadata?.candidatesTokenCount) || 0;
      }
      const text = data?.candidates?.[0]?.content?.parts?.map(p => p.text).join("") ?? "";
      if (text) { if (usage) { usage.model = usedModel; usage.outcome = usedModel === models[0] ? "ok" : "fallback"; } return json({ reply: text, engine: "gemini" }); }
      if (usage) usage.errorKind = "parse";
    } else if (upstream.status === 429) {
      if (usage) { usage.outcome = "limited_global"; usage.errorKind = "upstream_4xx"; }
      return json({ error: "limit" }, 429);
    } else {
      if (usage) usage.errorKind = upstream.status < 500 ? "upstream_4xx" : "upstream_5xx";
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
        if (text) {
          if (usage) { usage.model = env.FALLBACK_MODEL || "@cf/google/gemma-4-26b-a4b-it"; usage.outcome = "fallback"; usage.input = Number(result?.usage?.prompt_tokens) || 0; usage.output = Number(result?.usage?.completion_tokens) || 0; }
          return json({ reply: String(text).trim(), engine: "workers-ai" });
        }
        detail = `${detail} | workers-ai returned no text`;
      } catch (error) {
        detail = `${detail} | workers-ai: ${String(error).slice(0, 120)}`;
      }
    }
    console.error("chat upstream", upstream.status, String(detail).slice(0, 240));
    return json({ error: "upstream" }, 502);
  }

// Short, source-linked financial literacy tips; update this list without shipping an app release.
const MONEY_TIPS = [
  ["Give every dirham a purpose before the month begins.", "حدّد وجهةً لكل درهم قبل بداية الشهر.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Track spending for a week to see where your money goes.", "تابع مصروفاتك أسبوعًا لتعرف أين يذهب مالك.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Set aside savings when income arrives, not only what remains.", "خصّص للادخار عند وصول الدخل، لا مما يتبقى فقط.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/saving/"],
  ["Keep a small buffer for bills that change from month to month.", "احتفظ بمبلغ احتياطي للفواتير التي تتغيّر من شهر إلى آخر.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Review subscriptions quarterly and cancel what you no longer use.", "راجع اشتراكاتك كل ثلاثة أشهر وألغِ ما لم تعد تستخدمه.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Compare a purchase with your priorities before you buy.", "وازن بين الشراء وأولوياتك قبل إتمامه.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/"],
  ["An emergency fund can help cover an unexpected expense.", "يساعدك صندوق الطوارئ على تغطية المصروفات المفاجئة.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/saving/"],
  ["Start an emergency fund with an amount that feels manageable.", "ابدأ صندوق الطوارئ بمبلغ يناسب قدرتك.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/saving/"],
  ["Plan for irregular costs such as car maintenance and annual fees.", "خطّط للمصروفات غير المنتظمة مثل صيانة السيارة والرسوم السنوية.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Check your account balance before a large discretionary purchase.", "تحقّق من رصيد حسابك قبل شراء شيء غير ضروري وباهظ الثمن.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/"],
  ["Use recent spending, not guesses, to set next month's budget.", "استند إلى مصروفاتك الفعلية عند إعداد ميزانية الشهر المقبل.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Separate needs, wants and savings when planning your spending.", "ميّز بين الاحتياجات والرغبات والادخار عند تخطيط مصروفاتك.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Pay attention to fees; small charges can add up over time.", "انتبه إلى الرسوم؛ فالمبالغ الصغيرة قد تتراكم مع الوقت.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/"],
  ["Set a realistic limit for flexible spending categories.", "ضع حدًا واقعيًا لبنود الإنفاق المرنة.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["If income varies, build your plan around a cautious estimate.", "إذا كان دخلك متغيّرًا، فابنِ خطتك على تقدير متحفّظ.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Save for known future costs a little at a time.", "ادّخر تدريجيًا للمصروفات المستقبلية المعروفة.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/saving/"],
  ["Check whether a discount still fits your budget before buying.", "تحقّق من ملاءمة الشراء لميزانيتك حتى عند وجود خصم.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/"],
  ["A budget is a plan you can adjust as your circumstances change.", "الميزانية خطة يمكنك تعديلها عندما تتغيّر ظروفك.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Review upcoming bills before choosing how much to spend this week.", "راجع الفواتير القادمة قبل تحديد إنفاقك لهذا الأسبوع.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Write down a savings goal and the date you hope to reach it.", "دوّن هدفًا للادخار والموعد الذي تطمح إلى بلوغه.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/saving/"],
  ["Automating a regular transfer can make saving more consistent.", "يساعدك التحويل الدوري التلقائي على الانتظام في الادخار.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/saving/"],
  ["Keep essential expenses in mind before taking on a new payment.", "ضع النفقات الأساسية في الحسبان قبل الالتزام بدفعة جديدة.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/"],
  ["Look at both the monthly cost and the full yearly cost of a plan.", "انظر إلى تكلفة الاشتراك شهريًا وسنويًا قبل اختياره.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Make room in your budget for occasional, not just monthly, expenses.", "اترك في ميزانيتك مجالًا للمصروفات العرضية إلى جانب الشهرية.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["If a bill is hard to pay, contact the provider early to discuss options.", "إذا تعذّر عليك سداد فاتورة، فتواصل مع الجهة مبكرًا لمعرفة الخيارات.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/"],
  ["Compare prices for recurring essentials when it is practical.", "قارن أسعار احتياجاتك المتكررة متى كان ذلك عمليًا.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/"],
  ["Keep savings accessible for emergencies while separate from daily spending.", "احتفظ بمدخرات الطوارئ في مكان متاح ومنفصل عن إنفاقك اليومي.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/saving/"],
  ["Update your plan after a major change in income or expenses.", "حدّث خطتك بعد أي تغيّر كبير في دخلك أو نفقاتك.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["A short weekly money check-in can help catch overspending early.", "تساعدك مراجعة أسبوعية سريعة لأموالك على ملاحظة تجاوز الإنفاق مبكرًا.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/budgeting/"],
  ["Choose a savings amount you can repeat consistently.", "اختر مبلغًا للادخار تستطيع الالتزام به بانتظام.", "CFPB", "https://www.consumerfinance.gov/consumer-tools/saving/"]
].map(([en, ar, source, url], index) => ({ id: index + 1, en, ar, source, url }));

async function liveToken(body, env, developer, device, usage) {
  // Live calls speak in Gemini voices, not Hamad/Mariam, so they stay off unless the owner turns them on.
  if (env.LIVE_CALLS_ENABLED !== "1") { if (usage) usage.outcome = "voice_off"; return json({ error: "voice_off" }, 410); }
  if (usage) usage.lang = body.language === "ar" ? "ar" : body.language === "en" ? "en" : "other";
  if (body.language !== "ar" && body.language !== "en") return json({ error: "bad_language" }, 400);
  const character = body.character === "Mariam" ? "Mariam" : "Hamad";
  const tier = ["pro_monthly", "pro_yearly"].includes(body.tier) ? body.tier : "free";
  if (usage) usage.tier = tier;
  if (!developer && tier === "pro_yearly" && !await reserveYearlyBudget(env, device, 0, 0, 1)) { if (usage) usage.outcome = "limited_device"; return json({ error: "limit", scope: "budget" }, 429); }
  if (!developer && tier === "free") {
    if (usage) usage.outcome = "limited_device";
    return json({ error: "pro_required", code: "pro_required" }, 429);
  }
  if (!developer) {
    // Turns are counted by /voice-turn, but a session token is the costly thing a client can request,
    // so it is capped here too: no token once the day's turns are used, and sessions per device/global are bounded.
    const turns = await voiceUsage(env, device, tier);
    if (turns.used >= turns.limit) { if (usage) usage.outcome = "limited_device"; return json({ error: "daily_limit", ...turns }, 429); }
    const limited = await overLimit(env, device, `vs:${tier}`, voiceLimit(tier, env), Number(env.VOICE_GLOBAL_DAILY_LIMIT || 3000));
    if (limited) { if (usage) usage.outcome = `limited_${limited}`; return json({ error: "daily_limit", ...turns }, 429); }
  }
  if (!env.GEMINI_API_KEY) return json({ error: "upstream" }, 502);
  const expires = new Date(Date.now() + 30 * 60_000).toISOString();
  let response;
  try { response = await fetch("https://generativelanguage.googleapis.com/v1alpha/auth_tokens", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
    body: JSON.stringify({
      uses: 1, expireTime: expires, newSessionExpireTime: new Date(Date.now() + 60_000).toISOString(),
      bidiGenerateContentSetup: { model: env.LIVE_MODEL || "models/gemini-3.8-live", generationConfig: { responseModalities: ["AUDIO"] }, sessionResumption: {} },
      // Without a field mask Google ignores the app's whole setup (instructions, tools, voice). Lock only these.
      fieldMask: "model,generationConfig.responseModalities,sessionResumption"
    })
  }); } catch { return json({ error: "upstream" }, 502); }
  if (!response.ok) {
    if (usage) { usage.errorKind = response.status < 500 ? "upstream_4xx" : "upstream_5xx"; if (response.status === 429) usage.outcome = "limited_global"; }
    const detail = (await response.json().catch(() => null))?.error?.message ?? "";
    console.error("live-token upstream", response.status, String(detail).slice(0, 240));
    return response.status === 429 ? json({ error: "limit" }, 429) : json({ error: "upstream" }, 502);
  }
  const data = await response.json().catch(() => null);
  if (!data?.name) { if (usage) usage.errorKind = "parse"; return json({ error: "upstream" }, 502); }
  if (usage) { usage.model = env.LIVE_MODEL || "models/gemini-3.8-live"; usage.outcome = "ok"; }
  return json({ token: data.name, model: env.LIVE_MODEL || "models/gemini-3.8-live", expiresAt: expires,
    voice: character === "Mariam" ? env.VOICE_MARIAM || "Kore" : env.VOICE_HAMAD || "Orus" });
}

async function announcement(request, env) {
  const raw = env.ANNOUNCEMENT || await env.USAGE?.get("ghaf:announcement");
  if (!raw) return json({ error: "no_announcement" }, 404);
  let value;
  try { value = typeof raw === "string" ? JSON.parse(raw) : raw; } catch { return json({ error: "invalid_announcement" }, 500); }
  if (!value || typeof value !== "object" || !value.id || !value.title || !value.body || !value.expires) {
    return json({ error: "invalid_announcement" }, 500);
  }
  const expiresAt = Date.parse(value.expires);
  if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) return json({ error: "no_announcement" }, 404);
  const language = (request.headers.get("Accept-Language") || "en").toLowerCase().startsWith("ar") ? "ar" : "en";
  const localized = (item) => typeof item === "string" ? item : item?.[language] || item?.en || "";
  return json({
    id: String(value.id), title: localized(value.title), body: localized(value.body),
    ...(typeof value.minVersion === "string" ? { minVersion: value.minVersion } : {}),
    ...(typeof value.code === "string" ? { code: value.code } : {}),
    expires: new Date(expiresAt).toISOString()
  });
}

async function redeemAccessCode(body, env, device, usage) {
  const day = new Date().toISOString().slice(0, 10);
  const key = `redeem:${day}:${device}`;
  const attempts = Number(await env.USAGE.get(key) || 0);
  if (attempts >= 5) {
    if (usage) usage.outcome = "limited_device";
    return json({ error: "rate_limited" }, 429);
  }
  await env.USAGE.put(key, String(attempts + 1), { expirationTtl: 172800 });
  const code = typeof body.code === "string" ? body.code : "";
  if (!code || code.length > 256 || !await matchesAccessCode(code, env.ACCESS_CODE_HASHES)) {
    return json({ error: "invalid_code" }, 401);
  }
  if (usage) { usage.tier = "pro_yearly"; usage.model = "access-code-v1"; }
  return json({ tier: "pro_yearly" });
}

// R2: the header path used to check codes with no limit, so short codes could be guessed.
// Wrong codes now count per device (5/day, same as /redeem) and per IP (30/day); past the limit nothing is checked.
async function accessCodeTier(request, env, device = "") {
  const code = request.headers.get("X-Ghaf-Code");
  if (!code) return null;
  if (code.length > 256) return false;
  const day = new Date().toISOString().slice(0, 10);
  const ip = request.headers.get("CF-Connecting-IP") || "";
  const deviceKey = `codefail:${day}:${device}`, ipKey = `codefail-ip:${day}:${ip}`;
  const [deviceFails, ipFails] = await Promise.all([env.USAGE.get(deviceKey), ip ? env.USAGE.get(ipKey) : null]);
  if (Number(deviceFails || 0) >= 5 || Number(ipFails || 0) >= 30) return false;
  if (await matchesAccessCode(code, env.ACCESS_CODE_HASHES)) return "pro_yearly";
  await env.USAGE.put(deviceKey, String(Number(deviceFails || 0) + 1), { expirationTtl: 172800 });
  if (ip) await env.USAGE.put(ipKey, String(Number(ipFails || 0) + 1), { expirationTtl: 172800 });
  return false;
}

async function matchesAccessCode(code, configuredHashes) {
  const expectedHashes = String(configuredHashes || "").split(",").map(value => value.trim().toLowerCase()).filter(Boolean);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(code)));
  const actual = [...digest].map(byte => byte.toString(16).padStart(2, "0")).join("");
  let matched = 0;
  for (const expected of expectedHashes) matched |= constantTimeHexEqual(actual, expected) ? 1 : 0;
  return matched === 1;
}

function constantTimeHexEqual(left, right) {
  if (!/^[0-9a-f]{64}$/.test(right)) return false;
  let difference = 0;
  for (let index = 0; index < 64; index++) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}

function authorize(request, env) {
  const developer = Boolean(env.APP_TOKEN && request.headers.get("X-Ghaf-Token") === env.APP_TOKEN);
  const device = request.headers.get("X-Ghaf-Device") || "";
  return developer || /^[0-9A-F-]{36}$/i.test(device) ? { developer, device } : null;
}

function normalizeTier(value) {
  return ["pro_monthly", "pro_yearly"].includes(value) ? value : "free";
}

function voiceLimit(tier, env) {
  return {
    free: 0,
    pro_monthly: Number(env.ESSENTIALS_DAILY_VOICE_LIMIT ?? 3),
    pro_yearly: Number(env.COMPLETE_DAILY_VOICE_LIMIT ?? 10)
  }[tier] ?? 0;
}

async function questionUsage(env, device, tier) {
  const day = new Date().toISOString().slice(0, 10);
  const used = Number(await env.USAGE.get(`d:${tier}:${day}:${device}`) || 0);
  const limit = tier === "pro_yearly" ? 200 : tier === "pro_monthly" ? 60 : Number(env.FREE_DAILY_LIMIT ?? 0);
  const resetsAt = new Date(Date.UTC(Number(day.slice(0, 4)), Number(day.slice(5, 7)) - 1, Number(day.slice(8, 10)) + 1)).toISOString();
  return { used, limit, resetsAt };
}

async function voiceUsage(env, device, tier) {
  const day = new Date().toISOString().slice(0, 10);
  const used = Number(await env.USAGE.get(`v:${tier}:${day}:${device}`) || 0);
  const resetsAt = new Date(Date.UTC(Number(day.slice(0, 4)), Number(day.slice(5, 7)) - 1, Number(day.slice(8, 10)) + 1)).toISOString();
  return { used, limit: voiceLimit(tier, env), resetsAt };
}

async function incrementVoiceUsage(env, device, tier) {
  const before = await voiceUsage(env, device, tier);
  if (before.used >= before.limit) return { allowed: false, usage: before };
  const day = new Date().toISOString().slice(0, 10);
  await env.USAGE.put(`v:${tier}:${day}:${device}`, String(before.used + 1), { expirationTtl: 172800 });
  return { allowed: true, usage: { ...before, used: before.used + 1 } };
}

// Text to speech for Ghaf AI's voice mode. Gemini's speech model first (Arabic and English);
// Deepgram Aura on Workers AI for English when Gemini is unavailable. Returns audio bytes.
async function speak(body, env, developer, device, usage) {
  const text = String(body.text || "").trim().slice(0, 700);
  const arabic = body.language === "ar";
  const character = body.character === "Mariam" ? "Mariam" : "Hamad";
  const voice = character === "Mariam" ? env.VOICE_MARIAM || "Kore" : env.VOICE_HAMAD || "Orus";
  const tier = ["pro_monthly", "pro_yearly"].includes(body.tier) ? body.tier : "free";
  if (!developer && tier === "free") {
    if (usage) usage.outcome = "limited_device";
    return json({ error: "pro_required", code: "pro_required" }, 429);
  }
  if (!text) return json({ error: "missing_text" }, 400);
  // Developer-only clip studio: records the app's bundled Hamad/Mariam clips (Gemini Orus/Kore) with a delivery note.
  // Requires the private developer token, so no user request can reach it.
  if (developer && body.studio === true) return studioSpeak(text, character, String(body.style || ""), env);
  // Developer-only ElevenLabs studio for marketing/onboarding narration: any voice ID, the higher-quality multilingual model.
  if (developer && body.studio === "eleven") return elevenStudio(text, String(body.voice || ""), body.settings, env);
  // Developer-only background music / sound bed for the same narration (text is the music prompt).
  // Developer-only ElevenLabs voice design (design a voice from a description, then save it) for onboarding narration.
  if (developer && body.studio === "eleven-api") return elevenAPI(String(body.path || ""), body.payload, env);
  if (developer && body.studio === "eleven-music") return elevenMusic(text, Number(body.seconds) || 30, body.kind === "sfx", env);
  // Owner rule (2026-11-25): users only ever hear Hamad or Mariam. Until ElevenLabs is paid for, answers are
  // text only ("voice_off"); there is no stand-in voice, and old stand-in audio in the cache is never served.
  if (!useEleven(env)) { if (usage) usage.outcome = "voice_off"; return json({ error: "voice_off" }, 410); }
  const cacheDigest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`eleven\n${character}\n${text}`));
  const cacheKey = `tts:${Array.from(new Uint8Array(cacheDigest), b => b.toString(16).padStart(2, "0")).join("")}`;
  const cached = await env.USAGE.get(cacheKey, "arrayBuffer");
  if (cached) { if (usage) { usage.model = env.ELEVEN_MODEL || "eleven_flash_v2_5"; usage.outcome = "ok"; } return new Response(cached, { headers: { "Content-Type": "audio/wav", "X-Ghaf-Voice": "elevenlabs", "X-Ghaf-Cache": "hit" } }); }
  return elevenSpeak(text, character, tier, env, developer, device, usage, cacheKey);
}

async function studioSpeak(text, character, style, env) {
  if (!env.GEMINI_API_KEY) return json({ error: "upstream" }, 502);
  const voice = character === "Mariam" ? env.VOICE_MARIAM || "Kore" : env.VOICE_HAMAD || "Orus";
  const upstream = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${env.TTS_MODEL || "gemini-3.1-flash-tts-preview"}:generateContent`, {
    method: "POST", headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
    body: JSON.stringify({ contents: [{ parts: [{ text: `${style}\n\n${text}` }] }],
      generationConfig: { responseModalities: ["AUDIO"], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } } } })
  });
  if (!upstream.ok) return json({ error: "upstream", status: upstream.status, detail: (await upstream.text()).slice(0, 300) }, upstream.status === 429 ? 429 : 502);
  const b64 = (await upstream.json())?.candidates?.[0]?.content?.parts?.find(p => p.inlineData)?.inlineData?.data;
  if (!b64) return json({ error: "parse" }, 502);
  return new Response(wav(Uint8Array.from(atob(b64), c => c.charCodeAt(0))), { headers: { "Content-Type": "audio/wav", "X-Ghaf-Voice": "studio" } });
}

function useEleven(env) { return Boolean(env.ELEVENLABS_API_KEY && env.ELEVEN_VOICE_HAMAD && env.ELEVEN_VOICE_MARIAM); }

function voiceCharacterAllowance(tier, env) {
  return { pro_monthly: Number(env.MONTHLY_VOICE_CHARS ?? 15000), pro_yearly: Number(env.YEARLY_VOICE_CHARS ?? 20000) }[tier] ?? 0;
}

async function elevenSpeak(text, character, tier, env, developer, device, usage, cacheKey) {
  const month = new Date().toISOString().slice(0, 7);
  const key = `vc:${tier}:${month}:${device}`;
  const used = Number(await env.USAGE.get(key) || 0);
  const allowance = voiceCharacterAllowance(tier, env);
  if (!developer) {
    if (used + text.length > allowance) { if (usage) usage.outcome = "limited_device"; return json({ error: "limit", scope: "voice_month", used, limit: allowance }, 429); }
    const limited = await overLimit(env, device, "s", Number(env.SPEAK_DAILY_LIMIT || 10));
    if (limited) { if (usage) usage.outcome = `limited_${limited}`; return json({ error: "limit", scope: limited }, 429); }
  }
  const voiceID = character === "Mariam" ? env.ELEVEN_VOICE_MARIAM : env.ELEVEN_VOICE_HAMAD;
  const model = env.ELEVEN_MODEL || "eleven_flash_v2_5";
  if (usage) usage.model = model;
  let upstream;
  try {
    upstream = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceID)}?output_format=pcm_24000`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "xi-api-key": env.ELEVENLABS_API_KEY },
      body: JSON.stringify({ text, model_id: model })
    });
  } catch { return json({ error: "unavailable" }, 503); }
  if (upstream.status === 429) { if (usage) { usage.outcome = "limited_global"; usage.errorKind = "upstream_4xx"; } return json({ error: "limit" }, 429); }
  if (!upstream.ok) {
    if (usage) usage.errorKind = upstream.status < 500 ? "upstream_4xx" : "upstream_5xx";
    // Unpaid plan, bad key or missing voice: no Hamad/Mariam audio is possible, so tell the app to stay text-only.
    if ([401, 402, 403, 404].includes(upstream.status)) { console.error("eleven upstream", upstream.status); if (usage) usage.outcome = "voice_off"; return json({ error: "voice_off" }, 410); }
    console.error("eleven upstream", upstream.status, (await upstream.text().catch(() => "")).slice(0, 240));
    return json({ error: "unavailable" }, 503);
  }
  const audio = wav(new Uint8Array(await upstream.arrayBuffer()));
  // Charge the allowance only for audio actually produced; cached repeats stay free.
  if (!developer) await env.USAGE.put(key, String(used + text.length), { expirationTtl: 40 * 86400 });
  await env.USAGE.put(cacheKey, audio, { expirationTtl: 604800 });
  if (usage) { usage.output = text.length; usage.outcome = "ok"; }
  return new Response(audio, { headers: { "Content-Type": "audio/wav", "X-Ghaf-Voice": "elevenlabs" } });
}

async function elevenAPI(path, payload, env) {
  if (!env.ELEVENLABS_API_KEY) return json({ error: "voice_off" }, 410);
  if (!["/v1/text-to-voice/design", "/v1/text-to-voice"].includes(path)) return json({ error: "bad_path" }, 400);
  const upstream = await fetch(`https://api.elevenlabs.io${path}`, {
    method: "POST", headers: { "Content-Type": "application/json", "xi-api-key": env.ELEVENLABS_API_KEY }, body: JSON.stringify(payload || {})
  }).catch(() => null);
  if (!upstream) return json({ error: "unavailable" }, 503);
  return new Response(await upstream.text(), { status: upstream.ok ? 200 : 502, headers: { "Content-Type": "application/json" } });
}

async function elevenMusic(prompt, seconds, sfx, env) {
  if (!env.ELEVENLABS_API_KEY) return json({ error: "voice_off" }, 410);
  const length = Math.min(Math.max(seconds, 5), sfx ? 30 : 120);
  const upstream = await fetch(sfx ? "https://api.elevenlabs.io/v1/sound-generation" : "https://api.elevenlabs.io/v1/music", {
    method: "POST", headers: { "Content-Type": "application/json", "xi-api-key": env.ELEVENLABS_API_KEY },
    body: JSON.stringify(sfx ? { text: prompt, duration_seconds: length, prompt_influence: 0.5 }
                             : { prompt, music_length_ms: length * 1000, force_instrumental: true })
  }).catch(() => null);
  if (!upstream) return json({ error: "unavailable" }, 503);
  if (!upstream.ok) return json({ error: "upstream", status: upstream.status, detail: (await upstream.text().catch(() => "")).slice(0, 300) }, 502);
  return new Response(await upstream.arrayBuffer(), { headers: { "Content-Type": "audio/mpeg", "X-Ghaf-Voice": "eleven-music" } });
}

async function elevenStudio(text, voiceID, settings, env) {
  if (!env.ELEVENLABS_API_KEY) return json({ error: "voice_off" }, 410);
  if (!/^[A-Za-z0-9]{16,32}$/.test(voiceID)) return json({ error: "bad_voice" }, 400);
  const voice_settings = settings && typeof settings === "object" ? settings : undefined;
  const upstream = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceID}?output_format=pcm_24000`, {
    method: "POST", headers: { "Content-Type": "application/json", "xi-api-key": env.ELEVENLABS_API_KEY },
    body: JSON.stringify({ text, model_id: "eleven_multilingual_v2", voice_settings })
  }).catch(() => null);
  if (!upstream) return json({ error: "unavailable" }, 503);
  if (!upstream.ok) return json({ error: "upstream", status: upstream.status, detail: (await upstream.text().catch(() => "")).slice(0, 300) }, 502);
  return new Response(wav(new Uint8Array(await upstream.arrayBuffer())), { headers: { "Content-Type": "audio/wav", "X-Ghaf-Voice": "eleven-studio" } });
}

// Gemini returns raw 24 kHz 16-bit mono PCM; wrap it in a WAV header so iOS can play it directly.
function wav(pcm) {
  const header = new ArrayBuffer(44), v = new DataView(header), rate = 24000;
  const put = (o, str) => [...str].forEach((c, i) => v.setUint8(o + i, c.charCodeAt(0)));
  put(0, "RIFF"); v.setUint32(4, 36 + pcm.length, true); put(8, "WAVE"); put(12, "fmt ");
  v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true); v.setUint32(24, rate, true);
  v.setUint32(28, rate * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true); put(36, "data"); v.setUint32(40, pcm.length, true);
  const out = new Uint8Array(44 + pcm.length); out.set(new Uint8Array(header), 0); out.set(pcm, 44);
  return out;
}

// Counts this request and reports which daily limit, if any, it would exceed.
// KV is eventually consistent, so a burst can overshoot slightly; good enough for a free-quota guard.
async function overLimit(env, device, kind = "d", deviceLimit = Number(env.FREE_DAILY_LIMIT || 20), globalLimit = Number(env.GLOBAL_DAILY_LIMIT || 1000)) {
  const day = new Date().toISOString().slice(0, 10);
  const globalKind = kind.startsWith("v:") || kind.startsWith("vs:") ? "live" : kind === "s" ? "speak" : "chat";
  const deviceKey = `${kind}:${day}:${device}`, globalKey = `g:${globalKind}:${day}`;
  const [used, all] = await Promise.all([env.USAGE.get(deviceKey), env.USAGE.get(globalKey)]);
  const deviceCount = Number(used || 0), globalCount = Number(all || 0);
  if (deviceCount >= deviceLimit) return "device";
  if (globalCount >= globalLimit) return "global";
  const ttl = { expirationTtl: 172800 };
  await Promise.all([env.USAGE.put(deviceKey, String(deviceCount + 1), ttl), env.USAGE.put(globalKey, String(globalCount + 1), ttl)]);
  return null;
}

async function reserveYearlyBudget(env, device, inputTokens, outputTokens, audioSeconds) {
  const month = new Date().toISOString().slice(0, 7);
  const key = `c:${month}:${device}`;
  const used = Number(await env.USAGE.get(key) || 0);
  const ceiling = Number(env.YEARLY_MONTHLY_BUDGET_USD || 1.50);
  const estimate = inputTokens * Number(env.TEXT_INPUT_USD_PER_MILLION || 0.10) / 1_000_000
    + outputTokens * Number(env.TEXT_OUTPUT_USD_PER_MILLION || 0.40) / 1_000_000
    + audioSeconds * Number(env.TTS_AUDIO_USD_PER_SECOND || 0.0003);
  if (used + estimate > ceiling) return false;
  await env.USAGE.put(key, String(used + estimate), { expirationTtl: 35 * 86400 });
  return true;
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}

function detectLanguage(text) {
  const letters = [...text].filter(c => /\p{L}/u.test(c));
  if (!letters.length) return "other";
  const arabic = letters.filter(c => /\p{Script=Arabic}/u.test(c)).length;
  if (!arabic) return "en";
  if (arabic === letters.length) return "ar";
  return arabic / letters.length >= 0.3 ? "ar" : "mixed";
}

function writeUsage(env, ctx, usage, latency) {
  if (!env.USAGE_EVENTS?.writeDataPoint || !ctx?.waitUntil) return;
  const write = Promise.resolve().then(async () => {
    let deviceHash = "";
    if (usage.device && env.AI_HASH_SALT) {
      const bytes = new TextEncoder().encode(usage.device + env.AI_HASH_SALT);
      const digest = await crypto.subtle.digest("SHA-256", bytes);
      deviceHash = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
    }
    env.USAGE_EVENTS.writeDataPoint({
      indexes: ["ghaf"],
      blobs: [usage.endpoint, usage.model, usage.outcome, usage.lang, deviceHash, usage.errorKind, usage.build],
      doubles: [latency, usage.input, usage.output, usage.developer ? 1 : 0]
    });
  }).catch(() => {});
  try { ctx.waitUntil(write); } catch { /* analytics must never affect the response */ }
}
