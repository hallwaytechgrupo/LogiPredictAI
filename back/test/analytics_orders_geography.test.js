import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

async function makeHarness(t, { ordersCsv, customersCsv, geolocationCsv } = {}) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-geo-'));
  const hubsFile = path.join(directory, 'hubs.json');
  const ordersFile = path.join(directory, 'orders.json');
  const predictionsFile = path.join(directory, 'predictions.json');
  const olistOrdersFile = path.join(directory, 'olist_orders_dataset.csv');
  const olistCustomersFile = path.join(directory, 'olist_customers_dataset.csv');
  const geolocationFile = path.join(directory, 'olist_geolocation_dataset.csv');

  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, '[]');
  await writeFile(predictionsFile, '[]');

  if (ordersCsv) await writeFile(olistOrdersFile, ordersCsv, { encoding: 'utf8' });
  if (customersCsv) await writeFile(olistCustomersFile, customersCsv, { encoding: 'utf8' });
  if (geolocationCsv) await writeFile(geolocationFile, geolocationCsv, { encoding: 'utf8' });

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

  const apiApp = await createApp({
    mlUrl: `http://127.0.0.1:${mlServer.address().port}`,
    timeoutMs: 1000,
    hubsFile,
    ordersFile,
    predictionsFile,
    olistOrdersFile,
    olistCustomersFile,
    geolocationFile,
  });
  const apiServer = apiApp.listen(0);
  await new Promise((resolve) => apiServer.once('listening', resolve));

  const baseUrl = `http://127.0.0.1:${apiServer.address().port}`;
  t.after(async () => {
    await Promise.all([mlServer, apiServer].map((server) =>
      new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve())),
    ));
    await rm(directory, { recursive: true, force: true });
  });
  return { baseUrl };
}

const ordersHeader = '"order_id","customer_id","order_status","order_purchase_timestamp","order_approved_at","order_delivered_carrier_date","order_delivered_customer_date","order_estimated_delivery_date"';
const customersHeader = '"customer_id","customer_unique_id","customer_zip_code_prefix","customer_city","customer_state"';
const geolocationHeader = '"geolocation_zip_code_prefix","geolocation_lat","geolocation_lng","geolocation_city","geolocation_state"';

function orderRow(id, customerId, delivered, estimated) {
  return `"${id}","${customerId}",delivered,2018-01-01 10:00:00,2018-01-01 11:00:00,2018-01-02 10:00:00,${delivered},${estimated}`;
}
function customerRow(id, zip, city, state) {
  return `"${id}","unique-${id}","${zip}","${city}","${state}"`;
}
function geoRow(zip, lat, lng, city, state) {
  return `"${zip}","${lat}","${lng}","${city}","${state}"`;
}

test('orders-geography — delay rate calculation', async (t) => {
  // 2 orders: 1 delayed (delivered > estimated), 1 on time
  const ordersCsv = [
    ordersHeader,
    orderRow('order-1', 'cust-1', '2018-01-20 10:00:00', '2018-01-15 00:00:00'), // delayed
    orderRow('order-2', 'cust-2', '2018-01-10 10:00:00', '2018-01-15 00:00:00'), // on time
  ].join('\n');
  const customersCsv = [
    customersHeader,
    customerRow('cust-1', '12345', 'sao paulo', 'SP'),
    customerRow('cust-2', '12346', 'sao paulo', 'SP'),
  ].join('\n');
  const geolocationCsv = [
    geolocationHeader,
    geoRow('12345', '-23.55', '-46.63', 'sao paulo', 'SP'),
    geoRow('12346', '-23.56', '-46.64', 'sao paulo', 'SP'),
  ].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.total, 1);
  const locality = body.data[0];
  assert.equal(locality.city, 'sao paulo');
  assert.equal(locality.state, 'SP');
  assert.equal(locality.total_orders, 2);
  assert.equal(locality.orders_with_valid_dates, 2);
  assert.equal(locality.delayed_orders, 1);
  assert.equal(locality.delay_rate, 50);
  assert.equal(locality.risk_level, 'muito_alto');
});

