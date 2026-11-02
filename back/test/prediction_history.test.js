import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { appendFile, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

const shipment = {
  purchase_at: '2018-01-10T10:00:00',
  dispatched_at: '2018-01-11T09:00:00',
  estimated_delivery_at: '2018-01-20T00:00:00',
  seller_state: 'SP',
  customer_state: 'BA',
  items_count: 1,
  sellers_count: 1,
  price: 350,
  freight_value: 35,
  distance_km: 1450,
};

const output = ({ probability = 0.8, predictedLate = true, threshold = 0.4,
  version = 'rf-olist-v1', synthetic = false } = {}) => ({
  model_version: version,
  source: 'olist',
  synthetic,
  delay_probability: probability,
  threshold,
  predicted_late: predictedLate,
  warnings: ['Aviso do serviço ML.'],
});

async function makeHarness(t, {
  orders = [
    { order_id: 'order-hub-a', hub_id: 'hub-a', createdAt: new Date().toISOString() },
    { order_id: 'order-no-hub', hub_id: null, createdAt: new Date().toISOString() },
    { order_id: 'order-changing-hub', hub_id: 'hub-a', createdAt: new Date().toISOString() },
    { order_id: 'order-hub-b', hub_id: 'hub-b', createdAt: new Date().toISOString() },
  ],
  predictionsPath,
  mlHandler,
} = {}) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-predictions-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = predictionsPath ?? path.join(directory, 'predictions.json');
  await writeFile(hubsFile, JSON.stringify([
    { id: 'hub-a', code: 'A-01', name: 'Hub A', city: 'São Paulo', state: 'SP', status: 'active', validationStatus: 'APROVADO' },
    { id: 'hub-b', code: 'B-01', name: 'Hub B', city: 'Salvador', state: 'BA', status: 'active', validationStatus: 'APROVADO' },
  ]));
  await writeFile(ordersFile, JSON.stringify(orders));
  const calls = [];
  const mlServer = createServer((req, res) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => body += chunk);
    req.on('end', async () => {
      const parsed = JSON.parse(body);
      calls.push(parsed);
      try {
        const result = mlHandler ? await mlHandler({ req, body: parsed, index: calls.length, directory, ordersFile }) : output();
        if (result?.status) {
          res.writeHead(result.status, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(result.body ?? {}));
          return;
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (error) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: error.message }));
      }
    });
  }).listen(0);
  await new Promise((resolve) => mlServer.once('listening', resolve));
  const apiServer = createApp({
    mlUrl: `http://127.0.0.1:${mlServer.address().port}`,
    timeoutMs: 1000,
    hubsFile,
    ordersFile,
    predictionsFile,
  }).listen(0);
  await new Promise((resolve) => apiServer.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${apiServer.address().port}`;
  t.after(async () => {
    await Promise.all([mlServer, apiServer].map((server) =>
      new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve())),
    ));
    await rm(directory, { recursive: true, force: true });
  });
  return { baseUrl, calls, directory, ordersFile, predictionsFile };
}

async function predict(baseUrl, orderId) {
  return fetch(`${baseUrl}/api/v1/predictions?order_id=${encodeURIComponent(orderId)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(shipment),
  });
}

