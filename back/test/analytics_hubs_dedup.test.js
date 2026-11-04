import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
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

async function makeHarness(t, { predictions = [], orders = [] } = {}) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-analytics-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, JSON.stringify([
    { id: 'hub-a', code: 'A-01', name: 'Hub A', city: 'São Paulo', state: 'SP', status: 'active', validationStatus: 'APROVADO' },
    { id: 'hub-b', code: 'B-01', name: 'Hub B', city: 'Salvador', state: 'BA', status: 'active', validationStatus: 'APROVADO' },
  ]));
  await writeFile(ordersFile, JSON.stringify(orders));

  // Write predictions to the journal file
  if (predictions.length > 0) {
    const lines = predictions.map((p) => JSON.stringify(p)).join('\n') + '\n';
    await writeFile(journalFile, lines, { encoding: 'utf8', mode: 0o600 });
  }

  // Mock ML server
  const mlServer = createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      model_version: 'rf-olist-v1',
      source: 'olist',
      synthetic: false,
      delay_probability: 0.5,
      threshold: 0.4,
      predicted_late: false,
      warnings: [],
    }));
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
  return { baseUrl, directory, journalFile };
}

function makePrediction({
  orderId = 'order-1',
  hubId = 'hub-a',
  probability = 0.8,
  predictedLate = true,
  predictedAt = '2024-01-01T12:00:00.000Z',
  version = 'rf-olist-v1',
} = {}) {
  return {
    prediction_id: crypto.randomUUID(),
    order_id: orderId,
    hub_id: hubId,
    delay_probability: probability,
    predicted_late: predictedLate,
    threshold: 0.4,
    model_version: version,
    source: 'olist',
    synthetic: false,
    warnings: [],
    predicted_at: predictedAt,
  };
}

test('analytics/hubs — um pedido com uma previsão é contado uma vez', async (t) => {
  const { baseUrl } = await makeHarness(t, {
    predictions: [
      makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: true }),
    ],
  });

  const res = await fetch(`${baseUrl}/api/v1/analytics/hubs`);
  assert.equal(res.status, 200);
  const body = await res.json();
  const hubA = body.data.find((h) => h.hub_id === 'hub-a');
  assert.ok(hubA, 'Hub A deve estar na resposta');
  assert.equal(hubA.predictions_count, 1, 'Deve contar 1 previsão');
  assert.equal(hubA.risk_count, 1, 'Deve contar 1 risco');
  assert.equal(hubA.risk_percentage, 100, 'Risco deve ser 100%');
});

test('analytics/hubs — um pedido com várias previsões é contado uma vez (a mais recente)', async (t) => {
  const { baseUrl } = await makeHarness(t, {
    predictions: [
      makePrediction({
        orderId: 'order-1',
        hubId: 'hub-a',
        predictedLate: true,
        predictedAt: '2024-01-01T10:00:00.000Z',
      }),
      makePrediction({
        orderId: 'order-1',
        hubId: 'hub-a',
        predictedLate: false,
        predictedAt: '2024-01-01T12:00:00.000Z',
      }),
      makePrediction({
        orderId: 'order-1',
        hubId: 'hub-a',
        predictedLate: true,
        predictedAt: '2024-01-01T14:00:00.000Z',
      }),
    ],
  });

  const res = await fetch(`${baseUrl}/api/v1/analytics/hubs`);
  assert.equal(res.status, 200);
  const body = await res.json();
  const hubA = body.data.find((h) => h.hub_id === 'hub-a');
  assert.ok(hubA, 'Hub A deve estar na resposta');
  assert.equal(hubA.predictions_count, 1, 'Deve contar 1 pedido único, não 3 previsões');
  // The most recent prediction (14:00) has predicted_late: true
  assert.equal(hubA.risk_count, 1, 'A previsão mais recente é de risco');
  assert.equal(hubA.risk_percentage, 100, 'Risco deve ser 100%');
});

test('analytics/hubs — dois pedidos diferentes são contados separadamente', async (t) => {
  const { baseUrl } = await makeHarness(t, {
    predictions: [
      makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: true }),
      makePrediction({ orderId: 'order-2', hubId: 'hub-a', predictedLate: false }),
    ],
  });

  const res = await fetch(`${baseUrl}/api/v1/analytics/hubs`);
  assert.equal(res.status, 200);
  const body = await res.json();
  const hubA = body.data.find((h) => h.hub_id === 'hub-a');
  assert.ok(hubA, 'Hub A deve estar na resposta');
  assert.equal(hubA.predictions_count, 2, 'Deve contar 2 pedidos');
  assert.equal(hubA.risk_count, 1, 'Deve contar 1 risco');
  assert.equal(hubA.risk_percentage, 50, 'Risco deve ser 50%');
});

