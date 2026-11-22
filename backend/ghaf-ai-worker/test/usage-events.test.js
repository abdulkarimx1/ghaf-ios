import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.js';

const device = '12345678-1234-1234-1234-123456789abc';
const prompt = 'PRIVATE_PROMPT_usage_event_test';
function setup(initial = {}) {
  const values = new Map(Object.entries(initial)), points = [], pending = [];
  const env = { GEMINI_API_KEY: 'test-key', AI_HASH_SALT: 'usage-test-salt', GEMINI_MODEL: 'gemini-3.5-flash-lite', REASONING_MODEL: 'gemini-3.8-flash', LIVE_MODEL: 'models/gemini-3.8-live', TTS_MODEL: 'gemini-3.1-flash-tts-preview',
    USAGE: { get: async (key, type) => values.get(key) ?? null, put: async (key, value) => values.set(key, value) },
    USAGE_EVENTS: { writeDataPoint: point => points.push(point) } };
  return { env, ctx: { waitUntil: promise => pending.push(promise) }, points, pending, values };
}
function request(path, body, headers = { 'X-Ghaf-Device': device }) {
  return new Request(`https://worker.test${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
}
async function invoke(path, body, state) {
  const response = await worker.fetch(request(path, body), state.env, state.ctx);
  await Promise.all(state.pending.splice(0));
  return response;
}
function assertShape(point, endpoint) {
  assert.deepEqual(point.indexes, ['ghaf']);
  assert.equal(point.blobs.length, 6);
  assert.equal(point.blobs[0], endpoint);
  assert.equal(point.doubles.length, 4);
  assert.ok(point.doubles.every(Number.isFinite));
}

test('chat error emits one anonymous event with no prompt or raw device', async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async () => new Response('{"error":{"message":"provider error"}}', { status: 400 });
  const state = setup();
  const response = await invoke('/chat', { question: prompt }, state);
  assert.equal(response.status, 502);
  assert.equal(state.points.length, 1);
  assertShape(state.points[0], 'chat');
  assert.equal(state.points[0].blobs[2], 'error');
  assert.equal(state.points[0].blobs[3], 'en');
  assert.equal(state.points[0].blobs[5], 'upstream_4xx');
  assert.match(state.points[0].blobs[4], /^[0-9a-f]{16}$/);
  assert.deepEqual(state.points[0].doubles.slice(1), [0, 0, 0]);
  assert.equal(JSON.stringify(state.points).includes(prompt), false);
  assert.equal(JSON.stringify(state.points).includes(device), false);
});

test('limited request logs once and missing analytics binding does not change response', async () => {
  const date = new Date().toISOString().slice(0, 10);
  const key = `d:free:${date}:${device}`;
  const state = setup({ [key]: '20' });
  const response = await invoke('/chat', { question: prompt }, state);
  assert.equal(response.status, 429);
  assert.equal(state.points.length, 1);
  assertShape(state.points[0], 'chat');
  assert.equal(state.points[0].blobs[2], 'limited_device');
  delete state.env.USAGE_EVENTS;
  assert.equal((await worker.fetch(request('/chat', { question: prompt }), state.env, state.ctx)).status, 429);
});

test('live-token and speak write their own endpoint and actual model', async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  let tokenRequest;
  globalThis.fetch = async (url, options) => String(url).includes('auth_tokens')
    ? (tokenRequest = JSON.parse(options.body), Response.json({ name: 'authTokens/test' }))
    : Response.json({ candidates: [{ content: { parts: [{ inlineData: { data: 'AQI=' } }] } }], usageMetadata: { promptTokenCount: 12, candidatesTokenCount: 4 } });
  const state = setup();
  const live = await invoke('/live-token', { language: 'ar', tier: 'free' }, state);
  assert.equal(live.status, 200);
  assert.equal(state.points.length, 1);
  assertShape(state.points[0], 'live-token');
  assert.equal(state.points[0].blobs[1], 'models/gemini-3.8-live');
  assert.equal(state.points[0].blobs[2], 'ok');
  assert.equal(state.points[0].blobs[3], 'ar');
  assert.equal(tokenRequest.fieldMask, 'model,generationConfig.responseModalities,sessionResumption');
  assert.equal(tokenRequest.bidiGenerateContentSetup.lockAdditionalFields, undefined);

  const speak = await invoke('/speak', { text: 'hello voice', language: 'en', tier: 'free' }, state);
  assert.equal(speak.status, 200);
  assert.equal(state.points.length, 2);
  assertShape(state.points[1], 'speak');
  assert.equal(state.points[1].blobs[1], 'gemini-3.1-flash-tts-preview');
  assert.equal(state.points[1].blobs[2], 'ok');
  assert.deepEqual(state.points[1].doubles.slice(1), [12, 4, 0]);
});

test('health, tips and unmatched routes use fixed endpoint labels', async () => {
  const state = setup();
  assert.equal((await worker.fetch(new Request('https://worker.test/health'), state.env, state.ctx)).status, 200);
  assert.equal((await worker.fetch(new Request('https://worker.test/tips'), state.env, state.ctx)).status, 200);
  assert.equal((await worker.fetch(new Request('https://worker.test/private-prompt-in-path'), state.env, state.ctx)).status, 404);
  await Promise.all(state.pending);
  assert.deepEqual(state.points.map(point => point.blobs[0]), ['health', 'tips', 'other']);
  assert.deepEqual(state.points.map(point => point.blobs[2]), ['ok', 'ok', 'error']);
  assert.equal(JSON.stringify(state.points).includes('private-prompt-in-path'), false);
});

test('live-token refuses a session once the day\'s voice turns are used', async () => {
  const state = setup();
  const day = new Date().toISOString().slice(0, 10);
  await state.env.USAGE.put(`v:free:${day}:${device}`, '15');
  const live = await invoke('/live-token', { language: 'en', tier: 'free' }, state);
  assert.equal(live.status, 429);
});
