import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

test('GET /api/v1/orders returns empty list when no orders exist', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-orders-list-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, '[]');

  const app = await createApp({ hubsFile, ordersFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.data.length, 0);
  assert.equal(body.total, 0);
  assert.equal(body.page, 1);
  assert.equal(body.per_page, 50);
  assert.equal(body.total_pages, 1);
});

test('GET /api/v1/orders returns paginated orders with hub enrichment', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-orders-list-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const hubId = 'hub-test-1';
  await writeFile(hubsFile, JSON.stringify([{
    id: hubId,
    code: 'HUB-01',
    name: 'Hub Teste',
    city: 'Curitiba',
    state: 'PR',
    status: 'active',
    validationStatus: 'APROVADO',
  }]));
  const now = new Date().toISOString();
  const orders = [];
  for (let i = 0; i < 3; i++) {
    orders.push({
      order_id: `order-${i}`,
      hub_id: i === 0 ? hubId : null,
      source: 'olist',
      createdAt: now,
      updatedAt: now,
    });
  }
  await writeFile(ordersFile, JSON.stringify(orders));

  const app = await createApp({ hubsFile, ordersFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  // Full list
  {
    const res = await fetch(`${baseUrl}/api/v1/orders`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.total, 3);
    assert.equal(body.data.length, 3);
    assert.equal(body.page, 1);
    assert.equal(body.per_page, 50);
    // First order has hub enrichment
    const first = body.data.find((o) => o.order_id === 'order-0');
    assert.ok(first);
    assert.equal(first.hub_id, hubId);
    assert.equal(first.hub.code, 'HUB-01');
    assert.equal(first.hub.state, 'PR');
    assert.equal(first.source, 'olist');
    // Second order has no hub
    const second = body.data.find((o) => o.order_id === 'order-1');
    assert.ok(second);
    assert.equal(second.hub_id, null);
    assert.equal(second.hub, null);
  }

  // Pagination: per_page=2
  {
    const res = await fetch(`${baseUrl}/api/v1/orders?per_page=2`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.total, 3);
    assert.equal(body.data.length, 2);
    assert.equal(body.page, 1);
    assert.equal(body.per_page, 2);
    assert.equal(body.total_pages, 2);
  }

  // Page 2
  {
    const res = await fetch(`${baseUrl}/api/v1/orders?page=2&per_page=2`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.total, 3);
    assert.equal(body.data.length, 1);
    assert.equal(body.page, 2);
  }

  // Filter by hub_id
  {
    const res = await fetch(`${baseUrl}/api/v1/orders?hub_id=${hubId}`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.total, 1);
    assert.equal(body.data[0].order_id, 'order-0');
  }

  // Search by order_id
  {
    const res = await fetch(`${baseUrl}/api/v1/orders?q=order-1`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.total, 1);
    assert.equal(body.data[0].order_id, 'order-1');
  }
});

test('GET /api/v1/orders rejects invalid pagination parameters', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-orders-list-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, '[]');

  const app = await createApp({ hubsFile, ordersFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  // Invalid page
  {
    const res = await fetch(`${baseUrl}/api/v1/orders?page=0`);
    assert.equal(res.status, 422);
    const body = await res.json();
    assert.equal(body.error, 'INVALID_PAGE');
  }

  // Invalid per_page
  {
    const res = await fetch(`${baseUrl}/api/v1/orders?per_page=0`);
    assert.equal(res.status, 422);
    const body = await res.json();
    assert.equal(body.error, 'INVALID_PAGE');
  }

  // Non-numeric page
  {
    const res = await fetch(`${baseUrl}/api/v1/orders?page=abc`);
    assert.equal(res.status, 422);
    const body = await res.json();
    assert.equal(body.error, 'INVALID_PAGE');
  }

  // per_page exceeds max
  {
    const res = await fetch(`${baseUrl}/api/v1/orders?per_page=501`);
    assert.equal(res.status, 422);
    const body = await res.json();
    assert.equal(body.error, 'INVALID_PAGE');
  }

  // Invalid hub_id
  {
    const res = await fetch(`${baseUrl}/api/v1/orders?hub_id=`);
    assert.equal(res.status, 422);
    const body = await res.json();
    assert.equal(body.error, 'INVALID_HUB_ID');
  }
});

test('GET /api/v1/orders returns 500 on storage error', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-orders-list-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  await writeFile(hubsFile, '[]');
  // Write invalid JSON to trigger parse error
  await writeFile(ordersFile, '{invalid json');

  const app = await createApp({ hubsFile, ordersFile });
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const res = await fetch(`${baseUrl}/api/v1/orders`);
  assert.equal(res.status, 500);
  const body = await res.json();
  assert.equal(body.error, 'ORDER_STORAGE_ERROR');
});
