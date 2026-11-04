import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createApp } from '../src/app.js';

test('prediction proxy sends model input unchanged and reports ML unavailability', async (t) => {
  let received;
  const mlServer = createServer((req, res) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => body += chunk);
    req.on('end', () => {
      received = JSON.parse(body);
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ detail: 'test only: model unavailable' }));
    });
  }).listen(0);
  await new Promise((resolve) => mlServer.once('listening', resolve));
  const apiServer = createApp({
    mlUrl: 'http://127.0.0.1:' + mlServer.address().port,
  }).listen(0);
  await new Promise((resolve) => apiServer.once('listening', resolve));
  t.after(async () => {
    await Promise.all([mlServer, apiServer].map((server) =>
      new Promise((resolve, reject) =>
        server.close((error) => error ? reject(error) : resolve()),
      ),
    ));
  });

  const payload = {
    purchase_at: '2018-01-10T10:00:00',
    dispatched_at: '2018-01-11T09:00:00',
    estimated_delivery_at: '2018-01-20T00:00:00',
    seller_state: 'SP',
    customer_state: 'BA',
    distance_km: 1450.5,
    total_weight_g: 2500,
    items_count: 1,
    sellers_count: 1,
    price: 350,
    freight_value: 35,
  };
  const response = await fetch(
    'http://127.0.0.1:' + apiServer.address().port + '/api/v1/predictions',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    },
  );
  assert.equal(response.status, 503);
  assert.deepEqual(received, payload);
});
