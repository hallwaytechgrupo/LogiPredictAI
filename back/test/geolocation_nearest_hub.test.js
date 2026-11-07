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

const GEO_SP_BA = geoCsv([
  '1,01001,São Paulo,SP,-23.5505,-46.6333',
  '2,40000,Salvador,BA,-12.9714,-38.5108',
]);

const GEO_SP_ONLY = geoCsv(['1,01001,São Paulo,SP,-23.5505,-46.6333']);
const GEO_SP_TWO = geoCsv([
  '1,01001,São Paulo,SP,-23.5505,-46.6333',
  '2,01002,São Paulo,SP,-23.5600,-46.6400',
]);

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

test('POST /api/v1/geolocation/nearest-hub — Hub mais próximo por CEP', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, HUBS_SP_BA, GEO_SP_BA);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/geolocation/nearest-hub`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ cep: '01001-000' }) });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.data.hub.id, 'hub-sp-001');
    assert.ok(body.data.distance_km >= 0);
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/geolocation/nearest-hub — Hub mais próximo por coordenadas', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, HUBS_SP_BA, GEO_SP_BA);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/geolocation/nearest-hub`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ latitude: -13.0, longitude: -38.5 }) });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.data.hub.id, 'hub-ba-001');
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/geolocation/nearest-hub — CEP inválido retorna 422', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, [], GEO_SP_ONLY);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/geolocation/nearest-hub`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ cep: 'invalid' }) });
    assert.equal(res.status, 422);
    assert.equal((await res.json()).error, 'INVALID_CEP');
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/geolocation/nearest-hub — Sem hubs ativos retorna 503', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, [], GEO_SP_ONLY);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/geolocation/nearest-hub`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ cep: '01001-000' }) });
    assert.equal(res.status, 503);
    assert.equal((await res.json()).error, 'NO_HUBS_AVAILABLE');
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/geolocation/nearest-hub — Sem cep ou coordenadas retorna 422', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, [], GEO_SP_ONLY);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/geolocation/nearest-hub`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) });
    assert.equal(res.status, 422);
    assert.equal((await res.json()).error, 'MISSING_INPUT');
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/geolocation/nearest-hub — Coordenadas inválidas retornam 422', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const files = await setup(tmpDir, [], GEO_SP_ONLY);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/geolocation/nearest-hub`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ latitude: 999, longitude: 999 }) });
    assert.equal(res.status, 422);
    assert.equal((await res.json()).error, 'INVALID_COORDINATES');
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/geolocation/nearest-hub — Hub pendente não é selecionado', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const pendingHubs = [{ id: 'hub-pending-001', code: 'HUB-PENDING', name: 'Hub Pendente', city: 'São Paulo', state: 'SP', latitude: -23.5505, longitude: -46.6333, active: false, validationStatus: 'PENDENTE', osm_id: '999' }];
  const files = await setup(tmpDir, pendingHubs, GEO_SP_ONLY);
  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: files.ordersFile, HUBS_FILE: files.hubsFile, PREDICTIONS_FILE: files.predictionsFile, PREDICTIONS_JOURNAL_FILE: files.predictionsJournalFile, GEOLOCATION_FILE: files.geolocationFile };
  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/geolocation/nearest-hub`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ cep: '01001-000' }) });
    assert.equal(res.status, 503);
    assert.equal((await res.json()).error, 'NO_HUBS_AVAILABLE');
    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});
