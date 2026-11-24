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
});
