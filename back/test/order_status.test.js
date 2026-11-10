import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';
import { getKnex } from '../src/db/knex.js';
import { orderStatus } from '../src/order-status.js';

after(async () => getKnex().destroy());

async function harness(t, initial = []) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-order-status-'));
  const ordersFile = path.join(directory, 'orders.json');
  const hubsFile = path.join(directory, 'hubs.json');
  await writeFile(ordersFile, JSON.stringify(initial));
  await writeFile(hubsFile, '[]');
  const app = await createApp({ ordersFile, hubsFile });
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  });
  const base = `http://127.0.0.1:${server.address().port}/api/v1/orders`;
  const post = (route, body) => fetch(`${base}${route}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  return { base, post, ordersFile };
}

test('legacy import persists status, defaults to unknown and preserves status on reimport', async (t) => {
  const { base, post, ordersFile } = await harness(t);
  const orders = [
    { order_id: 'pending' },
    { order_id: 'shipped', status: 'shipped' },
    { order_id: 'delivered', status: 'delivered' },
    { order_id: 'canceled', status: 'canceled' },
    { order_id: 'fifth', status: 'pending' },
  ];
  const response = await post('/import', { orders });
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).data.map((o) => o.status),
    ['unknown', 'shipped', 'delivered', 'canceled', 'pending']);
  let saved = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(saved.length, 5);
  assert.equal(saved.find((o) => o.order_id === 'delivered').status, 'delivered');
  const repeated = await post('/import', { orders: [{ order_id: 'delivered', status: 'pending' }] });
  assert.equal((await repeated.json()).data[0].status, 'delivered');
  const detail = await fetch(`${base}/delivered`);
  assert.equal((await detail.json()).data.status, 'delivered');
  saved = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(saved.length, 5);
});

test('invalid status rejects the entire JSON import before persistence', async (t) => {
  const { post, ordersFile } = await harness(t);
  const response = await post('/import', {
    orders: [{ order_id: 'valid' }, { order_id: 'invalid', status: 'invalid-status' }],
  });
  assert.equal(response.status, 422);
  assert.equal((await response.json()).error, 'INVALID_STATUS');
  assert.deepEqual(JSON.parse(await readFile(ordersFile, 'utf8')), []);
});

test('CSV import persists explicit/default status and returns the promised date in list/detail', async (t) => {
  const { base, post, ordersFile } = await harness(t);
  const header = 'order_id,origin_zip_code,destination_zip_code,purchase_at,dispatched_at,estimated_delivery_at,seller_state,customer_state,items_count,sellers_count,price,freight_value,status';
  const row = (id, status) => `${id},01001000,12245000,2026-10-01T10:00:00,2026-10-02T10:00:00,2026-10-09T00:00:00,SP,SP,1,1,100,20,${status}`;
  const response = await post('/import-csv', {
    csv: [header, row('csv-default', ''), row('csv-delivered', 'delivered'), row('csv-invalid', 'invalid-status')].join('\n'),
  });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.imported, 2);
  assert.equal(result.failed, 1);
  assert.match(result.data.failed[0].reason, /status inválido/);
  const saved = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(saved.find((o) => o.order_id === 'csv-default').status, 'shipped');
  assert.equal(saved.find((o) => o.order_id === 'csv-delivered').status, 'delivered');
  const list = await (await fetch(base)).json();
  assert.equal(list.total, 2);
  const item = list.data.find((o) => o.order_id === 'csv-default');
  assert.equal(item.status, 'shipped');
  assert.equal(item.estimated_delivery_at, '2026-10-09T00:00:00');
  const detail = await (await fetch(`${base}/csv-default`)).json();
  assert.equal(detail.data.status, item.status);
  assert.equal(detail.data.estimated_delivery_at, item.estimated_delivery_at);
});

test('legacy records use only dispatch evidence, never the promised date to infer delivery', () => {
  assert.equal(orderStatus({}), 'unknown');
  assert.equal(orderStatus({ dispatched_at: '2018-01-01' }), 'shipped');
  assert.equal(orderStatus({ estimated_delivery_at: '2018-01-01' }), 'unknown');
  assert.equal(orderStatus({ status: 'canceled', dispatched_at: '2018-01-01' }), 'canceled');
});
