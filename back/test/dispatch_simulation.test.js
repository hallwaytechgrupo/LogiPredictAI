import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

const GEO_HEADER = 'geolocation_id,geolocation_zip_code_prefix,geolocation_city,geolocation_state,geolocation_lat,geolocation_lng';

function geoCsv(rows) {
  return [GEO_HEADER, ...rows].join('\n');
}

const HUBS_SP_BA = [
  { id: 'hub-sp-001', code: 'HUB-SP-001', name: 'Hub São Paulo', city: 'São Paulo', state: 'SP', latitude: -23.5505, longitude: -46.6333, active: true, validationStatus: 'APROVADO', osm_id: '100' },
  { id: 'hub-ba-001', code: 'HUB-BA-001', name: 'Hub Bahia', city: 'Salvador', state: 'BA', latitude: -12.9714, longitude: -38.5108, active: true, validationStatus: 'APROVADO', osm_id: '200' },
];

const HUBS_SP_ONLY = [
  { id: 'hub-sp-001', code: 'HUB-SP-001', name: 'Hub São Paulo', city: 'São Paulo', state: 'SP', latitude: -23.5505, longitude: -46.6333, active: true, validationStatus: 'APROVADO', osm_id: '100' },
];

const GEO_SP_BA = geoCsv([
  '1,01001,São Paulo,SP,-23.5505,-46.6333',
  '2,40000,Salvador,BA,-12.9714,-38.5108',
]);

const GEO_SP_TWO = geoCsv([
  '1,01001,São Paulo,SP,-23.5505,-46.6333',
  '2,01002,São Paulo,SP,-23.5600,-46.6400',
]);

const GEO_SP_ONLY = geoCsv(['1,01001,São Paulo,SP,-23.5505,-46.6333']);

async function setup(dir, hubs, geoContent) {
  const ordersFile = path.join(dir, 'orders.json');
  const hubsFile = path.join(dir, 'hubs.json');
  const predictionsFile = path.join(dir, 'predictions.json');
  const predictionsJournalFile = path.join(dir, 'predictions.jsonl');
  const geolocationFile = path.join(dir, 'geolocation.csv');
  await writeFile(hubsFile, JSON.stringify(hubs, null, 2));
  await writeFile(ordersFile, '[]');
  await writeFile(predictionsFile, '[]');
  await writeFile(geolocationFile, geoContent);
  return { ordersFile, hubsFile, predictionsFile, predictionsJournalFile, geolocationFile };
}

test('POST /api/v1/dispatch/simulate — Simulação básica com dois CEPs', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, HUBS_SP_BA, GEO_SP_BA);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/dispatch/simulate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ origin_cep: '01001-000', destination_cep: '40000-000' }) });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.data.origin.cep, '01001000');
    assert.equal(body.data.destination.cep, '40000000');
    assert.ok(body.data.origin_hub);
    assert.ok(body.data.destination_hub);
    assert.ok(body.data.distances.hub_to_hub_haversine_km > 0);
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/dispatch/simulate — Hubs selecionados corretamente', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, HUBS_SP_BA, GEO_SP_BA);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/dispatch/simulate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ origin_cep: '01001-000', destination_cep: '40000-000' }) });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.data.origin_hub.id, 'hub-sp-001');
    assert.equal(body.data.destination_hub.id, 'hub-ba-001');
    assert.equal(body.data.same_hub, false);
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/dispatch/simulate — Mesmo hub para origem e destino', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, HUBS_SP_ONLY, GEO_SP_TWO);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/dispatch/simulate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ origin_cep: '01001-000', destination_cep: '01002-000' }) });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.data.same_hub, true);
    assert.equal(body.data.origin_hub.id, body.data.destination_hub.id);
    assert.ok(body.data.warnings.length > 0);
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/dispatch/simulate — CEP de origem inválido retorna 422', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, [], GEO_SP_ONLY);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/dispatch/simulate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ origin_cep: 'invalid', destination_cep: '40000-000' }) });
    assert.equal(res.status, 422);
    assert.equal((await res.json()).error, 'INVALID_ORIGIN_CEP');
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/dispatch/simulate — CEP de destino inválido retorna 422', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, [], GEO_SP_ONLY);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/dispatch/simulate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ origin_cep: '01001-000', destination_cep: 'invalid' }) });
    assert.equal(res.status, 422);
    assert.equal((await res.json()).error, 'INVALID_DESTINATION_CEP');
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/dispatch/simulate — Sem hubs ativos retorna 503', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, [], GEO_SP_BA);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/dispatch/simulate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ origin_cep: '01001-000', destination_cep: '40000-000' }) });
    assert.equal(res.status, 503);
    assert.equal((await res.json()).error, 'NO_HUBS_AVAILABLE');
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/dispatch/simulate — CEP não encontrado retorna 404', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, HUBS_SP_ONLY, GEO_SP_ONLY);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/dispatch/simulate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ origin_cep: '01001-000', destination_cep: '99999-999' }) });
    assert.equal(res.status, 404);
    assert.equal((await res.json()).error, 'DESTINATION_CEP_NOT_FOUND');
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/dispatch/simulate — OpenRouteService indisponível retorna aviso', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, HUBS_SP_BA, GEO_SP_BA);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  delete process.env.OPENROUTE_API_KEY;
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/dispatch/simulate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ origin_cep: '01001-000', destination_cep: '40000-000' }) });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok(body.data.distances.hub_to_hub_haversine_km > 0);
    assert.ok(body.data.warnings.length > 0);
    assert.equal(body.data.route, null);
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/dispatch/simulate — Distâncias SP-BA corretas', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, HUBS_SP_BA, GEO_SP_BA);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/dispatch/simulate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ origin_cep: '01001-000', destination_cep: '40000-000' }) });
    assert.equal(res.status, 200);
    const body = await res.json();
    const dist = body.data.distances;
    assert.ok(typeof dist.origin_to_origin_hub_km === 'number');
    assert.ok(typeof dist.destination_to_dest_hub_km === 'number');
    assert.ok(dist.hub_to_hub_haversine_km > 1000);
    assert.ok(dist.hub_to_hub_haversine_km < 2000);
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});
