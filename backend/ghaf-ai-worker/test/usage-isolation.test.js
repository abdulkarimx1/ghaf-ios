import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.js';

const device = '12345678-1234-1234-1234-123456789abc';
const accessCodeHash = '293f6bf6ac4a72bdaf109ae879ed4b388d9ea3aa3d43c6842b8e6ec51e27ec1f';

test('live usage does not consume the chat global quota', async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const values = new Map([[`g:live:${new Date().toISOString().slice(0, 10)}`, '1000']]);
  const env = { ACCESS_CODE_HASHES: accessCodeHash, GEMINI_API_KEY: 'test', USAGE: {
    get: async key => values.get(key) ?? null,
    put: async (key, value) => values.set(key, value)
  } };
  globalThis.fetch = async () => Response.json({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] });
  const response = await worker.fetch(new Request('https://worker.test/chat', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': '12345678-1234-1234-1234-123456789abc', 'X-Ghaf-Code': 'release-test-code' },
    body: JSON.stringify({ question: 'hello', tier: 'pro_monthly' })
  }), env);
  assert.equal(response.status, 200);
  assert.equal(values.get(`g:chat:${new Date().toISOString().slice(0, 10)}`), '1');
});

test('chat upstream failure does not expose provider detail', async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const env = { ACCESS_CODE_HASHES: accessCodeHash, GEMINI_API_KEY: 'test', USAGE: { get: async () => null, put: async () => {} } };
  globalThis.fetch = async () => new Response(JSON.stringify({ error: { message: 'private provider detail' } }), { status: 500 });
  const response = await worker.fetch(new Request('https://worker.test/chat', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': '12345678-1234-1234-1234-123456789abc', 'X-Ghaf-Code': 'release-test-code' },
    body: JSON.stringify({ question: 'hello', tier: 'pro_monthly' })
  }), env);
  assert.equal(response.status, 502);
  const body = await response.json();
  assert.equal(body.error, 'upstream');
  assert.equal(body.used, 0);
  assert.equal(body.limit, 200);
  assert.equal(typeof body.resetsAt, 'string');
});

test('free chat, speech, voice-turn and Live token requests return a clear Pro-only 429', async () => {
  const device = '12345678-1234-1234-1234-123456789abc';
  const env = { USAGE: { get: async () => null, put: async () => {} } };
  for (const [path, body] of [
    ['/chat', { question: 'How much did I spend?' }],
    ['/speak', { text: 'Hello', language: 'en' }],
    ['/voice-turn', { language: 'en' }],
    ['/live-token', { language: 'en', character: 'Hamad' }]
  ]) {
    const response = await worker.fetch(new Request(`https://worker.test${path}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device },
      body: JSON.stringify({ ...body, tier: 'free' })
    }), env);
    assert.equal(response.status, 429, path);
    const payload = await response.json();
    assert.equal(payload.error, 'pro_required', path);
    assert.equal(payload.code, 'pro_required', path);
  }
});

test('client tier claims cannot unlock Pro routes or usage, while a valid access code can', async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const code = 'release-test-code';
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(code));
  const codeHash = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
  const values = new Map();
  const env = {
    ACCESS_CODE_HASHES: codeHash, LIVE_CALLS_ENABLED: '1', GEMINI_API_KEY: 'test', APP_TOKEN: 'dev-test',
    USAGE: { get: async key => values.get(key) ?? null, put: async (key, value) => values.set(key, value) }
  };
  globalThis.fetch = async url => String(url).includes('auth_tokens')
    ? Response.json({ name: 'authTokens/test' })
    : Response.json({ candidates: [{ content: { parts: [{ text: 'ok', inlineData: { data: 'AQI=' } }] } }] });

  for (const [path, body] of [
    ['/chat', { question: 'hello', tier: 'pro_yearly' }],
    ['/speak', { text: 'hello', language: 'en', tier: 'pro_yearly' }],
    ['/live-token', { language: 'en', tier: 'pro_yearly' }],
    ['/voice-turn', { language: 'en', tier: 'pro_yearly' }]
  ]) {
    const response = await worker.fetch(new Request(`https://worker.test${path}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device }, body: JSON.stringify(body)
    }), env);
    assert.equal(response.status, 429, path);
    assert.equal((await response.json()).error, 'pro_required', path);
  }

  const usage = await worker.fetch(new Request('https://worker.test/voice-usage', {
    headers: { 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'pro_yearly' }
  }), env);
  assert.equal((await usage.json()).limit, 0);

  for (const [path, body] of [
    ['/chat', { question: 'hello', tier: 'free' }],
    ['/speak', { text: 'hello', language: 'en', tier: 'free' }],
    ['/live-token', { language: 'en', tier: 'free' }],
    ['/voice-turn', { language: 'en', tier: 'free' }]
  ]) {
    const response = await worker.fetch(new Request(`https://worker.test${path}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device, 'X-Ghaf-Code': code }, body: JSON.stringify(body)
    }), env);
    const payload = response.status === 200 ? {} : await response.json();
    assert.notEqual(payload.error, 'pro_required', path);
    assert.notEqual(response.status, 401, path);
  }

  const codeUsage = await worker.fetch(new Request('https://worker.test/voice-usage', {
    headers: { 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'free', 'X-Ghaf-Code': code }
  }), env);
  assert.equal((await codeUsage.json()).limit, 10);

  const developer = await worker.fetch(new Request('https://worker.test/voice-usage', {
    headers: { 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'pro_monthly', 'X-Ghaf-Token': 'dev-test' }
  }), env);
  assert.equal((await developer.json()).limit, 3);
});
