import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, unlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

test('order association validates a hub, persists it, and is returned by GET', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-orders-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const hubId = 'hub-stable-id-1';
  await writeFile(hubsFile, JSON.stringify([{
    id: hubId,
    code: 'HUB-01',
    name: 'Hub São Paulo',
    city: 'São Paulo',
    state: 'SP',
    status: 'active',
    validationStatus: 'APROVADO',
    latitude: -23.55,
    longitude: -46.63,
  }]));
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'legacy-order', createdAt: '2020-01-01T00:00:00.000Z' },
  ]));

  const app = await createApp({ hubsFile, ordersFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const importResponse = await fetch(`${baseUrl}/api/v1/orders/import`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ orders: [{ order_id: 'order-001' }, { order_id: 'legacy-order' }] }),
  });
  assert.equal(importResponse.status, 200);
  const imported = (await importResponse.json()).data;
  assert.equal(imported.find((order) => order.order_id === 'order-001').hub_id, null);
  assert.equal(imported.find((order) => order.order_id === 'legacy-order').hub_id, null);

  const invalidHubResponse = await fetch(`${baseUrl}/api/v1/orders/order-001/hub`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ hub_id: 'not-a-hub-id' }),
  });
  assert.equal(invalidHubResponse.status, 404);
  assert.equal((await invalidHubResponse.json()).error, 'HUB_NOT_FOUND');

  const linkResponse = await fetch(`${baseUrl}/api/v1/orders/order-001/hub`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ hub_id: hubId }),
  });
  assert.equal(linkResponse.status, 200);
  const linked = (await linkResponse.json()).data;
  assert.equal(linked.hub_id, hubId);
  assert.equal(linked.hub.code, 'HUB-01');

  const getLinked = await fetch(`${baseUrl}/api/v1/orders/order-001`);
  assert.equal(getLinked.status, 200);
  assert.equal((await getLinked.json()).data.hub_id, hubId);
  const storedLinked = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(storedLinked.find((order) => order.order_id === 'order-001').hub_id, hubId);

  const blockedDelete = await fetch(`${baseUrl}/api/v1/hubs/${hubId}`, {
    method: 'DELETE',
  });
  assert.equal(blockedDelete.status, 409);
  assert.equal((await blockedDelete.json()).error, 'HUB_IN_USE');
  const blockedBulkDelete = await fetch(`${baseUrl}/api/v1/hubs/bulk`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ids: [hubId] }),
  });
  assert.equal(blockedBulkDelete.status, 409);

  const getLegacy = await fetch(`${baseUrl}/api/v1/orders/legacy-order`);
  assert.equal((await getLegacy.json()).data.hub_id, null);

  // Re-importing a shipment without hub_id retains a previously explicit association.
  const reimport = await fetch(`${baseUrl}/api/v1/orders/import`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ orders: [{ order_id: 'order-001' }] }),
  });
  assert.equal((await reimport.json()).data[0].hub_id, hubId);

  const unlinkResponse = await fetch(`${baseUrl}/api/v1/orders/order-001/hub`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ hub_id: null }),
  });
  assert.equal((await unlinkResponse.json()).data.hub_id, null);

  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.find((order) => order.order_id === 'order-001').hub_id, null);
  assert.equal(stored.find((order) => order.order_id === 'legacy-order').hub_id, undefined);
});

test('order import rejects invalid and duplicate order identifiers atomically', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-orders-validation-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  await writeFile(hubsFile, '[]');
  const app = await createApp({ hubsFile, ordersFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  for (const orders of [
    [{ order_id: 'duplicate' }, { order_id: 'duplicate' }],
    [{ order_id: '   ' }],
  ]) {
    const response = await fetch(`${baseUrl}/api/v1/orders/import`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ orders }),
    });
    assert.equal(response.status, 422);
  }
  await assert.rejects(readFile(ordersFile, 'utf8'), { code: 'ENOENT' });
});

test('demo import assigns the selected hub only to unassociated orders and preserves existing hubs', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-demo-orders-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const demoHub = { id: 'demo-hub', code: 'DEMO', name: 'Hub demonstração', city: 'São Paulo', state: 'SP', status: 'active', validationStatus: 'APROVADO' };
  const existingHub = { id: 'existing-hub', code: 'EXISTING', name: 'Hub existente', city: 'Salvador', state: 'BA', status: 'active', validationStatus: 'APROVADO' };
  await writeFile(hubsFile, JSON.stringify([demoHub, existingHub]));
  await writeFile(ordersFile, JSON.stringify([
    { order_id: 'already-linked', hub_id: existingHub.id },
    { order_id: 'no-hub-yet', hub_id: null },
  ]));
  const app = await createApp({ hubsFile, ordersFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const response = await fetch(`${baseUrl}/api/v1/orders/import`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      default_hub_id: demoHub.id,
      orders: [
        { order_id: 'new-demo-order' },
        { order_id: 'no-hub-yet' },
        { order_id: 'already-linked' },
      ],
    }),
  });
  assert.equal(response.status, 200);
  const rows = (await response.json()).data;
  assert.equal(rows.find((row) => row.order_id === 'new-demo-order').hub_id, demoHub.id);
  assert.equal(rows.find((row) => row.order_id === 'new-demo-order').imported, true);
  assert.equal(rows.find((row) => row.order_id === 'new-demo-order').demo_hub_assigned, true);
  assert.equal(rows.find((row) => row.order_id === 'no-hub-yet').hub_id, demoHub.id);
  assert.equal(rows.find((row) => row.order_id === 'no-hub-yet').demo_hub_assigned, true);
  assert.equal(rows.find((row) => row.order_id === 'already-linked').hub_id, existingHub.id);
  assert.equal(rows.find((row) => row.order_id === 'already-linked').hub_preserved, true);

  const reimport = await fetch(`${baseUrl}/api/v1/orders/import`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ default_hub_id: demoHub.id, orders: [{ order_id: 'new-demo-order' }] }),
  });
  assert.equal((await reimport.json()).data[0].imported, false);
  const stored = JSON.parse(await readFile(ordersFile, 'utf8'));
  assert.equal(stored.find((row) => row.order_id === 'already-linked').hub_id, existingHub.id);
});

test('configured Olist dataset endpoint returns CSV and reports a missing dataset', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-olist-dataset-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const datasetFile = path.join(directory, 'olist.csv');
  await writeFile(hubsFile, '[]');
  await writeFile(datasetFile, 'order_id,seller_state\norder-1,SP\n');
  const app = await createApp({ hubsFile, olistDatasetFile: datasetFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const response = await fetch(`${baseUrl}/api/v1/datasets/olist`);
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /text\/csv/);
  assert.equal(await response.text(), 'order_id,seller_state\norder-1,SP\n');

  await unlink(datasetFile);
  const missing = await fetch(`${baseUrl}/api/v1/datasets/olist`);
  assert.equal(missing.status, 404);
  assert.equal((await missing.json()).error, 'OLIST_DATASET_NOT_FOUND');
});