test('analytics/hubs — risk_count nunca é maior que predictions_count', async (t) => {
  const { baseUrl } = await makeHarness(t, {
    predictions: [
      makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: true }),
      makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: true, predictedAt: '2024-01-01T11:00:00.000Z' }),
      makePrediction({ orderId: 'order-2', hubId: 'hub-a', predictedLate: false }),
      makePrediction({ orderId: 'order-3', hubId: 'hub-a', predictedLate: true }),
    ],
  });

  const res = await fetch(`${baseUrl}/api/v1/analytics/hubs`);
  assert.equal(res.status, 200);
  const body = await res.json();
  const hubA = body.data.find((h) => h.hub_id === 'hub-a');
  assert.ok(hubA, 'Hub A deve estar na resposta');
  // 3 unique orders: order-1 (latest: risk), order-2 (no risk), order-3 (risk)
  assert.equal(hubA.predictions_count, 3, '3 pedidos únicos');
  assert.equal(hubA.risk_count, 2, '2 de risco (order-1 latest + order-3)');
  assert.ok(hubA.risk_count <= hubA.predictions_count,
    'risk_count deve ser <= predictions_count');
});

test('analytics/hubs — deduplicação mantém a previsão mais recente por order_id', async (t) => {
  const { baseUrl } = await makeHarness(t, {
    predictions: [
      makePrediction({
        orderId: 'order-1',
        hubId: 'hub-a',
        predictedLate: true,
        probability: 0.9,
        predictedAt: '2024-01-01T10:00:00.000Z',
      }),
      makePrediction({
        orderId: 'order-1',
        hubId: 'hub-a',
        predictedLate: false,
        probability: 0.2,
        predictedAt: '2024-01-01T14:00:00.000Z',
      }),
    ],
  });

  const res = await fetch(`${baseUrl}/api/v1/analytics/hubs`);
  assert.equal(res.status, 200);
  const body = await res.json();
  const hubA = body.data.find((h) => h.hub_id === 'hub-a');
  assert.ok(hubA, 'Hub A deve estar na resposta');
  assert.equal(hubA.predictions_count, 1, '1 pedido único');
  // Most recent prediction (14:00) has predicted_late: false
  assert.equal(hubA.risk_count, 0, 'A previsão mais recente não é de risco');
  assert.equal(hubA.risk_percentage, 0, 'Risco deve ser 0%');
});

test('analytics/hubs — filtros por hub_id funcionam com deduplicação', async (t) => {
  const { baseUrl } = await makeHarness(t, {
    predictions: [
      makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: true }),
      makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: false, predictedAt: '2024-01-01T11:00:00.000Z' }),
      makePrediction({ orderId: 'order-2', hubId: 'hub-b', predictedLate: true }),
    ],
  });

  const resA = await fetch(`${baseUrl}/api/v1/analytics/hubs?hub_id=hub-a`);
  assert.equal(resA.status, 200);
  const bodyA = await resA.json();
  assert.equal(bodyA.total, 1, 'Apenas hub-a na resposta');
  assert.equal(bodyA.data[0].predictions_count, 1, '1 pedido único no hub-a');

  const resB = await fetch(`${baseUrl}/api/v1/analytics/hubs?hub_id=hub-b`);
  assert.equal(resB.status, 200);
  const bodyB = await resB.json();
  assert.equal(bodyB.total, 1, 'Apenas hub-b na resposta');
  assert.equal(bodyB.data[0].predictions_count, 1, '1 pedido no hub-b');
});

test('analytics/hubs — filtros por período funcionam com deduplicação', async (t) => {
  const { baseUrl } = await makeHarness(t, {
    predictions: [
      makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: true, predictedAt: '2024-01-01T10:00:00.000Z' }),
      makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: false, predictedAt: '2024-01-05T10:00:00.000Z' }),
      makePrediction({ orderId: 'order-2', hubId: 'hub-a', predictedLate: true, predictedAt: '2024-01-10T10:00:00.000Z' }),
    ],
  });

  // Filter to only include Jan 1-3
  const res = await fetch(`${baseUrl}/api/v1/analytics/hubs?start_date=2024-01-01&end_date=2024-01-03`);
  assert.equal(res.status, 200);
  const body = await res.json();
  const hubA = body.data.find((h) => h.hub_id === 'hub-a');
  assert.ok(hubA, 'Hub A deve estar na resposta');
  // Only order-1's first prediction (Jan 1) is in range; order-2 is Jan 10
  // After dedup: order-1 has 1 prediction in range
  assert.equal(hubA.predictions_count, 1, 'Apenas 1 pedido no período');
});