async function readPredictionHistory(predictionsFile) {
  let history = [];
  try {
    history = JSON.parse(await readFile(predictionsFile, 'utf8'));
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  try {
    const journal = await readFile(`${predictionsFile}.jsonl`, 'utf8');
    history.push(...journal.split('\n').filter(Boolean).map((line) => JSON.parse(line)));
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  return history;
}

async function assertNoPredictionHistory(predictionsFile) {
  await assert.rejects(readFile(predictionsFile, 'utf8'), { code: 'ENOENT' });
  await assert.rejects(readFile(`${predictionsFile}.jsonl`, 'utf8'), { code: 'ENOENT' });
}

test('persists each successful real model response with the hub captured at request time', async (t) => {
  const harness = await makeHarness(t, {
    mlHandler: async ({ index, ordersFile }) => {
      if (index === 1) return output({ probability: 0.3, predictedLate: false });
      if (index === 2) return output({ probability: 0.9, predictedLate: true, threshold: 0.5, version: 'rf-olist-v2' });
      if (index === 3) {
        // Change the order while inference is in flight; this prediction must keep its initial hub.
        const orders = JSON.parse(await readFile(ordersFile, 'utf8'));
        orders.find((order) => order.order_id === 'order-changing-hub').hub_id = 'hub-b';
        await writeFile(ordersFile, JSON.stringify(orders));
        return output({ probability: 0.7, predictedLate: true, threshold: 0.5, version: 'rf-olist-v2' });
      }
      return output({ probability: 0.95, predictedLate: true, threshold: 0.5, version: 'rf-olist-v2' });
    },
  });

  const first = await predict(harness.baseUrl, 'order-hub-a');
  const firstResult = await first.json();
  assert.equal(first.status, 200);
  assert.equal(firstResult.prediction_id.length > 0, true);
  assert.equal(firstResult.persisted, true);
  assert.equal(firstResult.delay_probability, 0.3);
  assert.deepEqual(harness.calls[0], shipment);

  const unassociatedResponse = await predict(harness.baseUrl, 'order-no-hub');
  assert.equal(unassociatedResponse.status, 200);
  const unassociated = (await readPredictionHistory(harness.predictionsFile))
    .find((record) => record.order_id === 'order-no-hub');
  assert.equal(unassociated.hub_id, null);

  const snapshotResponse = await predict(harness.baseUrl, 'order-changing-hub');
  assert.equal(snapshotResponse.status, 200);
  const repeatResponse = await predict(harness.baseUrl, 'order-hub-a');
  assert.equal(repeatResponse.status, 200);
  const history = await readPredictionHistory(harness.predictionsFile);
  const orderHistory = history.filter((record) => record.order_id === 'order-hub-a');
  assert.equal(orderHistory.length, 2);
  assert.notEqual(orderHistory[0].prediction_id, orderHistory[1].prediction_id);
  assert.ok(orderHistory.every((record) => record.hub_id === 'hub-a'));
  assert.equal(history.find((record) => record.order_id === 'order-changing-hub').hub_id, 'hub-a');
  assert.equal(history[0].source, 'olist');
  assert.equal(history[0].synthetic, false);
  assert.deepEqual(history[0].warnings, ['Aviso do serviço ML.']);
  assert.ok(history[0].predicted_at);
});

test('does not call ML or persist a prediction for an unknown order', async (t) => {
  const harness = await makeHarness(t);
  const response = await predict(harness.baseUrl, 'not-imported');
  assert.equal(response.status, 404);
  assert.equal((await response.json()).error, 'ORDER_NOT_FOUND');
  assert.equal(harness.calls.length, 0);
  await assertNoPredictionHistory(harness.predictionsFile);
});

test('keeps one-off simulations compatible and does not persist without order_id', async (t) => {
  const harness = await makeHarness(t);
  const response = await fetch(`${harness.baseUrl}/api/v1/predictions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(shipment),
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.delay_probability, 0.8);
  assert.equal(Object.hasOwn(body, 'prediction_id'), false);
  assert.equal(harness.calls.length, 1);
  assert.deepEqual(harness.calls[0], shipment);
  await assertNoPredictionHistory(harness.predictionsFile);
});

test('returns an empty aggregate when there is no prediction history', async (t) => {
  const harness = await makeHarness(t);
  const response = await fetch(`${harness.baseUrl}/api/v1/analytics/hubs`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    data: [],
    total: 0,
    filters: { start_date: null, end_date: null, hub_id: null },
  });
  assert.equal(harness.calls.length, 0);
});

test('does not report persistence success if writing prediction history fails', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-predictions-failure-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const blockedParent = path.join(directory, 'not-a-directory');
  await writeFile(blockedParent, 'file');
  const harness = await makeHarness(t, {
    predictionsPath: path.join(blockedParent, 'predictions.json'),
  });
  const response = await predict(harness.baseUrl, 'order-hub-a');
  assert.equal(response.status, 500);
  const body = await response.json();
  assert.equal(body.error, 'PREDICTION_PERSISTENCE_ERROR');
  assert.equal(body.persisted, false);
  assert.equal(body.prediction.delay_probability, 0.8);
});

test('serializes concurrent appends without losing prediction history', async (t) => {
  const orders = Array.from({ length: 12 }, (_, index) => ({
    order_id: `parallel-${index}`,
    hub_id: 'hub-a',
  }));
  const harness = await makeHarness(t, {
    orders,
    mlHandler: async ({ index }) => {
      await new Promise((resolve) => setTimeout(resolve, index % 3));
      return output({ probability: index / 20, predictedLate: index % 2 === 0 });
    },
  });
  const responses = await Promise.all(orders.map((order) => predict(harness.baseUrl, order.order_id)));
  assert.ok(responses.every((response) => response.status === 200));
  const history = await readPredictionHistory(harness.predictionsFile);
  assert.equal(history.length, orders.length);
});

test('aggregates persisted decisions by hub and date without calling ML', async (t) => {
  const harness = await makeHarness(t, {
    mlHandler: async ({ index }) => index === 1
      ? output({ probability: 0.2, predictedLate: true, threshold: 0.4 })
      : index === 2
        ? output({ probability: 0.99, predictedLate: false, threshold: 0.4 })
        : output({ probability: 0.75, predictedLate: true, threshold: 0.5, version: 'rf-olist-v2' }),
  });
  await predict(harness.baseUrl, 'order-hub-a');
  await predict(harness.baseUrl, 'order-hub-a');
  await predict(harness.baseUrl, 'order-changing-hub');
  await predict(harness.baseUrl, 'order-no-hub');
  const records = await readPredictionHistory(harness.predictionsFile);
  const date = records[0].predicted_at.slice(0, 10);
  const syntheticRecords = [
    { ...records[0], prediction_id: 'test-synthetic', order_id: 'synthetic', synthetic: true },
    { ...records[0], prediction_id: 'test-invalid', order_id: 'invalid', delay_probability: 2 },
    { ...records[0], prediction_id: 'test-no-hub', order_id: 'unlinked', hub_id: null },
  ];
  await appendFile(`${harness.predictionsFile}.jsonl`, `${syntheticRecords.map((item) => JSON.stringify(item)).join('\n')}\n`);
  const callsBeforeAnalytics = harness.calls.length;

  const allResponse = await fetch(`${harness.baseUrl}/api/v1/analytics/hubs?start_date=${date}&end_date=${date}`);
  assert.equal(allResponse.status, 200);
  const all = await allResponse.json();
  assert.equal(all.data.length, 1);
  assert.deepEqual(harness.calls.length, callsBeforeAnalytics);
  const hubA = all.data[0];
  assert.equal(hubA.hub_id, 'hub-a');
  // After deduplication by order_id:
  // - order-hub-a: predicted twice (call 1: risk, call 2: no risk). Latest (call 2) → no risk.
  // - order-changing-hub: predicted once (call 3, default handler) → risk.
  // - order-no-hub: no hub_id → excluded from aggregation.
  // Result: 2 unique orders, 1 at risk.
  assert.equal(hubA.predictions_count, 2);
  assert.equal(hubA.risk_count, 1);
  assert.equal(hubA.risk_percentage, 50);
  assert.equal(hubA.threshold, null);
  assert.deepEqual(hubA.thresholds, [0.4, 0.5]);
  assert.equal(hubA.thresholds_consistent, false);
  assert.equal(hubA.model_version, null);
  assert.deepEqual(hubA.model_versions, ['rf-olist-v1', 'rf-olist-v2']);
  assert.equal(hubA.model_versions_consistent, false);
  assert.ok(hubA.last_prediction_at);

  const filtered = await fetch(`${harness.baseUrl}/api/v1/analytics/hubs?hub_id=hub-a&start_date=${date}`);
  assert.equal((await filtered.json()).data[0].predictions_count, 2);
  const future = new Date(Date.parse(`${date}T00:00:00.000Z`) + 86400000).toISOString().slice(0, 10);
  const empty = await fetch(`${harness.baseUrl}/api/v1/analytics/hubs?start_date=${future}`);
  assert.deepEqual((await empty.json()).data, []);
  const invalidDate = await fetch(`${harness.baseUrl}/api/v1/analytics/hubs?start_date=2025-02-30`);
  assert.equal(invalidDate.status, 422);
  const invalidRange = await fetch(`${harness.baseUrl}/api/v1/analytics/hubs?start_date=2025-02-02&end_date=2025-02-01`);
  assert.equal(invalidRange.status, 422);
  const unknownHub = await fetch(`${harness.baseUrl}/api/v1/analytics/hubs?hub_id=missing`);
  assert.equal(unknownHub.status, 404);
});

test('ML errors and invalid ML response are not recorded', async (t) => {
  const harness = await makeHarness(t, {
    mlHandler: ({ index }) => index === 1
      ? { status: 503, body: { detail: 'unavailable' } }
      : { model_version: 'v1', source: 'olist', synthetic: false, warnings: [] },
  });
  const unavailable = await predict(harness.baseUrl, 'order-hub-a');
  assert.equal(unavailable.status, 503);
  const invalid = await predict(harness.baseUrl, 'order-hub-a');
  assert.equal(invalid.status, 502);
  assert.equal((await invalid.json()).persisted, false);
  await assertNoPredictionHistory(harness.predictionsFile);
});
