import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.js';

test('live usage does not consume the chat global quota', async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const values = new Map([[`g:live:${new Date().toISOString().slice(0, 10)}`, '1000']]);
  const env = { GEMINI_API_KEY: 'test', USAGE: {
    get: async key => values.get(key) ?? null,
    put: async (key, value) => values.set(key, value)
  } };
  globalThis.fetch = async () => Response.json({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] });
  const response = await worker.fetch(new Request('https://worker.test/chat', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': '12345678-1234-1234-1234-123456789abc' },
    body: JSON.stringify({ question: 'hello', tier: 'pro_monthly' })
  }), env);
  assert.equal(response.status, 200);
  assert.equal(values.get(`g:chat:${new Date().toISOString().slice(0, 10)}`), '1');
});

test('chat upstream failure does not expose provider detail', async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const env = { GEMINI_API_KEY: 'test', USAGE: { get: async () => null, put: async () => {} } };
  globalThis.fetch = async () => new Response(JSON.stringify({ error: { message: 'private provider detail' } }), { status: 500 });
  const response = await worker.fetch(new Request('https://worker.test/chat', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': '12345678-1234-1234-1234-123456789abc' },
    body: JSON.stringify({ question: 'hello', tier: 'pro_monthly' })
  }), env);
  assert.equal(response.status, 502);
  const body = await response.json();
  assert.equal(body.error, 'upstream');
  assert.equal(body.used, 0);
  assert.equal(body.limit, 60);
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
