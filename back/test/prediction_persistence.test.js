import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';
import {
  create as createPrediction,
  findByOrderId,
  list as listPredictions,
  checkDb,
} from '../src/db/repositories/predictions.js';
import {
  create as createOrder,
  findById as findOrderById,
  checkDb as checkOrdersDb,
} from '../src/db/repositories/orders.js';

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

const mlResponse = {
  model_version: 'rf-olist-v1',
  source: 'olist',
  synthetic: false,
  delay_probability: 0.82,
  threshold: 0.4,
  predicted_late: true,
  warnings: ['Test warning'],
};

test('prediction persistence repository — checkDb returns boolean', async (t) => {
  const dbOk = await checkDb();
  assert.ok(typeof dbOk === 'boolean', 'checkDb deve retornar boolean');
});

test('prediction persistence repository — create and findByOrderId', async (t) => {
  const dbOk = await checkDb();
  if (!dbOk) {
    console.log('PostgreSQL indisponível; pulando teste de persistência.');
    return;
  }

  const prediction = {
    prediction_id: 'test-pred-001',
    order_id: 'test-order-persistence',
    hub_id: 'hub-test',
    delay_probability: 0.75,
    predicted_late: true,
    threshold: 0.4,
    model_version: 'test-v1',
    source: 'test',
    synthetic: false,
    warnings: ['Test'],
    predicted_at: new Date().toISOString(),
  };

  const created = await createPrediction(prediction);
  assert.ok(created, 'Previsão deve ser criada');
  assert.equal(created.order_id, 'test-order-persistence');

  const found = await findByOrderId('test-order-persistence');
  assert.ok(Array.isArray(found), 'findByOrderId deve retornar array');
  assert.ok(found.length >= 1, 'Deve encontrar pelo menos uma previsão');
  assert.equal(found[0].order_id, 'test-order-persistence');
});

test('prediction persistence repository — list with pagination', async (t) => {
  const dbOk = await checkDb();
  if (!dbOk) {
    console.log('PostgreSQL indisponível; pulando teste de listagem.');
    return;
  }

  const result = await listPredictions({ page: 1, perPage: 10 });
  assert.ok(result.data, 'list deve retornar data');
  assert.ok(typeof result.total === 'number', 'list deve retornar total');
  assert.ok(result.page, 'list deve retornar page');
  assert.ok(result.perPage, 'list deve retornar perPage');
});

test('orders repository — create and findById', async (t) => {
  const dbOk = await checkOrdersDb();
  if (!dbOk) {
    console.log('PostgreSQL indisponível; pulando teste de pedidos.');
    return;
  }

  const order = {
    order_id: 'test-order-find',
    origin_zip_code: '01001000',
    destination_zip_code: '01001000',
    purchase_at: '2018-01-10T10:00:00',
    dispatched_at: '2018-01-11T09:00:00',
    estimated_delivery_at: '2018-01-20T00:00:00',
    seller_state: 'SP',
    customer_state: 'SP',
    items_count: 2,
    sellers_count: 1,
    price: 100,
    freight_value: 15,
    source: 'test',
  };

  const created = await createOrder(order);
  assert.ok(created, 'Pedido deve ser criado');
  assert.equal(created.order_id, 'test-order-find');

  const found = await findOrderById('test-order-find');
  assert.ok(found, 'Pedido deve ser encontrado');
  assert.equal(found.order_id, 'test-order-find');
});

