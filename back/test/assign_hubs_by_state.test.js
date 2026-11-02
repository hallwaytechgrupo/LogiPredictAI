import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

test('assign-hubs-by-state: dry run with single hub per state', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  const hubSp = {
    id: 'hub-sp-001',
    code: 'HUB-SP-001',
    name: 'Hub SP',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  };
  const hubMg = {
    id: 'hub-mg-001',
    code: 'HUB-MG-001',
    name: 'Hub MG',
    city: 'Belo Horizonte',
    state: 'MG',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -19.92,
    longitude: -43.94,
  };
  await writeFile(hubsFile, JSON.stringify([hubSp, hubMg]));
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'order-sp-001', hub_id: 'hub-sp-001', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
    { order_id: 'order-mg-001', hub_id: 'hub-sp-001', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [
        { order_id: 'order-sp-001', customer_state: 'SP' },
        { order_id: 'order-mg-001', customer_state: 'MG' },
      ],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.dry_run, true);
  assert.equal(body.summary.total_analyzed, 2);
  assert.equal(body.summary.total_unassigned, 0);

  // order-sp-001 should be assigned to hub-sp-001 (unchanged)
  const spAssign = body.assignments.find((a) => a.order_id === 'order-sp-001');
  assert.equal(spAssign.assigned_hub_id, 'hub-sp-001');

  // order-mg-001 should be assigned to hub-mg-001 (would change from hub-sp-001)
  const mgAssign = body.assignments.find((a) => a.order_id === 'order-mg-001');
  assert.equal(mgAssign.assigned_hub_id, 'hub-mg-001');
  assert.equal(mgAssign.reason, 'WOULD_CHANGE');

  // Verify orders are NOT modified in dry-run
  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.find((o) => o.order_id === 'order-mg-001').hub_id, 'hub-sp-001');
});

test('assign-hubs-by-state: dry run with multiple hubs per state distributes deterministically', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  // 4 hubs in SP
  const hubsSp = [];
  for (let i = 1; i <= 4; i++) {
    hubsSp.push({
      id: `hub-sp-${String(i).padStart(3, '0')}`,
      code: `HUB-SP-${String(i).padStart(3, '0')}`,
      name: `Hub SP ${i}`,
      city: 'São Paulo',
      state: 'SP',
      status: 'active',
      validationStatus: 'APROVADO',
      latitude: -23.55,
      longitude: -46.63,
    });
  }
  await writeFile(hubsFile, JSON.stringify(hubsSp));
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  // Generate 100 orders for SP
  const orders = [];
  for (let i = 1; i <= 100; i++) {
    orders.push({ order_id: `order-sp-${String(i).padStart(4, '0')}`, customer_state: 'SP' });
  }

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dry_run: true, orders }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();

  // All 100 should be assigned (no unassigned)
  assert.equal(body.summary.total_unassigned, 0);

  // Check distribution across hubs
  const hubCounts = new Map();
  for (const a of body.assignments) {
    hubCounts.set(a.assigned_hub_id, (hubCounts.get(a.assigned_hub_id) || 0) + 1);
  }
  // Should use all 4 hubs
  assert.equal(hubCounts.size, 4);

  // Deterministic: running again should produce same result
  const res2 = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dry_run: true, orders }),
  });
  const body2 = await res2.json();
  assert.deepEqual(body2.assignments, body.assignments);
});

test('assign-hubs-by-state: state without hub coverage reports unassigned', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  // Only SP hub, no DF hub
  await writeFile(hubsFile, JSON.stringify([{
    id: 'hub-sp-001',
    code: 'HUB-SP-001',
    name: 'Hub SP',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  }]));
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [
        { order_id: 'order-sp-001', customer_state: 'SP' },
        { order_id: 'order-df-001', customer_state: 'DF' },
      ],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.summary.total_unassigned, 1);
  assert.equal(body.summary.states_uncovered, 1);

  const dfState = body.uncovered_states.find((s) => s.state === 'DF');
  assert.ok(dfState);
  assert.equal(dfState.orders_count, 1);

  const dfAssign = body.assignments.find((a) => a.order_id === 'order-df-001');
  assert.equal(dfAssign.assigned_hub_id, null);
  assert.equal(dfAssign.reason, 'NO_HUB_FOR_STATE');
});

test('assign-hubs-by-state: rejects invalid customer_state', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [{ order_id: 'order-001', customer_state: 'XX' }],
    }),
  });
  assert.equal(res.status, 422);
  const body = await res.json();
  assert.equal(body.error, 'INVALID_STATE');
});

