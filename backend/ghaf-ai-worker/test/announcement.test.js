import test from "node:test";
import assert from "node:assert/strict";
import worker from "../worker.js";

const now = new Date(Date.now() + 60_000).toISOString();
const announcement = {
  id: "test-1",
  title: { en: "Update", ar: "تحديث" },
  body: { en: "A new version is ready.", ar: "يتوفر إصدار جديد." },
  minVersion: "1.30",
  code: "GHAF30",
  expires: now
};

test("GET /announcement localizes the configured KV value", async () => {
  const env = { USAGE: { get: async key => key === "ghaf:announcement" ? JSON.stringify(announcement) : null } };
  const response = await worker.fetch(new Request("https://ghaf.test/announcement", { headers: { "Accept-Language": "ar" } }), env, {});
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { id: "test-1", title: "تحديث", body: "يتوفر إصدار جديد.", minVersion: "1.30", code: "GHAF30", expires: new Date(now).toISOString() });
});

test("GET /announcement returns 404 for expired or missing values", async () => {
  const missing = await worker.fetch(new Request("https://ghaf.test/announcement"), { USAGE: { get: async () => null } }, {});
  const expired = await worker.fetch(new Request("https://ghaf.test/announcement"), { ANNOUNCEMENT: JSON.stringify({ ...announcement, expires: "2000-01-01T00:00:00Z" }) }, {});
  assert.equal(missing.status, 404);
  assert.equal(expired.status, 404);
});
