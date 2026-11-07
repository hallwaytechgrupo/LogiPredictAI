import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

test('cleanup: dry-run shows orders and predictions to remove', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-cleanup-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'olist-001', hub_id: null, source: 'olist', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
    { order_id: 'olist-002', hub_id: null, source: 'olist', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
    { order_id: 'manual-001', hub_id: null, createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));
  await writeFile(predictionsFile, '[]');
  await writeFile(journalFile, [
    JSON.stringify({ prediction_id: 'p1', order_id: 'olist-001', hub_id: null, delay_probability: 0.5, predicted_late: true, threshold: 0.37, model_version: 'v1', source: 'ml', warnings: [], predicted_at: '2025-01-01T00:00:00.000Z' }),
    JSON.stringify({ prediction_id: 'p2', order_id: 'olist-002', hub_id: null, delay_probability: 0.2, predicted_late: false, threshold: 0.37, model_version: 'v1', source: 'ml', warnings: [], predicted_at: '2025-01-01T00:00:00.000Z' }),
    JSON.stringify({ prediction_id: 'p3', order_id: 'manual-001', hub_id: null, delay_probability: 0.8, predicted_late: true, threshold: 0.37, model_version: 'v1', source: 'ml', warnings: [], predicted_at: '2025-01-01T00:00:00.000Z' }),
  ].join('\n') + '\n');

  const app = await createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/cleanup`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ source: 'olist', dry_run: true }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.dry_run, true);
  assert.equal(body.summary.source, 'olist');
  assert.equal(body.summary.orders_to_remove, 2);
  assert.equal(body.summary.total_orders, 3);
  assert.equal(body.summary.orders_preserved, 1);
  assert.equal(body.summary.predictions_to_remove, 2);
  assert.equal(body.summary.total_predictions, 3);
  assert.equal(body.summary.predictions_preserved, 1);

  // Verify data is NOT modified
  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.length, 3);
});

test('cleanup: requires confirmation to execute', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-cleanup-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'olist-001', hub_id: null, source: 'olist', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));
  await writeFile(predictionsFile, '[]');
  await writeFile(journalFile, '');

  const app = await createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  // Without confirm, should reject
  const res = await fetch(`${baseUrl}/api/v1/orders/cleanup`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ source: 'olist' }),
  });
  assert.equal(res.status, 422);
  const body = await res.json();
  assert.equal(body.error, 'CONFIRMATION_REQUIRED');
});

test('cleanup: executes cleanup with confirmation', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-cleanup-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'olist-001', hub_id: null, source: 'olist', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
    { order_id: 'olist-002', hub_id: null, source: 'olist', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
    { order_id: 'manual-001', hub_id: null, createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));
  await writeFile(predictionsFile, '[]');
  await writeFile(journalFile, [
    JSON.stringify({ prediction_id: 'p1', order_id: 'olist-001', hub_id: null, delay_probability: 0.5, predicted_late: true, threshold: 0.37, model_version: 'v1', source: 'ml', warnings: [], predicted_at: '2025-01-01T00:00:00.000Z' }),
    JSON.stringify({ prediction_id: 'p2', order_id: 'olist-002', hub_id: null, delay_probability: 0.2, predicted_late: false, threshold: 0.37, model_version: 'v1', source: 'ml', warnings: [], predicted_at: '2025-01-01T00:00:00.000Z' }),
    JSON.stringify({ prediction_id: 'p3', order_id: 'manual-001', hub_id: null, delay_probability: 0.8, predicted_late: true, threshold: 0.37, model_version: 'v1', source: 'ml', warnings: [], predicted_at: '2025-01-01T00:00:00.000Z' }),
  ].join('\n') + '\n');

  const app = await createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/cleanup`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ source: 'olist', confirm: true }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.dry_run, false);
  assert.equal(body.summary.orders_to_remove, 2);
  assert.equal(body.summary.predictions_to_remove, 2);

  // Verify orders.json only has manual-001
  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.length, 1);
  assert.equal(stored[0].order_id, 'manual-001');

  // Verify journal only has prediction for manual-001
  const journal = await readFile(journalFile, 'utf8');
  const lines = journal.split('\n').filter((l) => l.trim());
  assert.equal(lines.length, 1);
  const pred = JSON.parse(lines[0]);
  assert.equal(pred.order_id, 'manual-001');
});