test('batch endpoint — pedidos já previstos são pulados (idempotência)', async (t) => {
  const orders = [
    { order_id: 'order-1', hub_id: 'hub-a', createdAt: new Date().toISOString() },
    { order_id: 'order-2', hub_id: 'hub-a', createdAt: new Date().toISOString() },
  ];
  const existingPredictions = [
    makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: true, predictedAt: '2024-01-01T10:00:00.000Z' }),
  ];

  const { baseUrl } = await makeHarness(t, {
    predictions: existingPredictions,
    orders,
  });

  // Track ML calls
  let mlCallCount = 0;
  // We need to override the ML server to count calls — but the harness already creates one.
  // Instead, we check the SSE response for skipped status.

  // Send batch with both orders
  const response = await fetch(`${baseUrl}/api/v1/predictions/batch`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream' },
    body: JSON.stringify({
      shipments: [shipment, shipment],
      orderIds: ['order-1', 'order-2'],
    }),
  });

  assert.equal(response.status, 200);

  // Read the SSE stream
  let body = '';
  const decoder = new TextDecoder();
  for await (const chunk of response.body) {
    body += decoder.decode(chunk);
  }

  // Parse SSE events
  const events = body.split('\n\n').map((e) => {
    const line = e.trim();
    if (line.startsWith('data: ')) {
      return JSON.parse(line.substring(6));
    }
    return null;
  }).filter(Boolean);

  const completeEvent = events.find((e) => e.type === 'complete');
  assert.ok(completeEvent, 'Deve ter evento complete');
  assert.ok(completeEvent.skipped >= 1, 'Deve ter pulado pelo menos 1 pedido já previsto');
  assert.ok(completeEvent.succeeded >= 1, 'Deve ter processado pelo menos 1 pedido novo');
});

test('batch endpoint — resultado skipped contém dados da previsão existente', async (t) => {
  const orders = [
    { order_id: 'order-1', hub_id: 'hub-a', createdAt: new Date().toISOString() },
  ];
  const existingPredictions = [
    makePrediction({
      orderId: 'order-1',
      hubId: 'hub-a',
      predictedLate: true,
      probability: 0.75,
      predictedAt: '2024-01-01T10:00:00.000Z',
    }),
  ];

  const { baseUrl } = await makeHarness(t, {
    predictions: existingPredictions,
    orders,
  });

  const response = await fetch(`${baseUrl}/api/v1/predictions/batch`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream' },
    body: JSON.stringify({
      shipments: [shipment],
      orderIds: ['order-1'],
    }),
  });

  assert.equal(response.status, 200);

  let body = '';
  const decoder = new TextDecoder();
  for await (const chunk of response.body) {
    body += decoder.decode(chunk);
  }

  const events = body.split('\n\n').map((e) => {
    const line = e.trim();
    if (line.startsWith('data: ')) {
      return JSON.parse(line.substring(6));
    }
    return null;
  }).filter(Boolean);

  const completeEvent = events.find((e) => e.type === 'complete');
  assert.ok(completeEvent, 'Deve ter evento complete');
  const skippedResult = completeEvent.results.find((r) => r.status === 'skipped');
  assert.ok(skippedResult, 'Deve ter resultado com status skipped');
  assert.equal(skippedResult.delay_probability, 0.75, 'Deve retornar a probabilidade da previsão existente');
  assert.equal(skippedResult.predicted_late, true, 'Deve retornar predicted_late da previsão existente');
});

test('analytics/hubs — resposta é compatível com o Flutter (validação HubRiskAggregate)', async (t) => {
  const { baseUrl } = await makeHarness(t, {
    predictions: [
      makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: true }),
      makePrediction({ orderId: 'order-1', hubId: 'hub-a', predictedLate: false, predictedAt: '2024-01-01T11:00:00.000Z' }),
      makePrediction({ orderId: 'order-2', hubId: 'hub-a', predictedLate: false }),
    ],
  });

  const res = await fetch(`${baseUrl}/api/v1/analytics/hubs`);
  assert.equal(res.status, 200);
  const body = await res.json();

  // Validate structure matches Flutter's HubRiskAggregate expectations
  for (const hub of body.data) {
    assert.ok(typeof hub.hub_id === 'string' && hub.hub_id.length > 0, 'hub_id deve ser string não vazia');
    assert.ok(typeof hub.predictions_count === 'number' && hub.predictions_count > 0, 'predictions_count deve ser número positivo');
    assert.ok(typeof hub.risk_count === 'number' && hub.risk_count >= 0, 'risk_count deve ser número não negativo');
    assert.ok(hub.risk_count <= hub.predictions_count, 'risk_count <= predictions_count');
    assert.ok(typeof hub.risk_percentage === 'number' && hub.risk_percentage >= 0 && hub.risk_percentage <= 100,
      'risk_percentage deve estar entre 0 e 100');
    assert.ok(Array.isArray(hub.thresholds), 'thresholds deve ser array');
    assert.ok(Array.isArray(hub.model_versions), 'model_versions deve ser array');
    assert.ok(typeof hub.thresholds_consistent === 'boolean', 'thresholds_consistent deve ser boolean');
    assert.ok(typeof hub.model_versions_consistent === 'boolean', 'model_versions_consistent deve ser boolean');
  }
});
