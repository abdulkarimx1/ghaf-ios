import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.js';

const device = '12345678-1234-1234-1234-123456789abc';
const month = new Date().toISOString().slice(0, 7);

function setup(used) {
  const values = new Map(used == null ? [] : [[`vc:pro_monthly:${month}:${device}`, String(used)]]);
  const env = { ELEVENLABS_API_KEY: 'k', ELEVEN_VOICE_HAMAD: 'h', ELEVEN_VOICE_MARIAM: 'm', USAGE: {
    get: async key => values.get(key) ?? null, put: async (key, value) => values.set(key, value) } };
  return { values, env };
}
const speak = (env, text) => worker.fetch(new Request('https://worker.test/speak', {
  method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'pro_monthly' },
  body: JSON.stringify({ text, character: 'Mariam', tier: 'pro_monthly', language: 'ar' }) }), env);

test('ElevenLabs speech is charged to the monthly character allowance', async t => {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, init) => { calls.push([String(url), init]); return new Response(new Uint8Array(480)); });
  const { env, values } = setup(100);
  const response = await speak(env, 'مرحبا');
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('X-Ghaf-Voice'), 'elevenlabs');
  assert.match(calls[0][0], /text-to-speech\/m\?output_format=pcm_24000/);
  assert.equal(values.get(`vc:pro_monthly:${month}:${device}`), '105');
});

test('over the monthly allowance is refused without calling ElevenLabs', async t => {
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => new Response(new Uint8Array(4)));
  const { env } = setup(14999);
  const response = await speak(env, 'hello');
  assert.equal(response.status, 429);
  assert.equal((await response.json()).scope, 'voice_month');
  assert.equal(fetchMock.mock.callCount(), 0);
});
