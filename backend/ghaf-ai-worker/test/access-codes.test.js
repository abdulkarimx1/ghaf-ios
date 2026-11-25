import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import worker from '../worker.js';

const device = '12345678-1234-1234-1234-123456789abc';
const hash = code => createHash('sha256').update(code).digest('hex');
function harness(hashes = '') {
  const values = new Map();
  return { values, env: { ACCESS_CODE_HASHES: hashes, USAGE: {
    get: async key => values.get(key) ?? null,
    put: async (key, value) => values.set(key, value)
  } } };
}
const makeRequest = (path, code, body = {}) => env => worker.fetch(new Request(`https://worker.test${path}`, {
  method: 'POST', headers: {
    'Content-Type': 'application/json', 'X-Ghaf-Device': device,
    ...(code ? { 'X-Ghaf-Code': code } : {})
  }, body: JSON.stringify(body)
}), env);

test('valid code redeems to Complete tier without echoing the code', async () => {
  const code = 'ghaf-test-code';
  const { env } = harness(hash(code));
  const response = await makeRequest('/redeem', null, { code })(env);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { tier: 'pro_yearly' });
});

test('invalid and revoked codes are rejected without granting the body tier', async () => {
  const { env } = harness(hash('valid-code'));
  const invalid = await makeRequest('/redeem', null, { code: 'wrong-code' })(env);
  assert.equal(invalid.status, 401);
  const revoked = await makeRequest('/voice-turn', 'valid-code', { tier: 'pro_yearly', language: 'en' })(harness('').env);
  assert.equal(revoked.status, 401);
  assert.equal((await revoked.json()).error, 'invalid_access_code');
});

test('redeemed code overrides body tier for AI requests and gets Complete allowance', async () => {
  const code = 'complete-code';
  const { env, values } = harness(hash(code));
  const response = await makeRequest('/voice-turn', code, { tier: 'free', language: 'en' })(env);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).limit, 10);
  assert.equal(values.get(`v:pro_yearly:${new Date().toISOString().slice(0, 10)}:${device}`), '1');
});

test('redemption is limited to five attempts per device per UTC day', async () => {
  const { env, values } = harness(hash('correct'));
  for (let index = 0; index < 5; index++) {
    const response = await makeRequest('/redeem', null, { code: 'wrong' })(env);
    assert.equal(response.status, 401);
  }
  const limited = await makeRequest('/redeem', null, { code: 'correct' })(env);
  assert.equal(limited.status, 429);
  assert.equal((await limited.json()).error, 'rate_limited');
  assert.equal(Number([...values.values()][0]), 5);
});

test('R2: guessing codes through the header is limited like /redeem', async () => {
  const { env } = harness(hash('correct'));
  for (let index = 0; index < 5; index++) {
    const response = await makeRequest('/voice-turn', 'wrong', { tier: 'free', language: 'en' })(env);
    assert.equal(response.status, 401);
  }
  const blocked = await makeRequest('/voice-turn', 'correct', { tier: 'free', language: 'en' })(env);
  assert.equal(blocked.status, 401, 'the right code is not even checked once the device hit the limit');
});