test('cleanup: rejects missing source', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-cleanup-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, '[]');

  const app = await createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/cleanup`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dry_run: true }),
  });
  assert.equal(res.status, 422);
  assert.equal((await res.json()).error, 'MISSING_SOURCE');
});

test('cleanup: preserves predictions.json when it exists', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-cleanup-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'olist-001', hub_id: null, source: 'olist', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
    { order_id: 'manual-001', hub_id: null, createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));
  // predictions.json has predictions
  await writeFile(predictionsFile, JSON.stringify([
    { prediction_id: 'p1', order_id: 'olist-001', hub_id: null, delay_probability: 0.5, predicted_late: true, threshold: 0.37, model_version: 'v1', source: 'ml', warnings: [], predicted_at: '2025-01-01T00:00:00.000Z' },
    { prediction_id: 'p2', order_id: 'manual-001', hub_id: null, delay_probability: 0.8, predicted_late: true, threshold: 0.37, model_version: 'v1', source: 'ml', warnings: [], predicted_at: '2025-01-01T00:00:00.000Z' },
  ]));
  await writeFile(journalFile, '');

  const app = await createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/cleanup`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ source: 'olist', confirm: true }),
  });
  assert.equal(res.status, 200);

  // Verify predictions.json only has manual-001
  const predJson = JSON.parse(await readFile(predictionsFile, 'utf8'));
  assert.equal(predJson.length, 1);
  assert.equal(predJson[0].order_id, 'manual-001');
});

test('cleanup: removes all orders and predictions when all match source', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-cleanup-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'olist-001', hub_id: null, source: 'olist', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));
  await writeFile(predictionsFile, '[]');
  await writeFile(journalFile, JSON.stringify({ prediction_id: 'p1', order_id: 'olist-001', hub_id: null, delay_probability: 0.5, predicted_late: true, threshold: 0.37, model_version: 'v1', source: 'ml', warnings: [], predicted_at: '2025-01-01T00:00:00.000Z' }) + '\n');

  const app = await createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/cleanup`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ source: 'olist', confirm: true }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.summary.orders_to_remove, 1);
  assert.equal(body.summary.orders_preserved, 0);

  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.length, 0);

  const journal = await readFile(journalFile, 'utf8');
  assert.equal(journal.trim(), '');
});

test('cleanup: source matching is case-insensitive', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-cleanup-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'olist-001', hub_id: null, source: 'OLIST', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));
  await writeFile(predictionsFile, '[]');
  await writeFile(journalFile, '');

  const app = await createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  // Query with lowercase 'olist' should match 'OLIST'
  const res = await fetch(`${baseUrl}/api/v1/orders/cleanup`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ source: 'olist', dry_run: true }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.summary.orders_to_remove, 1);
});

test('cleanup: does not remove orders without matching source', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-cleanup-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'manual-001', hub_id: null, createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
    { order_id: 'manual-002', hub_id: null, source: 'manual', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));
  await writeFile(predictionsFile, '[]');
  await writeFile(journalFile, '');

  const app = await createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/cleanup`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ source: 'olist', confirm: true }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.summary.orders_to_remove, 0);

  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.length, 2);
});

test('import with source field marks orders correctly', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-import-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, '[]');

  const app = await createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/import`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      orders: [
        { order_id: 'olist-001' },
        { order_id: 'olist-002' },
      ],
      source: 'olist',
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.total, 2);
  for (const item of body.data) {
    assert.equal(item.source, 'olist');
  }

  // Verify stored orders have source
  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.length, 2);
  assert.equal(stored[0].source, 'olist');
  assert.equal(stored[1].source, 'olist');
});

test('import without source field does not set source', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-import-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, '[]');

  const app = await createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/import`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      orders: [{ order_id: 'manual-001' }],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.data[0].source, null);

  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.length, 1);
  assert.equal(stored[0].source, undefined);
});
