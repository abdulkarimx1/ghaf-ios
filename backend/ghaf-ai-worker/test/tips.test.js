import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.js';

test('GET /tips returns a curated bilingual list with citations', async () => {
  const response = await worker.fetch(new Request('https://worker.test/tips'), {});
  assert.equal(response.status, 200);
  const { version, tips } = await response.json();
  assert.equal(version, 1);
  assert.equal(tips.length, 30);
  for (const tip of tips) {
    assert.ok(tip.en && tip.ar && tip.source);
    assert.equal(new URL(tip.url).protocol, 'https:');
  }
});
