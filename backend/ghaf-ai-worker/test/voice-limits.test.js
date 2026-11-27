import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.js';

const device = '12345678-1234-1234-1234-123456789abc';
const codeHash = '293f6bf6ac4a72bdaf109ae879ed4b388d9ea3aa3d43c6842b8e6ec51e27ec1f';

function harness(initial = []) {
  const values = new Map(initial);
  return { values, env: { APP_TOKEN: 'dev-test', ACCESS_CODE_HASHES: codeHash, USAGE: {
    get: async key => values.get(key) ?? null,
    put: async (key, value) => values.set(key, value)
  } } };
}

test('free tier has zero voice replies and reports the UTC reset', async () => {
  const day = new Date().toISOString().slice(0, 10);
  const { env } = harness([[`v:free:${day}:${device}`, '0']]);
  const response = await worker.fetch(new Request('https://worker.test/voice-usage', {
    headers: { 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'free' }
  }), env);
  const result = await response.json();
  assert.equal(response.status, 200);
  assert.deepEqual(Object.keys(result).sort(), ['limit', 'resetsAt', 'used']);
  assert.equal(result.used, 0);
  assert.equal(result.limit, 0);
  assert.equal(new Date(result.resetsAt).toISOString().slice(0, 10), new Date(Date.now() + 86_400_000).toISOString().slice(0, 10));
});

test('free voice turn is refused before recording any usage', async () => {
  const day = new Date().toISOString().slice(0, 10);
  const { env, values } = harness();
  const makeRequest = () => worker.fetch(new Request('https://worker.test/voice-turn', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device },
    body: JSON.stringify({ tier: 'free', language: 'en' })
  }), env);
  const limited = await makeRequest();
  assert.equal(limited.status, 429);
  const payload = await limited.json();
  assert.equal(payload.error, 'pro_required');
  assert.equal(payload.code, 'pro_required');
  assert.equal(payload.limit, 0);
  assert.equal(payload.used, 0);
  assert.equal(values.get(`v:free:${day}:${device}`), undefined);
});

test('voice turns are counted separately from text questions and plan tiers', async () => {
  const day = new Date().toISOString().slice(0, 10);
  const { env, values } = harness();
  const response = await worker.fetch(new Request('https://worker.test/voice-turn', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device, 'X-Ghaf-Code': 'release-test-code' },
    body: JSON.stringify({ tier: 'pro_monthly', language: 'ar' })
  }), env);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).limit, 10);
  assert.equal(values.get(`v:pro_yearly:${day}:${device}`), '1');
  assert.equal(values.get(`d:${day}:${device}`), undefined);
});

test('Essentials and Complete use defaults, env overrides, and a shared per-tier voice counter', async () => {
  const day = new Date().toISOString().slice(0, 10);
  for (const [tier, expected] of [['pro_monthly', 3], ['pro_yearly', 10]]) {
    const { env } = harness();
    const response = await worker.fetch(new Request('https://worker.test/voice-usage', {
      headers: { 'X-Ghaf-Device': device, 'X-Ghaf-Tier': tier, 'X-Ghaf-Token': 'dev-test' }
    }), env);
    assert.equal((await response.json()).limit, expected);
  }

  const { env, values } = harness();
  env.COMPLETE_DAILY_VOICE_LIMIT = '4';
  const response = await worker.fetch(new Request('https://worker.test/voice-turn', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device, 'X-Ghaf-Code': 'release-test-code' },
    body: JSON.stringify({ tier: 'pro_monthly', language: 'en' })
  }), env);
  assert.equal((await response.json()).limit, 4);
  assert.equal(values.get(`v:pro_yearly:${day}:${device}`), '1');
});