test('assign-hubs-by-state: rejects invalid order_id', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [{ order_id: '', customer_state: 'SP' }],
    }),
  });
  assert.equal(res.status, 422);
  assert.equal((await res.json()).error, 'INVALID_ORDER_ID');
});

test('assign-hubs-by-state: applies assignment and updates orders', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  const hubSp = {
    id: 'hub-sp-001',
    code: 'HUB-SP-001',
    name: 'Hub SP',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  };
  const hubMg = {
    id: 'hub-mg-001',
    code: 'HUB-MG-001',
    name: 'Hub MG',
    city: 'Belo Horizonte',
    state: 'MG',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -19.92,
    longitude: -43.94,
  };
  await writeFile(hubsFile, JSON.stringify([hubSp, hubMg]));
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'order-sp-001', hub_id: 'hub-sp-001', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
    { order_id: 'order-mg-001', hub_id: 'hub-sp-001', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  // Apply assignment (not dry run)
  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: false,
      orders: [
        { order_id: 'order-sp-001', customer_state: 'SP' },
        { order_id: 'order-mg-001', customer_state: 'MG' },
      ],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.dry_run, false);
  assert.equal(body.summary.assigned, 1); // order-mg-001 changes from SP to MG
  assert.equal(body.summary.unchanged, 1); // order-sp-001 stays at SP

  // Verify orders.json is updated
  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.find((o) => o.order_id === 'order-mg-001').hub_id, 'hub-mg-001');
  assert.equal(stored.find((o) => o.order_id === 'order-sp-001').hub_id, 'hub-sp-001');
});

test('assign-hubs-by-state: idempotent — running twice produces same result', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  const hubSp = {
    id: 'hub-sp-001',
    code: 'HUB-SP-001',
    name: 'Hub SP',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  };
  await writeFile(hubsFile, JSON.stringify([hubSp]));
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'order-001', hub_id: null, createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const ordersPayload = [{ order_id: 'order-001', customer_state: 'SP' }];

  // First run
  const res1 = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dry_run: false, orders: ordersPayload }),
  });
  const body1 = await res1.json();
  assert.equal(body1.summary.assigned, 1);

  // Second run — should be unchanged
  const res2 = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dry_run: false, orders: ordersPayload }),
  });
  const body2 = await res2.json();
  assert.equal(body2.summary.assigned, 0);
  assert.equal(body2.summary.unchanged, 1);
});

test('assign-hubs-by-state: reports orders with existing predictions', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  const hubSp = {
    id: 'hub-sp-001',
    code: 'HUB-SP-001',
    name: 'Hub SP',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  };
  const hubMg = {
    id: 'hub-mg-001',
    code: 'HUB-MG-001',
    name: 'Hub MG',
    city: 'Belo Horizonte',
    state: 'MG',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -19.92,
    longitude: -43.94,
  };
  await writeFile(hubsFile, JSON.stringify([hubSp, hubMg]));
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'order-001', hub_id: 'hub-sp-001', createdAt: '2025-01-01T00:00:00.000Z', updatedAt: '2025-01-01T00:00:00.000Z' },
  ]));
  // Prediction exists for order-001
  await writeFile(predictionsFile, JSON.stringify([{
    prediction_id: 'pred-001',
    order_id: 'order-001',
    hub_id: 'hub-sp-001',
    delay_probability: 0.5,
    predicted_late: true,
    threshold: 0.37,
    model_version: 'v1',
    source: 'ml',
    warnings: [],
    predicted_at: '2025-01-01T00:00:00.000Z',
  }]));

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [{ order_id: 'order-001', customer_state: 'SP' }],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  const assign = body.assignments[0];
  assert.equal(assign.has_prediction, true);
  assert.equal(body.summary.total_with_prediction, 1);
});

test('assign-hubs-by-state: skips orders not yet imported', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  const hubSp = {
    id: 'hub-sp-001',
    code: 'HUB-SP-001',
    name: 'Hub SP',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  };
  await writeFile(hubsFile, JSON.stringify([hubSp]));
  await writeFile(ordersFile, '[]'); // No orders imported

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  // Apply assignment for an order that doesn't exist in orders.json
  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: false,
      orders: [{ order_id: 'nonexistent-order', customer_state: 'SP' }],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.summary.skipped, 1);
  assert.equal(body.summary.assigned, 0);
});

