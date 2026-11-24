import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { requestRoadRoute, RoadRoutingService } from '../src/road-routing.js';
import { createApp } from '../src/app.js';

const points = [
  { latitude: -23.55, longitude: -46.63 },
  { latitude: -22.90, longitude: -43.17 },
];
const geometry = { type: 'LineString', coordinates: [[-46.63, -23.55], [-45.9, -23.1], [-43.17, -22.90]] };
const geojson = { features: [{ geometry, properties: { summary: { distance: 435800, duration: 19800 } } }] };
const response = (body = geojson) => ({ ok: true, json: async () => body });

test('roads use GeoJSON, longitude first, and the key only in the authorization header', async () => {
  let sent;
  const route = await requestRoadRoute(points, { apiKey: 'private-test-key', fetchImpl: async (url, options) => {
    sent = { url, options };
    return response();
  } });
  assert.equal(new URL(sent.url).search, '');
  assert.equal(sent.options.headers.Authorization, 'private-test-key');
  assert.deepEqual(JSON.parse(sent.options.body).coordinates, [[-46.63, -23.55], [-43.17, -22.90]]);
  assert.equal(JSON.parse(sent.options.body).instructions, false);
  assert.deepEqual(route.geometry, geometry);
  assert.equal(route.distance_km, 435.8);
  assert.equal(route.duration_seconds, 19800);
  assert.ok(!JSON.stringify(route).includes('private-test-key'));
});

test('the same provider preserves the legacy multi-hub distance contract', async () => {
  const route = await requestRoadRoute([...points, ...points], {
    apiKey: 'test', fetchImpl: async () => response({ features: [{ geometry,
      properties: { segments: [{ distance: 1000, duration: 60 }, { distance: 2000, duration: 120 }] } }] }),
  });
  assert.equal(route.distance_km, 3);
  assert.equal(route.duration_seconds, 180);
});

test('missing key, invalid coordinates, failed responses and timeouts do not invent a road', async () => {
  assert.equal((await requestRoadRoute(points, { apiKey: '' })).error, 'OPENROUTE_KEY_MISSING');
  assert.equal((await requestRoadRoute([{ latitude: 100, longitude: 0 }, points[1]], { apiKey: 'x' })).error, 'INVALID_ROUTE_COORDINATES');
  for (const status of [401, 404, 429, 500]) {
    const result = await requestRoadRoute(points, { apiKey: 'x', fetchImpl: async () => ({ ok: false, status }) });
    assert.ok(result.error);
    assert.equal(result.geometry, undefined);
  }
  for (const badGeometry of [null, { type: 'Point', coordinates: [1, 2] }, { type: 'LineString', coordinates: [[0, 0], [200, 95]] }]) {
    const route = await requestRoadRoute(points, { apiKey: 'x', fetchImpl: async () => response({ features: [{ geometry: badGeometry }] }) });
    assert.equal(route.error, 'OPENROUTE_NO_ROUTE');
  }
  const failed = await requestRoadRoute(points, { apiKey: 'secret', fetchImpl: async () => { throw Error('secret in a network exception'); } });
  assert.ok(!JSON.stringify(failed).includes('secret'));
  const timedOut = await requestRoadRoute(points, { apiKey: 'x', fetchImpl: async () => { throw new DOMException('timeout', 'TimeoutError'); } });
  assert.equal(timedOut.error, 'OPENROUTE_TIMEOUT');
});

test('cache coalesces simultaneous requests, expires and evicts the oldest entry', async () => {
  let calls = 0, now = 0;
  const service = new RoadRoutingService({ apiKey: 'test', ttlMs: 100, maxEntries: 1, now: () => now,
    fetchImpl: async () => { calls++; return response(); } });
  await Promise.all([service.route(points), service.route(points)]);
  await service.route(points);
  assert.equal(calls, 1);
  now = 101;
  await service.route(points);
  assert.equal(calls, 2);
  await service.route([points[1], points[0]]);
  await service.route(points);
  assert.equal(calls, 4);
  assert.equal(service.cache.size, 1);
});

test('a failed provider response is retried instead of being cached', async () => {
  let calls = 0;
  const service = new RoadRoutingService({ apiKey: 'test', fetchImpl: async () => {
    calls++;
    return calls === 1 ? { ok: false, status: 429 } : response();
  } });
  assert.ok((await service.route(points)).error);
  assert.equal((await service.route(points)).distance_km, 435.8);
  assert.equal(calls, 2);
});

test('map road endpoint validates input and works independently of ML and registered hubs', async (t) => {
  let calls = 0;
  const service = new RoadRoutingService({ apiKey: 'test', fetchImpl: async () => { calls++; return response(); } });
  const app = await createApp({ mlUrl: 'http://127.0.0.1:1', roadRouting: service });
  const server = createServer(app).listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}/api/v1/map/route`;
  const request = (body) => fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  assert.equal((await fetch(url, { method: 'POST', body: 'invalid' })).status, 415);
  for (const origin of [null, {}, { latitude: '12', longitude: 0 }, { latitude: 0, longitude: 181 }]) {
    assert.equal((await request({ origin, destination: points[1] })).status, 422);
  }
  assert.equal(calls, 0);
  const result = await request({ origin: points[0], destination: points[1] });
  assert.equal(result.status, 200);
  const body = await result.json();
  assert.deepEqual(body.data.geometry, geometry);
  assert.equal(body.data.source, 'openrouteservice');
  await request({ origin: points[0], destination: points[1] });
  assert.equal(calls, 1);
});