test('prediction endpoint persists with order_id via repository', async (t) => {
  // Create temporary directories for JSON fallback
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-pred-test-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');

  // Write hubs and orders JSON so the fallback works when DB is unavailable
  await writeFile(hubsFile, JSON.stringify([
    { id: 'hub-test', code: 'T-01', name: 'Hub Test', city: 'São Paulo', state: 'SP', status: 'active', validationStatus: 'APROVADO' },
  ]));
  await writeFile(ordersFile, JSON.stringify([
    {
      order_id: 'test-api-pred-order',
      hub_id: 'hub-test',
      origin_zip_code: '01001000',
      destination_zip_code: '01001000',
      purchase_at: '2018-01-10T10:00:00',
      dispatched_at: '2018-01-11T09:00:00',
      estimated_delivery_at: '2018-01-20T00:00:00',
      seller_state: 'SP',
      customer_state: 'BA',
      items_count: 1,
      sellers_count: 1,
      price: 350,
      freight_value: 35,
      source: 'test',
    },
  ]));

  // Also try to create in PostgreSQL if available
  const dbOk = await checkOrdersDb();
  if (dbOk) {
    try {
      await createOrder({
        order_id: 'test-api-pred-order',
        hub_id: 'hub-test',
        origin_zip_code: '01001000',
        destination_zip_code: '01001000',
        purchase_at: '2018-01-10T10:00:00',
        dispatched_at: '2018-01-11T09:00:00',
        estimated_delivery_at: '2018-01-20T00:00:00',
        seller_state: 'SP',
        customer_state: 'BA',
        items_count: 1,
        sellers_count: 1,
        price: 350,
        freight_value: 35,
        source: 'test',
      });
    } catch (e) {
      // Ignore if DB insert fails
    }
  }

  // Mock ML server
  const mlServer = createServer((req, res) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => (body += chunk));
    req.on('end', () => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(mlResponse));
    });
  }).listen(0);
  await new Promise((resolve) => mlServer.once('listening', resolve));

  const app = await createApp({
    mlUrl: `http://127.0.0.1:${mlServer.address().port}`,
    timeoutMs: 5000,
    hubsFile,
    ordersFile,
    predictionsFile,
  });
  const apiServer = app.listen(0);
  await new Promise((resolve) => apiServer.once('listening', resolve));

  t.after(async () => {
    await Promise.all([mlServer, apiServer].map((server) =>
      new Promise((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      ),
    ));
  });

  const baseUrl = `http://127.0.0.1:${apiServer.address().port}`;

  // Call prediction endpoint with order_id
  const response = await fetch(
    `${baseUrl}/api/v1/predictions?order_id=test-api-pred-order`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(shipment),
    },
  );

  const result = await response.json();
  assert.equal(response.status, 200, `Expected 200, got ${response.status}: ${JSON.stringify(result)}`);
  assert.equal(result.persisted, true, 'Previsão deve ser persistida');
  assert.equal(result.delay_probability, 0.82);
  assert.equal(result.predicted_late, true);
  assert.ok(result.prediction_id, 'Deve ter prediction_id');
});

test('prediction endpoint without order_id returns ML response', async (t) => {
  const mlServer = createServer((req, res) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => (body += chunk));
    req.on('end', () => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(mlResponse));
    });
  }).listen(0);
  await new Promise((resolve) => mlServer.once('listening', resolve));

  const app = await createApp({
    mlUrl: `http://127.0.0.1:${mlServer.address().port}`,
    timeoutMs: 5000,
  });
  const apiServer = app.listen(0);
  await new Promise((resolve) => apiServer.once('listening', resolve));

  t.after(async () => {
    await Promise.all([mlServer, apiServer].map((server) =>
      new Promise((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      ),
    ));
  });

  const baseUrl = `http://127.0.0.1:${apiServer.address().port}`;

  const response = await fetch(`${baseUrl}/api/v1/predictions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(shipment),
  });

  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.delay_probability, 0.82);
  assert.equal(result.predicted_late, true);
});

test('prediction endpoint returns 404 for unknown order_id', async (t) => {
  const mlServer = createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(mlResponse));
  }).listen(0);
  await new Promise((resolve) => mlServer.once('listening', resolve));

  const app = await createApp({
    mlUrl: `http://127.0.0.1:${mlServer.address().port}`,
    timeoutMs: 5000,
  });
  const apiServer = app.listen(0);
  await new Promise((resolve) => apiServer.once('listening', resolve));

  t.after(async () => {
    await Promise.all([mlServer, apiServer].map((server) =>
      new Promise((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      ),
    ));
  });

  const baseUrl = `http://127.0.0.1:${apiServer.address().port}`;

  const response = await fetch(
    `${baseUrl}/api/v1/predictions?order_id=nonexistent-order-12345`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(shipment),
    },
  );

  assert.equal(response.status, 404);
});
