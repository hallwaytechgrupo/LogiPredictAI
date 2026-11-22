import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createApp } from '../src/app.js';

test('map proxy preserves filters, scenarios, validation and availability errors', async (t) => {
  const calls = [];
  const upstream = createServer((req, res) => {
    let body = '';
    req.on('data', (chunk) => body += chunk);
    req.on('end', () => {
      calls.push({ method: req.method, url: req.url, body: body ? JSON.parse(body) : null });
      const code = req.url.includes('invalid') ? 422 : req.url.includes('missing') ? 404 : req.url.includes('offline') ? 503 : 200;
      res.writeHead(code, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(code === 200 ? { source: 'olist', model_version: 'modelo_564_filter' } : { detail: 'Revise os dados informados.' }));
    });
  }).listen(0, '127.0.0.1');
  await new Promise((resolve) => upstream.once('listening', resolve));
  const app = await createApp({ mlUrl: `http://127.0.0.1:${upstream.address().port}` });
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(() => Promise.all([upstream, server].map((s) => new Promise((resolve) => s.close(resolve)))));
  const base = `http://127.0.0.1:${server.address().port}/api/v1/map`;
  const query = new URLSearchParams({ start_date: '2018-06-01', origin_state: 'SP', region: 'Sudeste', risk: 'Médio', offset: '30' });
  assert.equal((await fetch(`${base}/orders?${query}`)).status, 200);
  assert.equal(calls[0].url, `/map/orders?${query}`);
  const body = { order_id: 'pedido-real', dispatched_at: '2018-06-02T10:00:00', destination_prefix5: '01234' };
  const response = await fetch(`${base}/simulate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  assert.equal((await response.json()).model_version, 'modelo_564_filter');
  assert.deepEqual(calls[1].body, body);
  assert.equal(calls[1].method, 'POST');
  const invalid = await fetch(`${base}/orders?risk=invalid`);
  assert.equal(invalid.status, 422);
  assert.equal((await invalid.json()).message, 'Revise os dados informados.');
  assert.equal((await fetch(`${base}/order?order_id=missing`)).status, 404);
  assert.equal((await fetch(`${base}/orders?risk=offline`)).status, 503);
  assert.equal((await fetch(`${base}/simulate`, { method: 'POST', body: 'invalid' })).status, 415);
});