test('assign-hubs-by-state: rejects empty order list', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dry_run: true, orders: [] }),
  });
  assert.equal(res.status, 422);
  assert.equal((await res.json()).error, 'INVALID_ORDERS');
});

test('assign-hubs-by-state: only approved hubs are eligible', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  // SP has one approved and one pending hub
  await writeFile(hubsFile, JSON.stringify([
    {
      id: 'hub-sp-approved',
      code: 'HUB-SP-APR',
      name: 'Hub SP Approved',
      city: 'São Paulo',
      state: 'SP',
      status: 'active',
      validationStatus: 'APROVADO',
      latitude: -23.55,
      longitude: -46.63,
    },
    {
      id: 'hub-sp-pending',
      code: 'HUB-SP-PND',
      name: 'Hub SP Pending',
      city: 'São Paulo',
      state: 'SP',
      status: 'inactive',
      validationStatus: 'PENDENTE_VALIDACAO',
      latitude: -23.55,
      longitude: -46.63,
    },
  ]));
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [{ order_id: 'order-001', customer_state: 'SP' }],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  // Should only assign to the approved hub
  assert.equal(body.assignments[0].assigned_hub_id, 'hub-sp-approved');
});

test('assign-hubs-by-state: distribution summary is correct', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  const hubSp = {
    id: 'hub-sp-001',
    code: 'HUB-SP-001',
    name: 'Hub SP',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  };
  const hubMg = {
    id: 'hub-mg-001',
    code: 'HUB-MG-001',
    name: 'Hub MG',
    city: 'Belo Horizonte',
    state: 'MG',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -19.92,
    longitude: -43.94,
  };
  await writeFile(hubsFile, JSON.stringify([hubSp, hubMg]));
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [
        { order_id: 'order-sp-001', customer_state: 'SP' },
        { order_id: 'order-sp-002', customer_state: 'SP' },
        { order_id: 'order-mg-001', customer_state: 'MG' },
        { order_id: 'order-df-001', customer_state: 'DF' },
      ],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();

  // Distribution should have entries for SP and MG
  const spDist = body.distribution.filter((d) => d.state === 'SP');
  const mgDist = body.distribution.filter((d) => d.state === 'MG');
  assert.ok(spDist.length > 0);
  assert.ok(mgDist.length > 0);

  // Total orders in distribution should be 3 (SP: 2, MG: 1)
  const distTotal = body.distribution.reduce((sum, d) => sum + d.orders_count, 0);
  assert.equal(distTotal, 3);

  // Uncovered states should include DF
  const dfUncovered = body.uncovered_states.find((s) => s.state === 'DF');
  assert.ok(dfUncovered);
  assert.equal(dfUncovered.orders_count, 1);
});

test('assign-hubs-by-state: state_counts and hub_counts are returned', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  const hubSp = {
    id: 'hub-sp-001',
    code: 'HUB-SP-001',
    name: 'Hub SP',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  };
  const hubMg = {
    id: 'hub-mg-001',
    code: 'HUB-MG-001',
    name: 'Hub MG',
    city: 'Belo Horizonte',
    state: 'MG',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -19.92,
    longitude: -43.94,
  };
  await writeFile(hubsFile, JSON.stringify([hubSp, hubMg]));
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [
        { order_id: 'order-sp-001', customer_state: 'SP' },
        { order_id: 'order-sp-002', customer_state: 'SP' },
        { order_id: 'order-mg-001', customer_state: 'MG' },
        { order_id: 'order-df-001', customer_state: 'DF' },
      ],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();

  // state_counts should have SP:2, MG:1, DF:1
  assert.ok(Array.isArray(body.state_counts));
  const spCount = body.state_counts.find((s) => s.state === 'SP');
  const mgCount = body.state_counts.find((s) => s.state === 'MG');
  const dfCount = body.state_counts.find((s) => s.state === 'DF');
  assert.equal(spCount.orders_count, 2);
  assert.equal(mgCount.orders_count, 1);
  assert.equal(dfCount.orders_count, 1);

  // hub_counts should have hub-sp-001:2, hub-mg-001:1
  assert.ok(Array.isArray(body.hub_counts));
  const hubSpCount = body.hub_counts.find((h) => h.hub_id === 'hub-sp-001');
  const hubMgCount = body.hub_counts.find((h) => h.hub_id === 'hub-mg-001');
  assert.equal(hubSpCount.orders_count, 2);
  assert.equal(hubMgCount.orders_count, 1);
  // Percentage check
  assert.ok(hubSpCount.percentage > 0);
  assert.ok(hubMgCount.percentage > 0);
  const totalPct = body.hub_counts.reduce((sum, h) => sum + h.percentage, 0);
  assert.ok(Math.abs(totalPct - 75) < 0.1); // 3/4 = 75% have hubs, DF has none

  // reasons should include NO_HUB_FOR_STATE and UNCHANGED
  assert.ok(Array.isArray(body.reasons));
  const noHub = body.reasons.find((r) => r.reason === 'NO_HUB_FOR_STATE');
  assert.ok(noHub);
  assert.equal(noHub.count, 1);
});

