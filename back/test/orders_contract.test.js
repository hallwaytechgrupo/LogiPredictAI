import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

async function serve(t, orders = [], predictions = []) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-orders-contract-'));
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const hubsFile = path.join(directory, 'hubs.json');
  await writeFile(ordersFile, JSON.stringify(orders));
  await writeFile(predictionsFile, JSON.stringify(predictions));
  await writeFile(hubsFile, '[]');
  const app = await createApp({ ordersFile, predictionsFile, hubsFile });
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  });
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  return { baseUrl, ordersFile };
}

function post(baseUrl, route, body) {
  return fetch(`${baseUrl}${route}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
}

test('five demo orders preserve statuses, deadlines and model fields through import, listing and details', async (t) => {
  const { baseUrl, ordersFile } = await serve(t);
  const csv = await readFile(new URL('../data/exemplos_fe04_be02.csv', import.meta.url), 'utf8');
  const imported = await post(baseUrl, '/api/v1/orders/import-csv', { csv });
  assert.equal(imported.status, 200);
  assert.equal((await imported.json()).imported, 5);
  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.ok(stored.every((order) => order.origin_zip_code === '01001000'));
  assert.equal(stored.find((order) => order.order_id === 'DEMO-FE04-002').destination_zip_code, '01001000');
  const listed = await (await fetch(`${baseUrl}/api/v1/orders?source=operational`)).json();
  assert.equal(listed.total, 5);
  assert.equal(listed.data.length, 5);
  for (const order of listed.data) {
    const original = stored.find((item) => item.order_id === order.order_id);
    const detail = await (await fetch(`${baseUrl}/api/v1/orders/${order.order_id}`)).json();
    for (const field of ['status', 'estimated_delivery_at', 'destination_zip_code', 'total_weight_g', 'total_volume_cm3', 'sellers_count']) {
      assert.equal(order[field], original[field], field);
      assert.equal(detail.data[field], original[field], field);
    }
  }
  const repeated = await post(baseUrl, '/api/v1/orders/import-csv', { csv });
  assert.equal((await repeated.json()).ignored, 5);
  assert.equal(JSON.parse(await readFile(ordersFile, 'utf8')).length, 5);
});

test('legacy orders get an explicit unknown status and numeric strings are serialized as numbers', async (t) => {
  const { baseUrl } = await serve(t, [{
    order_id: 'legacy', createdAt: '2026-11-01T10:00:00Z',
    total_weight_g: '500.00', total_volume_cm3: '1200', price: '89.90', freight_value: '15.00',
    items_count: 1, sellers_count: 1,
  }]);
  const listed = await (await fetch(`${baseUrl}/api/v1/orders`)).json();
  const detail = await (await fetch(`${baseUrl}/api/v1/orders/legacy`)).json();
  for (const order of [listed.data[0], detail.data]) {
    assert.equal(order.status, 'unknown');
    assert.equal(order.total_weight_g, 500);
    assert.equal(order.total_volume_cm3, 1200);
    assert.equal(order.price, 89.9);
    assert.equal(order.created_at, '2026-11-01T10:00:00Z');
  }
});

test('semicolon CSV accepts decimal commas and quoted separators', async (t) => {
  const { baseUrl } = await serve(t);
  const template = await readFile(new URL('../data/exemplos_fe04_be02.csv', import.meta.url), 'utf8');
  const [header, first] = template.trim().split(/\r?\n/);
  const csv = `\uFEFF${header};observacao\n${first.replace(';89.90;', ';89,90;')};"São Paulo; SP, Brasil"`;
  const result = await (await post(baseUrl, '/api/v1/orders/import-csv', { csv })).json();
  assert.equal(result.imported, 1);
  assert.equal(result.failed, 0);
  const detail = await (await fetch(`${baseUrl}/api/v1/orders/DEMO-FE04-001`)).json();
  assert.equal(detail.data.price, 89.9);
  assert.equal(detail.data.total_weight_g, 500);
});

test('invalid statuses and optional measures are rejected per row and order_status alias is accepted', async (t) => {
  const { baseUrl, ordersFile } = await serve(t);
  const csv = await readFile(new URL('../data/exemplos_fe04_be02.csv', import.meta.url), 'utf8');
  const invalidStatus = csv.replace('shipped', 'invalid-status');
  const result = await (await post(baseUrl, '/api/v1/orders/import-csv', { csv: invalidStatus })).json();
  assert.equal(result.failed, 1);
  assert.equal(result.imported, 4);
  assert.match(result.data.failed[0].reason, /status inválido/);
  const [header, first] = csv.trim().split(/\r?\n/);
  const invalidWeight = `${header}\n${first.replace('DEMO-FE04-001', 'negative-weight').replace(';500;', ';-500;')}`;
  const weightResult = await (await post(baseUrl, '/api/v1/orders/import-csv', { csv: invalidWeight })).json();
  assert.equal(weightResult.failed, 1);
  const alias = `${header.replace(';status', ';order_status')}\n${first.replace('DEMO-FE04-001', 'alias-status')}`;
  assert.equal((await (await post(baseUrl, '/api/v1/orders/import-csv', { csv: alias })).json()).imported, 1);
  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.find((order) => order.order_id === 'alias-status').status, 'shipped');
});

test('summary counts distinct operational orders with persisted predictions', async (t) => {
  const { baseUrl } = await serve(t, [
    { order_id: 'one', source: 'operational', hub_id: 'hub' },
    { order_id: 'two', source: 'operational' },
    { order_id: 'olist', source: 'olist' },
  ], [{ order_id: 'one' }, { order_id: 'one' }, { order_id: 'olist' }]);
  const result = await (await fetch(`${baseUrl}/api/v1/orders/summary`)).json();
  assert.deepEqual(result.data, { total: 2, withHub: 1, withoutHub: 1, withPrediction: 1 });
});

test('concurrent imports preserve every order and status', async (t) => {
  const { baseUrl, ordersFile } = await serve(t);
  const responses = await Promise.all(['one', 'two', 'three'].map((order_id) =>
    post(baseUrl, '/api/v1/orders/import', { orders: [{ order_id, status: 'processing' }] }),
  ));
  assert.ok(responses.every((response) => response.ok));
  const orders = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(orders.length, 3);
  assert.ok(orders.every((order) => order.status === 'processing'));
});

test('import failure preserves an existing corrupt storage file', async (t) => {
  const { baseUrl, ordersFile } = await serve(t);
  await writeFile(ordersFile, '{');
  const response = await post(baseUrl, '/api/v1/orders/import', { orders: [{ order_id: 'one' }] });
  assert.equal(response.status, 500);
  assert.equal(await readFile(ordersFile, 'utf8'), '{');
});
