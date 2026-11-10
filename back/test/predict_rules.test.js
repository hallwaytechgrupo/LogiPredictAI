import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';
import { classifyRisk, validateRiskReference } from '../src/risk.js';

const reference = JSON.parse(await readFile(new URL('../src/data/predict-reference.json', import.meta.url), 'utf8'));
const validInput = { total_weight_g: 500, distance_km: 100, remaining_days: 5 };

async function serve(t, options) {
  const app = await createApp(options);
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(() => new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve())));
  return `http://127.0.0.1:${server.address().port}`;
}

async function post(baseUrl, input) {
  return fetch(`${baseUrl}/predict`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });
}

test('POST /predict uses the real reference across all weight/distance bands and percentile boundaries', async (t) => {
  const baseUrl = await serve(t, { mlUrl: 'http://127.0.0.1:1' });
  validateRiskReference(reference);
  assert.equal(reference.groups.reduce((sum, group) => sum + group.sample_size, 0), reference.global.sample_size);
  assert.equal(Object.keys(reference.source_files_sha256).length, 6);
  assert.ok(reference.period.delivery_max < reference.observed_before);
  for (const group of reference.groups) {
    const scenarios = [
      { days: group.transit_days_p50 - 1, risk: 'Alto' },
      { days: group.transit_days_p50, risk: group.transit_days_p50 < group.transit_days_p90 ? 'Médio' : 'Baixo' },
      { days: group.transit_days_p90, risk: 'Baixo' },
    ];
    for (const scenario of scenarios) {
      const response = await post(baseUrl, {
        total_weight_g: (group.weight_g_min + group.weight_g_max) / 2,
        distance_km: (group.distance_km_min + group.distance_km_max) / 2,
        remaining_days: scenario.days,
      });
      assert.equal(response.status, 200);
      const result = await response.json();
      assert.equal(result.risk, scenario.risk);
      assert.equal(result.method, 'historical_rules');
      assert.equal(result.synthetic, false);
      assert.equal(result.rules_version, reference.rules_version);
      assert.equal(result.reference.sample_size, group.sample_size);
      assert.equal(result.reference.level, 'distance_weight');
    }
  }
  const sameDay = await post(baseUrl, { ...validInput, remaining_days: 0 });
  assert.equal(sameDay.status, 200);
  assert.equal((await sameDay.json()).risk, 'Alto');
});

test('POST /predict rejects invalid types, missing fields, unknown fields and invalid numbers', async (t) => {
  const baseUrl = await serve(t);
  const invalid = [
    {}, [],
    { ...validInput, total_weight_g: 0 },
    { ...validInput, total_weight_g: -1 },
    { ...validInput, total_weight_g: null },
    { ...validInput, total_weight_g: '500' },
    { ...validInput, distance_km: true },
    { ...validInput, distance_km: -1 },
    { ...validInput, distance_km: 20051 },
    { ...validInput, remaining_days: -1 },
    { ...validInput, remaining_days: 1.5 },
    { ...validInput, remaining_days: '5' },
    { ...validInput, delivered_at: '2018-01-01' },
  ];
  for (const input of invalid) {
    const response = await post(baseUrl, input);
    assert.equal(response.status, 422, JSON.stringify(input));
    const result = await response.json();
    assert.equal(result.error, 'VALIDATION_ERROR');
    assert.ok(result.details.length > 0);
  }
  for (const [body, expectedStatus] of [['{', 400], ['{"total_weight_g":1e400,"distance_km":1,"remaining_days":1}', 422]]) {
    const response = await fetch(`${baseUrl}/predict`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body,
    });
    assert.equal(response.status, expectedStatus);
  }
  const media = await fetch(`${baseUrl}/predict`, { method: 'POST', body: JSON.stringify(validInput) });
  assert.equal(media.status, 415);
  const missingBody = await fetch(`${baseUrl}/predict`, { method: 'POST', headers: { 'Content-Type': 'application/json' } });
  assert.equal(missingBody.status, 422);
});

test('band boundaries include the upper value, sparse groups fall back and extrapolation is disclosed', () => {
  const atBoundary = classifyRisk({ total_weight_g: 1000, distance_km: 250, remaining_days: 10 }, reference);
  assert.equal(atBoundary.reference.weight_band, 0);
  assert.equal(atBoundary.reference.distance_band, 0);
  const aboveBoundary = classifyRisk({ total_weight_g: 1001, distance_km: 251, remaining_days: 10 }, reference);
  assert.equal(aboveBoundary.reference.weight_band, 1);
  assert.equal(aboveBoundary.reference.distance_band, 1);

  const sparse = structuredClone(reference);
  sparse.groups = sparse.groups.filter((group) => group.distance_band !== 0 || group.weight_band !== 0);
  const distanceFallback = classifyRisk(validInput, validateRiskReference(sparse));
  assert.equal(distanceFallback.reference.level, 'distance');
  assert.ok(distanceFallback.warnings.some((warning) => warning.includes('Amostra insuficiente')));
  sparse.distance_groups = sparse.distance_groups.filter((group) => group.distance_band !== 0);
  assert.equal(classifyRisk(validInput, validateRiskReference(sparse)).reference.level, 'global');
  const extrapolated = classifyRisk({ ...validInput, total_weight_g: 1e9, distance_km: 20050 }, reference);
  assert.ok(extrapolated.warnings.some((warning) => warning.includes('extrapolado')));
});

test('missing or corrupt reference returns 503, recovers on retry and leaves health available', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-be03-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const filename = path.join(directory, 'reference.json');
  const baseUrl = await serve(t, { predictReferenceFile: filename });
  assert.equal((await post(baseUrl, validInput)).status, 503);
  assert.equal((await fetch(`${baseUrl}/health`)).status, 200);
  await writeFile(filename, '{');
  assert.equal((await post(baseUrl, validInput)).status, 503);
  await writeFile(filename, JSON.stringify({ ...reference, synthetic: true }));
  assert.equal((await post(baseUrl, validInput)).status, 503);
  await writeFile(filename, JSON.stringify(reference));
  assert.equal((await post(baseUrl, validInput)).status, 200);
});

test('new rule endpoint is independent of ML and existing prediction proxy keeps its contract', async (t) => {
  let calls = 0;
  let received;
  const mlResult = { model_version: 'existing-model', delay_probability: 0.42, predicted_late: true, threshold: 0.37 };
  const mlServer = createServer(async (req, res) => {
    calls++;
    let body = '';
    for await (const chunk of req) body += chunk;
    received = JSON.parse(body);
    assert.equal(req.url, '/predict');
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(mlResult));
  }).listen(0, '127.0.0.1');
  await new Promise((resolve) => mlServer.once('listening', resolve));
  t.after(() => new Promise((resolve) => mlServer.close(resolve)));
  const baseUrl = await serve(t, { mlUrl: `http://127.0.0.1:${mlServer.address().port}` });
  const results = await Promise.all(Array.from({ length: 10 }, () => post(baseUrl, validInput)));
  assert.ok(results.every((response) => response.status === 200));
  assert.equal(calls, 0);
  const payload = { purchase_at: '2018-01-01T10:00:00', total_weight_g: 500, existing_field: 'preserved' };
  const existing = await fetch(`${baseUrl}/api/v1/predictions`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
  });
  assert.equal(existing.status, 200);
  assert.deepEqual(await existing.json(), mlResult);
  assert.deepEqual(received, payload);
  assert.equal(calls, 1);
});
