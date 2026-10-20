import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { after, test } from 'node:test';
import { once } from 'node:events';
import { createApp } from '../src/app.js';

const servers = [];
async function listen(server) {
  if (typeof server === 'function') server = createServer(server);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  servers.push(server);
  return `http://127.0.0.1:${server.address().port}`;
}
after(async () => {
  await Promise.all(servers.map(server => new Promise(resolve => {
    server.close(resolve);
    server.closeAllConnections();
  })));
});

test('saúde responde sem ML; readiness informa dependência ausente', async () => {
  const url = await listen(createApp({ mlUrl: 'http://127.0.0.1:1' }));
  assert.equal((await fetch(`${url}/health`)).status, 200);
  const ready = await fetch(`${url}/ready`);
  assert.equal(ready.status, 503);
  assert.equal((await ready.json()).error, 'ML_UNAVAILABLE');
});

test('encaminha previsão e preserva identificação de dados sintéticos', async () => {
  const upstream = await listen(createServer((req, res) => {
    assert.equal(req.url, '/predict');
    assert.equal(req.method, 'POST');
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      assert.deepEqual(JSON.parse(body), { items_count: 2 });
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ synthetic: true, delay_probability: 0.73, predicted_late: true }));
    });
  }));
  const url = await listen(createApp({ mlUrl: upstream }));
  const response = await fetch(`${url}/api/v1/predictions`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ items_count: 2 }),
  });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).synthetic, true);
});

test('retorna validação sem expor campo input do Python', async () => {
  const upstream = await listen(createServer((_req, res) => {
    res.writeHead(422, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ detail: [{ loc: ['body', 'price'], msg: 'Invalid', type: 'error', input: 'private' }] }));
  }));
  const url = await listen(createApp({ mlUrl: upstream }));
  const response = await fetch(`${url}/api/v1/predictions`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
  });
  assert.equal(response.status, 422);
  assert.ok(!(await response.text()).includes('private'));
});

test('timeout de upstream vira HTTP 504', async () => {
  const upstream = await listen(createServer(() => {}));
  const url = await listen(createApp({ mlUrl: upstream, timeoutMs: 30 }));
  const response = await fetch(`${url}/ready`);
  assert.equal(response.status, 504);
});

test('distingue modelo ausente de erro ou resposta inválida do upstream', async () => {
  for (const [status, body, expected] of [
    [503, '{"detail":"missing model"}', 503], [500, '{}', 502], [200, 'invalid JSON', 502],
  ]) {
    const upstream = await listen(createServer((_req, res) => {
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(body);
    }));
    const url = await listen(createApp({ mlUrl: upstream }));
    assert.equal((await fetch(`${url}/ready`)).status, expected);
  }
});

test('JSON inválido, mídia incorreta, payload grande e rota desconhecida', async () => {
  const url = await listen(createApp());
  for (const [body, contentType, expected] of [
    ['{', 'application/json', 400], ['hello', 'text/plain', 415],
    [JSON.stringify({ x: 'x'.repeat(33000) }), 'application/json', 413],
  ]) {
    const response = await fetch(`${url}/api/v1/predictions`, {
      method: 'POST', headers: { 'Content-Type': contentType }, body,
    });
    assert.equal(response.status, expected);
  }
  assert.equal((await fetch(`${url}/unknown`)).status, 404);
});
