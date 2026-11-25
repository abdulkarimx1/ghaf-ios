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

test('without ElevenLabs there is no stand-in voice: speak and live-token answer voice_off', async t => {
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => new Response(new Uint8Array(4)));
  const { env } = setup(0);
  delete env.ELEVENLABS_API_KEY; env.GEMINI_API_KEY = 'g';
  const response = await speak(env, 'hello');
  assert.equal(response.status, 410);
  assert.equal((await response.json()).error, 'voice_off');
  const live = await worker.fetch(new Request('https://worker.test/live-token', { method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'pro_monthly' }, body: JSON.stringify({ tier: 'pro_monthly' }) }), env);
  assert.equal(live.status, 410);
  assert.equal(fetchMock.mock.callCount(), 0);
});

test('an unpaid ElevenLabs plan (402) turns speech off instead of failing over', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response('{}', { status: 402 }));
  const { env, values } = setup(0);
  const response = await speak(env, 'hello');
  assert.equal(response.status, 410);
  assert.equal(values.get(`vc:pro_monthly:${month}:${device}`), '0');
});

test('the ElevenLabs studio is developer-only: a user request never reaches it', async t => {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async url => { calls.push(String(url)); return new Response(new Uint8Array(480)); });
  const { env } = setup(0);
  const response = await worker.fetch(new Request('https://worker.test/speak', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Ghaf-Device': device, 'X-Ghaf-Tier': 'pro_monthly' },
    body: JSON.stringify({ text: 'hi', character: 'Hamad', tier: 'pro_monthly', studio: 'eleven', voice: 'abcdefghijklmnopqrst' }) }), env);
  assert.notEqual(response.headers.get('X-Ghaf-Voice'), 'eleven-studio');
  assert.ok(calls.every(url => !url.includes('abcdefghijklmnopqrst')));
});