test('orders-geography — risk classification thresholds', async (t) => {
  // Create 4 cities with different delay rates
  const orders = [
    // City A: 0% delay (baixo)
    orderRow('order-a1', 'cust-a1', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    // City B: 10% delay (baixo) — 1 delayed out of 10
    orderRow('order-b1', 'cust-b1', '2018-01-20 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-b2', 'cust-b2', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-b3', 'cust-b3', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-b4', 'cust-b4', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-b5', 'cust-b5', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-b6', 'cust-b6', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-b7', 'cust-b7', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-b8', 'cust-b8', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-b9', 'cust-b9', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-b10', 'cust-b10', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    // City C: 20% delay (medio) — 1 delayed out of 5
    orderRow('order-c1', 'cust-c1', '2018-01-20 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-c2', 'cust-c2', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-c3', 'cust-c3', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-c4', 'cust-c4', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-c5', 'cust-c5', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    // City D: 40% delay (muito_alto) — 2 delayed out of 5
    orderRow('order-d1', 'cust-d1', '2018-01-20 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-d2', 'cust-d2', '2018-01-20 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-d3', 'cust-d3', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-d4', 'cust-d4', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-d5', 'cust-d5', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
  ];
  const ordersCsv = [ordersHeader, ...orders].join('\n');

  const customers = [
    customerRow('cust-a1', '11111', 'city-a', 'SP'),
    customerRow('cust-b1', '11112', 'city-b', 'SP'),
    customerRow('cust-b2', '11113', 'city-b', 'SP'),
    customerRow('cust-b3', '11114', 'city-b', 'SP'),
    customerRow('cust-b4', '11115', 'city-b', 'SP'),
    customerRow('cust-b5', '11116', 'city-b', 'SP'),
    customerRow('cust-b6', '11117', 'city-b', 'SP'),
    customerRow('cust-b7', '11118', 'city-b', 'SP'),
    customerRow('cust-b8', '11119', 'city-b', 'SP'),
    customerRow('cust-b9', '11120', 'city-b', 'SP'),
    customerRow('cust-b10', '11121', 'city-b', 'SP'),
    customerRow('cust-c1', '11122', 'city-c', 'SP'),
    customerRow('cust-c2', '11123', 'city-c', 'SP'),
    customerRow('cust-c3', '11124', 'city-c', 'SP'),
    customerRow('cust-c4', '11125', 'city-c', 'SP'),
    customerRow('cust-c5', '11126', 'city-c', 'SP'),
    customerRow('cust-d1', '11127', 'city-d', 'SP'),
    customerRow('cust-d2', '11128', 'city-d', 'SP'),
    customerRow('cust-d3', '11129', 'city-d', 'SP'),
    customerRow('cust-d4', '11130', 'city-d', 'SP'),
    customerRow('cust-d5', '11131', 'city-d', 'SP'),
  ];
  const customersCsv = [customersHeader, ...customers].join('\n');

  const geos = [
    geoRow('11111', '-23.0', '-46.0', 'city-a', 'SP'),
    geoRow('11112', '-23.1', '-46.1', 'city-b', 'SP'),
    geoRow('11113', '-23.2', '-46.2', 'city-b', 'SP'),
    geoRow('11114', '-23.3', '-46.3', 'city-b', 'SP'),
    geoRow('11115', '-23.4', '-46.4', 'city-b', 'SP'),
    geoRow('11116', '-23.5', '-46.5', 'city-b', 'SP'),
    geoRow('11117', '-23.6', '-46.6', 'city-b', 'SP'),
    geoRow('11118', '-23.7', '-46.7', 'city-b', 'SP'),
    geoRow('11119', '-23.8', '-46.8', 'city-b', 'SP'),
    geoRow('11120', '-23.9', '-46.9', 'city-b', 'SP'),
    geoRow('11121', '-24.0', '-47.0', 'city-b', 'SP'),
    geoRow('11122', '-24.1', '-47.1', 'city-c', 'SP'),
    geoRow('11123', '-24.2', '-47.2', 'city-c', 'SP'),
    geoRow('11124', '-24.3', '-47.3', 'city-c', 'SP'),
    geoRow('11125', '-24.4', '-47.4', 'city-c', 'SP'),
    geoRow('11126', '-24.5', '-47.5', 'city-c', 'SP'),
    geoRow('11127', '-24.6', '-47.6', 'city-d', 'SP'),
    geoRow('11128', '-24.7', '-47.7', 'city-d', 'SP'),
    geoRow('11129', '-24.8', '-47.8', 'city-d', 'SP'),
    geoRow('11130', '-24.9', '-47.9', 'city-d', 'SP'),
    geoRow('11131', '-25.0', '-48.0', 'city-d', 'SP'),
  ];
  const geolocationCsv = [geolocationHeader, ...geos].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography`);
  assert.equal(res.status, 200);
  const body = await res.json();

  const byCity = {};
  for (const item of body.data) byCity[item.city] = item;

  assert.equal(byCity['city-a'].risk_level, 'baixo', 'City A should be baixo (0%)');
  assert.equal(byCity['city-b'].risk_level, 'baixo', 'City B should be baixo (10%)');
  assert.equal(byCity['city-c'].risk_level, 'medio', 'City C should be medio (20%)');
  assert.equal(byCity['city-d'].risk_level, 'muito_alto', 'City D should be muito_alto (40%)');
});

test('orders-geography — orders without delivery date excluded from delay calc', async (t) => {
  const ordersCsv = [
    ordersHeader,
    // Delivered on time
    orderRow('order-1', 'cust-1', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    // No delivery date
    orderRow('order-2', 'cust-2', '', '2018-01-15 00:00:00'),
  ].join('\n');
  const customersCsv = [
    customersHeader,
    customerRow('cust-1', '12345', 'sao paulo', 'SP'),
    customerRow('cust-2', '12346', 'sao paulo', 'SP'),
  ].join('\n');
  const geolocationCsv = [
    geolocationHeader,
    geoRow('12345', '-23.55', '-46.63', 'sao paulo', 'SP'),
    geoRow('12346', '-23.56', '-46.64', 'sao paulo', 'SP'),
  ].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography`);
  assert.equal(res.status, 200);
  const body = await res.json();
  const locality = body.data[0];
  assert.equal(locality.total_orders, 2);
  assert.equal(locality.orders_with_valid_dates, 1);
  assert.equal(locality.delayed_orders, 0);
  assert.equal(locality.orders_without_delivery_date, 1);
  assert.equal(locality.delay_rate, 0);
  assert.equal(locality.risk_level, 'baixo');
});

test('orders-geography — no duplication after joins', async (t) => {
  // Same customer has 2 orders — each counted once
  const ordersCsv = [
    ordersHeader,
    orderRow('order-1', 'cust-1', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-2', 'cust-1', '2018-01-12 10:00:00', '2018-01-15 00:00:00'),
  ].join('\n');
  const customersCsv = [
    customersHeader,
    customerRow('cust-1', '12345', 'sao paulo', 'SP'),
  ].join('\n');
  const geolocationCsv = [
    geolocationHeader,
    geoRow('12345', '-23.55', '-46.63', 'sao paulo', 'SP'),
  ].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography`);
  assert.equal(res.status, 200);
  const body = await res.json();
  const locality = body.data[0];
  assert.equal(locality.total_orders, 2, 'Each order counted once');
  assert.equal(locality.orders_with_valid_dates, 2);
});

test('orders-geography — aggregation by city and state', async (t) => {
  const ordersCsv = [
    ordersHeader,
    orderRow('order-1', 'cust-1', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-2', 'cust-2', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-3', 'cust-3', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
  ].join('\n');
  const customersCsv = [
    customersHeader,
    customerRow('cust-1', '12345', 'sao paulo', 'SP'),
    customerRow('cust-2', '12346', 'sao paulo', 'SP'),
    customerRow('cust-3', '22222', 'rio de janeiro', 'RJ'),
  ].join('\n');
  const geolocationCsv = [
    geolocationHeader,
    geoRow('12345', '-23.55', '-46.63', 'sao paulo', 'SP'),
    geoRow('12346', '-23.56', '-46.64', 'sao paulo', 'SP'),
    geoRow('22222', '-22.91', '-43.17', 'rio de janeiro', 'RJ'),
  ].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.total, 2, 'Two cities');

  const sp = body.data.find((d) => d.city === 'sao paulo');
  const rj = body.data.find((d) => d.city === 'rio de janeiro');
  assert.equal(sp.total_orders, 2);
  assert.equal(rj.total_orders, 1);
});

test('orders-geography — state filter', async (t) => {
  const ordersCsv = [
    ordersHeader,
    orderRow('order-1', 'cust-1', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-2', 'cust-2', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
  ].join('\n');
  const customersCsv = [
    customersHeader,
    customerRow('cust-1', '12345', 'sao paulo', 'SP'),
    customerRow('cust-2', '22222', 'rio de janeiro', 'RJ'),
  ].join('\n');
  const geolocationCsv = [
    geolocationHeader,
    geoRow('12345', '-23.55', '-46.63', 'sao paulo', 'SP'),
    geoRow('22222', '-22.91', '-43.17', 'rio de janeiro', 'RJ'),
  ].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography?state=SP`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.total, 1);
  assert.equal(body.data[0].state, 'SP');
  assert.equal(body.filters.state, 'SP');
});

test('orders-geography — response structure', async (t) => {
  const ordersCsv = [
    ordersHeader,
    orderRow('order-1', 'cust-1', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
  ].join('\n');
  const customersCsv = [
    customersHeader,
    customerRow('cust-1', '12345', 'sao paulo', 'SP'),
  ].join('\n');
  const geolocationCsv = [
    geolocationHeader,
    geoRow('12345', '-23.55', '-46.63', 'sao paulo', 'SP'),
  ].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.ok(Array.isArray(body.data));
  assert.ok(typeof body.total === 'number');
  assert.ok(typeof body.filters === 'object');

  const record = body.data[0];
  assert.ok(typeof record.city === 'string');
  assert.ok(typeof record.state === 'string');
  assert.ok(typeof record.total_orders === 'number');
  assert.ok(typeof record.orders_with_valid_dates === 'number');
  assert.ok(typeof record.delayed_orders === 'number');
  assert.ok(typeof record.orders_without_delivery_date === 'number');
  assert.ok(typeof record.delay_rate === 'number');
  assert.ok(typeof record.risk_level === 'string');
  assert.ok(typeof record.latitude === 'number');
  assert.ok(typeof record.longitude === 'number');
});

test('orders-geography — missing geolocation excluded', async (t) => {
  const ordersCsv = [
    ordersHeader,
    orderRow('order-1', 'cust-1', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-2', 'cust-2', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
  ].join('\n');
  const customersCsv = [
    customersHeader,
    customerRow('cust-1', '12345', 'sao paulo', 'SP'),
    customerRow('cust-2', '99999', 'unknown city', 'SP'),
  ].join('\n');
  const geolocationCsv = [
    geolocationHeader,
    geoRow('12345', '-23.55', '-46.63', 'sao paulo', 'SP'),
    // No geolocation for 99999
  ].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.total, 1, 'Only the city with geolocation is returned');
  assert.equal(body.data[0].total_orders, 1);
});

test('orders-geography — sem_dados classification', async (t) => {
  // Orders with no valid dates at all — all without delivery date
  const ordersCsv = [
    ordersHeader,
    orderRow('order-1', 'cust-1', '', '2018-01-15 00:00:00'),
    orderRow('order-2', 'cust-2', '', '2018-01-15 00:00:00'),
  ].join('\n');
  const customersCsv = [
    customersHeader,
    customerRow('cust-1', '12345', 'sao paulo', 'SP'),
    customerRow('cust-2', '12346', 'sao paulo', 'SP'),
  ].join('\n');
  const geolocationCsv = [
    geolocationHeader,
    geoRow('12345', '-23.55', '-46.63', 'sao paulo', 'SP'),
    geoRow('12346', '-23.56', '-46.64', 'sao paulo', 'SP'),
  ].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography`);
  assert.equal(res.status, 200);
  const body = await res.json();
  const locality = body.data[0];
  assert.equal(locality.risk_level, 'sem_dados');
  assert.equal(locality.orders_with_valid_dates, 0);
  assert.equal(locality.orders_without_delivery_date, 2);
});

test('orders-geography/regions — returns all 5 regions', async (t) => {
  const ordersCsv = [
    ordersHeader,
    orderRow('order-1', 'cust-1', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
  ].join('\n');
  const customersCsv = [
    customersHeader,
    customerRow('cust-1', '12345', 'sao paulo', 'SP'),
  ].join('\n');
  const geolocationCsv = [
    geolocationHeader,
    geoRow('12345', '-23.55', '-46.63', 'sao paulo', 'SP'),
  ].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography/regions`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.total, 5, 'Always returns all 5 regions');
  const regions = body.data.map((r) => r.region);
  assert.ok(regions.includes('Norte'));
  assert.ok(regions.includes('Nordeste'));
  assert.ok(regions.includes('Centro-Oeste'));
  assert.ok(regions.includes('Sudeste'));
  assert.ok(regions.includes('Sul'));
});

test('orders-geography/regions — risk classification thresholds', async (t) => {
  // Build orders across multiple states/regions with controlled delay rates
  const orders = [];
  const customers = [];
  const geos = [];

  // Norte (AM): 5% delay → baixo — 1 delayed out of 20
  for (let i = 0; i < 20; i++) {
    const id = `n-${i}`;
    const delivered = i === 0 ? '2018-01-20 10:00:00' : '2018-01-10 10:00:00';
    orders.push(orderRow(id, `cn-${i}`, delivered, '2018-01-15 00:00:00'));
    customers.push(customerRow(`cn-${i}`, `1${String(i).padStart(4, '0')}`, 'manaus', 'AM'));
    geos.push(geoRow(`1${String(i).padStart(4, '0')}`, '-3.1', '-60.0', 'manaus', 'AM'));
  }

  // Nordeste (BA): 15% delay → medio — 3 delayed out of 20
  for (let i = 0; i < 20; i++) {
    const id = `ne-${i}`;
    const delivered = i < 3 ? '2018-01-20 10:00:00' : '2018-01-10 10:00:00';
    orders.push(orderRow(id, `cne-${i}`, delivered, '2018-01-15 00:00:00'));
    customers.push(customerRow(`cne-${i}`, `2${String(i).padStart(4, '0')}`, 'salvador', 'BA'));
    geos.push(geoRow(`2${String(i).padStart(4, '0')}`, '-12.97', '-38.5', 'salvador', 'BA'));
  }

  // Centro-Oeste (DF): 2% delay → baixo — 1 delayed out of 50
  for (let i = 0; i < 50; i++) {
    const id = `co-${i}`;
    const delivered = i === 0 ? '2018-01-20 10:00:00' : '2018-01-10 10:00:00';
    orders.push(orderRow(id, `cco-${i}`, delivered, '2018-01-15 00:00:00'));
    customers.push(customerRow(`cco-${i}`, `3${String(i).padStart(4, '0')}`, 'brasilia', 'DF'));
    geos.push(geoRow(`3${String(i).padStart(4, '0')}`, '-15.79', '-47.88', 'brasilia', 'DF'));
  }

  // Sudeste (SP): 0% delay → baixo — 0 delayed out of 10
  for (let i = 0; i < 10; i++) {
    const id = `se-${i}`;
    orders.push(orderRow(id, `cse-${i}`, '2018-01-10 10:00:00', '2018-01-15 00:00:00'));
    customers.push(customerRow(`cse-${i}`, `4${String(i).padStart(4, '0')}`, 'sao paulo', 'SP'));
    geos.push(geoRow(`4${String(i).padStart(4, '0')}`, '-23.55', '-46.63', 'sao paulo', 'SP'));
  }

  // Sul (PR): 25% delay → alto — 5 delayed out of 20
  for (let i = 0; i < 20; i++) {
    const id = `s-${i}`;
    const delivered = i < 5 ? '2018-01-20 10:00:00' : '2018-01-10 10:00:00';
    orders.push(orderRow(id, `cs-${i}`, delivered, '2018-01-15 00:00:00'));
    customers.push(customerRow(`cs-${i}`, `5${String(i).padStart(4, '0')}`, 'curitiba', 'PR'));
    geos.push(geoRow(`5${String(i).padStart(4, '0')}`, '-25.42', '-49.27', 'curitiba', 'PR'));
  }

  const ordersCsv = [ordersHeader, ...orders].join('\n');
  const customersCsv = [customersHeader, ...customers].join('\n');
  const geolocationCsv = [geolocationHeader, ...geos].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography/regions`);
  assert.equal(res.status, 200);
  const body = await res.json();

  const byRegion = {};
  for (const item of body.data) byRegion[item.region] = item;

  assert.equal(byRegion['Norte'].risk_level, 'baixo', 'Norte should be baixo (~5%)');
  assert.equal(byRegion['Nordeste'].risk_level, 'medio', 'Nordeste should be medio (~15%)');
  assert.equal(byRegion['Centro-Oeste'].risk_level, 'baixo', 'Centro-Oeste should be baixo (~2%)');
  assert.equal(byRegion['Sudeste'].risk_level, 'baixo', 'Sudeste should be baixo (0%)');
  assert.equal(byRegion['Sul'].risk_level, 'alto', 'Sul should be alto (~25%)');
});

test('orders-geography/regions — state breakdown included', async (t) => {
  const ordersCsv = [
    ordersHeader,
    orderRow('order-1', 'cust-1', '2018-01-10 10:00:00', '2018-01-15 00:00:00'),
    orderRow('order-2', 'cust-2', '2018-01-20 10:00:00', '2018-01-15 00:00:00'),
  ].join('\n');
  const customersCsv = [
    customersHeader,
    customerRow('cust-1', '12345', 'sao paulo', 'SP'),
    customerRow('cust-2', '22222', 'rio de janeiro', 'RJ'),
  ].join('\n');
  const geolocationCsv = [
    geolocationHeader,
    geoRow('12345', '-23.55', '-46.63', 'sao paulo', 'SP'),
    geoRow('22222', '-22.91', '-43.17', 'rio de janeiro', 'RJ'),
  ].join('\n');

  const { baseUrl } = await makeHarness(t, { ordersCsv, customersCsv, geolocationCsv });
  const res = await fetch(`${baseUrl}/api/v1/analytics/orders-geography/regions`);
  assert.equal(res.status, 200);
  const body = await res.json();

  const sudeste = body.data.find((r) => r.region === 'Sudeste');
  assert.ok(sudeste, 'Sudeste region should exist');
  assert.ok(Array.isArray(sudeste.states), 'States array should exist');
  assert.equal(sudeste.states.length, 2, 'Sudeste should have SP and RJ states');

  const spState = sudeste.states.find((s) => s.state === 'SP');
  const rjState = sudeste.states.find((s) => s.state === 'RJ');
  assert.ok(spState, 'SP state should exist');
  assert.ok(rjState, 'RJ state should exist');
  assert.equal(spState.risk_level, 'baixo', 'SP should be baixo (0% delay)');
  assert.equal(rjState.risk_level, 'muito_alto', 'RJ should be muito_alto (100% delay)');
});
