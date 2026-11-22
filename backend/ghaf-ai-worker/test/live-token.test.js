import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.js';

const device = '12345678-1234-1234-1234-123456789abc';
function environment(initial = {}) {
  const values = new Map(Object.entries(initial));
  return { GEMINI_API_KEY: 'test-key', LIVE_DAILY_CALLS: '1', LIVE_GLOBAL_DAILY_CALLS: '300',
    USAGE: { get: async key => values.get(key) ?? null,
      put: async (key, value) => values.set(key, value) }, values };
}
function request(headers = {}, body = { language: 'ar' }) {
  return new Request('https://worker.test/live-token', { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
}

test('live token authorization, quota, response and upstream privacy', async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const env = environment();
  const denied = await worker.fetch(request(), env);
  assert.equal(denied.status, 401);

  globalThis.fetch = async () => Response.json({ name: 'authTokens/test' });
  const key = `v:free:${new Date().toISOString().slice(0, 10)}:${device}`;
  env.values.set(key, '14'); // A session needs a turn left; opening one does not consume a turn.
  const success = await worker.fetch(request({ 'X-Ghaf-Device': device }), env);
  const payload = await success.json();
  assert.equal(success.status, 200);
  assert.equal(payload.token, 'authTokens/test');
  assert.equal(payload.voice, 'Orus');
  assert.equal(payload.model, 'models/gemini-3.8-live');
  assert.equal(env.values.get(key), '14');

  const mariam = await worker.fetch(request({ 'X-Ghaf-Device': device }, { language: 'en', character: 'Mariam', tier: 'free' }), env);
  assert.equal((await mariam.json()).voice, 'Kore');

  env.values.clear();
  globalThis.fetch = async () => new Response('secret upstream body', { status: 500 });
  const failure = await worker.fetch(request({ 'X-Ghaf-Device': device }), env);
  assert.equal(failure.status, 502);
  assert.deepEqual(await failure.json(), {
    error: 'upstream', used: 0, limit: 15,
    resetsAt: new Date(Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), new Date().getUTCDate() + 1)).toISOString()
  });
});
