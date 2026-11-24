import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createApp } from '../src/app.js';
import { PostgresStore, databaseOptions } from '../src/db/cloud-store.js';

test('conexões externas usam TLS com certificado validado', () => {
  const options = databaseOptions('postgresql://user:password@database.example/neondb?sslmode=disable');
  assert.equal(new URL(options.connectionString).searchParams.get('sslmode'), 'verify-full');
  assert.throws(() => databaseOptions('https://example.com'), /PostgreSQL/);
});

test('persistência em PostgreSQL, concorrência e API sem depender de arquivos locais', {
  skip: process.env.TEST_CLOUD_DB !== '1',
}, async (t) => {
  // Use a conexão da branch de validação, nunca uma base operacional com dados pessoais.
  const store = new PostgresStore();
  const second = new PostgresStore();
  t.after(async () => { await store.close(); await second.close(); });
  await store.initialize({ hubs: [{ id: 'validation-hub', code: 'TEST', name: 'Hub de validação',
    city: 'São Paulo', state: 'SP', active: true, validationStatus: 'APROVADO', latitude: -23.55, longitude: -46.63 }] });
  const expectedHubs = await store.read('hubs');
  const id = `CLOUD-TEST-${randomUUID()}`;
  await store.run(async () => {
    const orders = await store.read('orders');
    await store.replace('orders', [...orders, { order_id: id, source: 'validation', status: 'approved' }]);
  });
  await second.run(async () => assert.ok((await second.read('orders')).some((order) => order.order_id === id)));

  let release;
  const barrier = new Promise((resolve) => { release = resolve; });
  let bothRead = 0;
  const concurrent = (database, suffix) => database.run(async () => {
    const records = await database.read('orders');
    if (++bothRead === 2) release();
    await barrier;
    await database.replace('orders', [...records, { order_id: `${id}-${suffix}`, source: 'validation' }]);
  });
  const results = await Promise.allSettled([concurrent(store, 'A'), concurrent(second, 'B')]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(results.find((result) => result.status === 'rejected').reason.code, 'STORAGE_CONFLICT');

  const app = await createApp({ store, hubsFile: 'arquivo-inexistente.json', ordersFile: 'arquivo-inexistente.json',
    mlUrl: process.env.CLOUD_TEST_ML_URL ?? 'http://127.0.0.1:8000',
    timeoutMs: 90000,
    corsOrigins: ['https://hallwaytechgrupo.github.io'] });
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  const headers = { 'Content-Type': 'application/json' };
  let response = await fetch(`${base}/api/v1/orders/import`, { method: 'POST', headers,
    body: JSON.stringify({ orders: [{ order_id: `${id}-HTTP` }] }) });
  assert.equal(response.status, 200);
  response = await fetch(`${base}/api/v1/orders/${id}-HTTP`);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).data.order_id, `${id}-HTTP`);
  response = await fetch(`${base}/api/v1/hubs?status=all`);
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).data.map((hub) => hub.id).sort(), expectedHubs.map((hub) => hub.id).sort());
  response = await fetch(`${base}/health`, { headers: { Origin: 'https://hallwaytechgrupo.github.io' } });
  assert.equal(response.headers.get('access-control-allow-origin'), 'https://hallwaytechgrupo.github.io');
  response = await fetch(`${base}/health`, { headers: { Origin: 'https://outro-site.example' } });
  assert.equal(response.headers.get('access-control-allow-origin'), null);

  const csv = 'order_id;origin_zip_code;destination_zip_code;purchase_at;dispatched_at;estimated_delivery_at;seller_state;customer_state;items_count;sellers_count;price;freight_value;total_weight_g;total_volume_cm3;status\n'
    + `${id}-CSV;01001000;20040002;2026-12-23T09:00:00;2026-12-24T15:00:00;2027-01-04T18:00:00;SP;RJ;1;1;100;20;500;1200;processing`;
  response = await fetch(`${base}/api/v1/orders/import-csv`, { method: 'POST', headers, body: JSON.stringify({ csv }) });
  assert.equal(response.status, 200);
  const imported = await response.json();
  assert.equal(imported.imported, 1, JSON.stringify(imported));
  response = await fetch(`${base}/api/v1/orders/${id}-CSV`);
  const detail = (await response.json()).data;
  assert.equal(detail.total_weight_g, 500);
  assert.equal(detail.status, 'processing');
  await t.test('previsão remota permanece disponível em outra conexão', {
    skip: !process.env.CLOUD_TEST_ML_URL,
  }, async () => {
    response = await fetch(`${base}/api/v1/predictions?order_id=${id}-CSV`, { method: 'POST', headers,
      body: JSON.stringify({ purchase_at: detail.purchase_at, dispatched_at: detail.dispatched_at,
        estimated_delivery_at: detail.estimated_delivery_at, seller_state: 'SP', customer_state: 'RJ',
        distance_km: 360, total_weight_g: 500, total_volume_cm3: 1200, items_count: 1,
        sellers_count: 1, price: 100, freight_value: 20 }) });
    assert.equal(response.status, 200);
    const prediction = await response.json();
    assert.equal(prediction.persisted, true);
    await second.run(async () => assert.ok((await second.read('predictions'))
      .some((record) => record.prediction_id === prediction.prediction_id)));
  });
});