test('assign-hubs-by-state: case insensitive customer_state normalization', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  const hubSp = {
    id: 'hub-sp-001',
    code: 'HUB-SP-001',
    name: 'Hub SP',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  };
  await writeFile(hubsFile, JSON.stringify([hubSp]));
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  // Lowercase state should be normalized to uppercase
  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [{ order_id: 'order-001', customer_state: 'sp' }],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.assignments[0].assigned_hub_id, 'hub-sp-001');
  assert.equal(body.assignments[0].customer_state, 'SP');
});

test('assign-hubs-by-state: report totals are consistent', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  const hubSp = {
    id: 'hub-sp-001',
    code: 'HUB-SP-001',
    name: 'Hub SP',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  };
  await writeFile(hubsFile, JSON.stringify([hubSp]));
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const orders = [];
  for (let i = 1; i <= 20; i++) {
    orders.push({ order_id: `order-${String(i).padStart(3, '0')}`, customer_state: 'SP' });
  }
  for (let i = 1; i <= 10; i++) {
    orders.push({ order_id: `order-df-${String(i).padStart(3, '0')}`, customer_state: 'DF' });
  }

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dry_run: true, orders }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();

  // total_analyzed = state_counts sum
  const stateSum = body.state_counts.reduce((s, c) => s + c.orders_count, 0);
  assert.equal(body.summary.total_analyzed, stateSum);

  // total_analyzed = assigned + unassigned
  const hubSum = body.hub_counts.reduce((s, c) => s + c.orders_count, 0);
  assert.equal(body.summary.total_analyzed, hubSum + body.summary.total_unassigned);

  // reasons sum = total_analyzed
  const reasonSum = body.reasons.reduce((s, r) => s + r.count, 0);
  assert.equal(reasonSum, body.summary.total_analyzed);
});

test('assign-hubs-by-state: multiple hubs per state — balanced distribution percentages', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-assign-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const journalFile = `${predictionsFile}.jsonl`;

  // 3 hubs in SP
  const hubs = [];
  for (let i = 1; i <= 3; i++) {
    hubs.push({
      id: `hub-sp-${String(i).padStart(3, '0')}`,
      code: `HUB-SP-${String(i).padStart(3, '0')}`,
      name: `Hub SP ${i}`,
      city: 'São Paulo',
      state: 'SP',
      status: 'active',
      validationStatus: 'APROVADO',
      latitude: -23.55,
      longitude: -46.63,
    });
  }
  await writeFile(hubsFile, JSON.stringify(hubs));
  await writeFile(ordersFile, '[]');

  const server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  // 300 orders to SP — should distribute roughly evenly across 3 hubs
  const orders = [];
  for (let i = 1; i <= 300; i++) {
    orders.push({ order_id: `order-${String(i).padStart(4, '0')}`, customer_state: 'SP' });
  }

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dry_run: true, orders }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();

  // All 300 orders should be assigned
  assert.equal(body.summary.total_unassigned, 0);
  assert.equal(body.summary.total_analyzed, 300);

  // Each hub should have roughly 100 orders (within ±15% tolerance for hash distribution)
  const counts = body.hub_counts.map((h) => h.orders_count).sort((a, b) => a - b);
  assert.equal(counts.length, 3);
  const minCount = counts[0];
  const maxCount = counts[2];
  // Max deviation should be reasonable for deterministic hash
  assert.ok(maxCount - minCount <= 30, `Distribution too uneven: ${counts.join(', ')}`);

  // Percentages should sum to ~100%
  const totalPct = body.hub_counts.reduce((s, h) => s + h.percentage, 0);
  assert.ok(Math.abs(totalPct - 100) < 0.1, `Percentages sum: ${totalPct}`);
});
