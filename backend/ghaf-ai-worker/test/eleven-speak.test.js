import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.js';

const device = '12345678-1234-1234-1234-123456789abc';
const month = new Date().toISOString().slice(0, 7);
const day = new Date().toISOString().slice(0, 10);
const allowanceKey = `vc:pro_monthly:${month}:${device}`;
const hash = async text => {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return `gtts:${Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('')}`;
};

function setup(initial = {}) {
  const values = new Map(Object.entries(initial));
  return { values, env: {
    GEMINI_API_KEY: 'k', TTS_MODEL: 'gemini-3.1-flash-tts-preview',
    VOICE_HAMAD: 'Orus', VOICE_MARIAM: 'Kore',
    USAGE: { get: async key => values.get(key) ?? null, put: async (key, value) => values.set(key, value) }
  } };
}
const speak = (env, text, character = 'Mariam', language = 'ar', liveSession = false) => worker.fetch(new Request('https://worker.test/speak', {
  method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'pro_monthly' },
  body: JSON.stringify({ text, character, tier: 'pro_monthly', language, liveSession }) }), env);

test('user speech uses approved Gemini TTS voice and style, then caches under gtts', async t => {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    calls.push([String(url), JSON.parse(init.body)]);
    return Response.json({ candidates: [{ content: { parts: [{ inlineData: { data: 'AQI=' } }] } }] });
  });
  const { env, values } = setup();
  const text = 'مرحبا';
  const first = await speak(env, text);
  assert.equal(first.status, 200);
  assert.equal(first.headers.get('X-Ghaf-Voice'), 'gemini-tts');
  assert.equal((await first.arrayBuffer()).byteLength, 46);
  assert.match(calls[0][0], /models\/gemini-3.1-flash-tts-preview:generateContent/);
  assert.equal(calls[0][1].contents[0].parts[0].text,
    'Read this in a calm, relaxed, low-key voice with a natural Emirati Gulf accent. Measured pace, gentle and composed, not cheerful, not excited, no smile in the voice:\n\nمرحبا');
  assert.equal(calls[0][1].generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName, 'Kore');
  const cacheKey = await hash(`gemini-tts-v1\ngemini-3.1-flash-tts-preview\nKore\nRead this in a calm, relaxed, low-key voice with a natural Emirati Gulf accent. Measured pace, gentle and composed, not cheerful, not excited, no smile in the voice:\nمرحبا`);
  assert.ok(values.has(cacheKey));
  assert.equal(values.get(allowanceKey), String(text.length));
  const cached = await speak(env, text);
  assert.equal(cached.headers.get('X-Ghaf-Cache'), 'hit');
  assert.equal(calls.length, 1);
});

test('English Hamad uses approved EN style and Orus without changing the text', async t => {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (_url, init) => {
    calls.push(JSON.parse(init.body));
    return Response.json({ candidates: [{ content: { parts: [{ inlineData: { data: 'AQI=' } }] } }] });
  });
  const { env } = setup();
  const response = await speak(env, "Hi, I'm Hahmad, your financial voice assistant.", 'Hamad', 'en');
  assert.equal(response.status, 200);
  assert.equal(calls[0].contents[0].parts[0].text,
    "Read this in a calm, relaxed, low-key voice. Measured pace, soft and composed, not cheerful, not excited:\nPronounce “Hamad” as “HAH-mad,” with a clear Arabic H and stress on the first syllable, matching حمد.\n\nHi, I'm Hahmad, your financial voice assistant.");
  assert.equal(calls[0].generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName, 'Orus');
});

test('live TTS chunks rely on existing voice-turn reservation while standard speech still reserves', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ candidates: [{ content: { parts: [{ inlineData: { data: 'AQI=' } }] } }] }));
  const live = setup();
  assert.equal((await speak(live.env, 'hello there from Ghaf.', 'Hamad', 'en', true)).status, 200);
  assert.equal(live.values.get(`v:pro_monthly:${day}:${device}`), undefined);
  assert.equal(live.values.get(`s:${day}:${device}`), '1');

  const standard = setup();
  assert.equal((await speak(standard.env, 'hello there from Ghaf.', 'Hamad', 'en')).status, 200);
  assert.equal(standard.values.get(`v:pro_monthly:${day}:${device}`), '1');
});

test('new Gemini failure is voice_off and never returns a stand-in', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response('provider detail', { status: 503 }));
  const { env } = setup();
  const response = await speak(env, 'hello', 'Hamad', 'en');
  assert.equal(response.status, 410);
  assert.equal((await response.json()).error, 'voice_off');
});

test('monthly allowance and daily speak limit remain enforced', async t => {
  const blockedFetch = t.mock.method(globalThis, 'fetch', async () => Response.json({ candidates: [{ content: { parts: [{ inlineData: { data: 'AQI=' } }] } }] }));
  const monthly = setup({ [allowanceKey]: '14999' });
  const overMonthly = await speak(monthly.env, 'hello');
  assert.equal(overMonthly.status, 429);
  assert.equal((await overMonthly.json()).scope, 'voice_month');
  assert.equal(blockedFetch.mock.callCount(), 0);

  const dailyKey = `s:${day}:${device}`;
  const daily = setup({ [dailyKey]: '10' });
  daily.env.SPEAK_DAILY_LIMIT = 10;
  const overDaily = await speak(daily.env, 'hello');
  assert.equal(overDaily.status, 429);
  assert.equal((await overDaily.json()).scope, 'speak_device');
});

test('the ElevenLabs studio is developer-only: a user request never reaches it', async t => {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async url => { calls.push(String(url)); return new Response(new Uint8Array(480)); });
  const { env } = setup();
  const response = await worker.fetch(new Request('https://worker.test/speak', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'pro_monthly' },
    body: JSON.stringify({ text: 'hi', character: 'Hamad', tier: 'pro_monthly', studio: 'eleven', voice: 'abcdefghijklmnopqrst' }) }), env);
  assert.notEqual(response.headers.get('X-Ghaf-Voice'), 'eleven-studio');
  const music = await worker.fetch(new Request('https://worker.test/speak', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'pro_monthly' },
    body: JSON.stringify({ text: 'calm piano', tier: 'pro_monthly', studio: 'eleven-music' }) }), env);
  assert.notEqual(music.headers.get('X-Ghaf-Voice'), 'eleven-music');
  assert.ok(calls.every(url => !url.includes('/v1/music') && !url.includes('sound-generation')));
  const design = await worker.fetch(new Request('https://worker.test/speak', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'pro_monthly' },
    body: JSON.stringify({ text: 'x', tier: 'pro_monthly', studio: 'eleven-api', path: '/v1/text-to-voice/design' }) }), env);
  assert.ok(calls.every(url => !url.includes('text-to-voice')));
  assert.ok(calls.every(url => !url.includes('abcdefghijklmnopqrst')));
});
