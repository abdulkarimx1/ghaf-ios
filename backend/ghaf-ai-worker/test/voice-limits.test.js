import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.js';

const device = '12345678-1234-1234-1234-123456789abc';

function harness(initial = []) {
  const values = new Map(initial);
  return { values, env: { USAGE: {
    get: async key => values.get(key) ?? null,
    put: async (key, value) => values.set(key, value)
  } } };
}

test('voice usage reports the per-device daily count and UTC reset', async () => {
  const day = new Date().toISOString().slice(0, 10);
  const { env } = harness([[`v:free:${day}:${device}`, '4']]);
  const response = await worker.fetch(new Request('https://worker.test/voice-usage', {
    headers: { 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'free' }
  }), env);
  const result = await response.json();
  assert.equal(response.status, 200);
  assert.deepEqual(Object.keys(result).sort(), ['limit', 'resetsAt', 'used']);
  assert.equal(result.used, 4);
  assert.equal(result.limit, 15);
  assert.equal(new Date(result.resetsAt).toISOString().slice(0, 10), new Date(Date.now() + 86_400_000).toISOString().slice(0, 10));
});

test('voice turn reserves one turn and refuses additional turns at the limit', async () => {
  const day = new Date().toISOString().slice(0, 10);
  const { env, values } = harness([[`v:free:${day}:${device}`, '14']]);
  const makeRequest = () => worker.fetch(new Request('https://worker.test/voice-turn', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device },
    body: JSON.stringify({ tier: 'free', language: 'en' })
  }), env);
  const allowed = await makeRequest();
  assert.equal(allowed.status, 200);
  assert.equal((await allowed.json()).used, 15);
  const limited = await makeRequest();
  assert.equal(limited.status, 429);
  assert.deepEqual(await limited.json(), {
    error: 'daily_limit', used: 15, limit: 15,
    resetsAt: new Date(Date.UTC(Number(day.slice(0, 4)), Number(day.slice(5, 7)) - 1, Number(day.slice(8, 10)) + 1)).toISOString()
  });
  assert.equal(values.get(`v:free:${day}:${device}`), '15');
});

test('voice turns are counted separately from text questions and plan tiers', async () => {
  const day = new Date().toISOString().slice(0, 10);
  const { env, values } = harness();
  const response = await worker.fetch(new Request('https://worker.test/voice-turn', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device },
    body: JSON.stringify({ tier: 'pro_monthly', language: 'ar' })
  }), env);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).limit, 60);
  assert.equal(values.get(`v:pro_monthly:${day}:${device}`), '1');
  assert.equal(values.get(`d:${day}:${device}`), undefined);
});
