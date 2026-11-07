import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

/**
 * Testes para o endpoint POST /api/v1/orders/import-csv
 *
 * Valida importação de CSV operacional com todos os campos obrigatórios,
 * deduplicação, validação de colunas e tipos, e associação automática de hubs.
 */

test('POST /api/v1/orders/import-csv — CSV válido com todas as colunas', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const ordersFile = path.join(tmpDir, 'orders.json');
  const hubsFile = path.join(tmpDir, 'hubs.json');
  const predictionsFile = path.join(tmpDir, 'predictions.json');
  const predictionsJournalFile = path.join(tmpDir, 'predictions.jsonl');

  // Criar hubs.json com um hub ativo e aprovado
  const hubs = [{
    id: 'hub-test-001',
    code: 'HUB-SP-001',
    name: 'Hub Teste SP',
    city: 'São Paulo',
    state: 'SP',
    latitude: -23.5505,
    longitude: -46.6333,
    active: true,
    validationStatus: 'APROVADO',
    osm_id: '12345',
  }];
  await writeFile(hubsFile, JSON.stringify(hubs, null, 2));
  await writeFile(ordersFile, '[]');
  await writeFile(predictionsFile, '[]');

  const csv = [
    'order_id,origin_zip_code,destination_zip_code,purchase_at,dispatched_at,estimated_delivery_at,seller_state,customer_state,items_count,sellers_count,price,freight_value',
    'order-csv-001,01001000,01001000,2018-01-10T10:00:00,2018-01-11T09:00:00,2018-01-20T00:00:00,SP,SP,1,1,350.00,35.00',
  ].join('\n');

  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: ordersFile, HUBS_FILE: hubsFile, PREDICTIONS_FILE: predictionsFile, PREDICTIONS_JOURNAL_FILE: predictionsJournalFile };

  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;

    const res = await fetch(`http://127.0.0.1:${port}/api/v1/orders/import-csv`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ csv }),
    });

    assert.equal(res.status, 200, 'Deve retornar 200 para CSV válido');
    const body = await res.json();
    assert.equal(body.imported, 1, 'Deve importar 1 pedido');
    assert.equal(body.ignored, 0, 'Nenhum pedido ignorado');
    assert.equal(body.failed, 0, 'Nenhum pedido com falha');
    assert.ok(body.data.imported[0].order_id === 'order-csv-001', 'Order ID correto');

    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/orders/import-csv — CSV com colunas ausentes retorna 422', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const ordersFile = path.join(tmpDir, 'orders.json');
  const hubsFile = path.join(tmpDir, 'hubs.json');
  const predictionsFile = path.join(tmpDir, 'predictions.json');
  const predictionsJournalFile = path.join(tmpDir, 'predictions.jsonl');

  await writeFile(ordersFile, '[]');
  await writeFile(hubsFile, '[]');
  await writeFile(predictionsFile, '[]');

  const csv = [
    'order_id,destination_zip_code',
    'order-missing-cols,01001000',
  ].join('\n');

  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: ordersFile, HUBS_FILE: hubsFile, PREDICTIONS_FILE: predictionsFile, PREDICTIONS_JOURNAL_FILE: predictionsJournalFile };

  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;

    const res = await fetch(`http://127.0.0.1:${port}/api/v1/orders/import-csv`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ csv }),
    });

    assert.equal(res.status, 422, 'Deve retornar 422 para colunas ausentes');
    const body = await res.json();
    assert.equal(body.error, 'MISSING_COLUMNS', 'Erro MISSING_COLUMNS');
    assert.ok(body.message.includes('ausentes'), 'Mensagem deve indicar colunas ausentes');

    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/orders/import-csv — Pedidos duplicados são ignorados', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const ordersFile = path.join(tmpDir, 'orders.json');
  const hubsFile = path.join(tmpDir, 'hubs.json');
  const predictionsFile = path.join(tmpDir, 'predictions.json');
  const predictionsJournalFile = path.join(tmpDir, 'predictions.jsonl');

  const hubs = [{
    id: 'hub-test-001',
    code: 'HUB-SP-001',
    name: 'Hub Teste SP',
    city: 'São Paulo',
    state: 'SP',
    latitude: -23.5505,
    longitude: -46.6333,
    active: true,
    validationStatus: 'APROVADO',
    osm_id: '12345',
  }];
  await writeFile(hubsFile, JSON.stringify(hubs, null, 2));
  await writeFile(ordersFile, '[]');
  await writeFile(predictionsFile, '[]');

  const csv = [
    'order_id,origin_zip_code,destination_zip_code,purchase_at,dispatched_at,estimated_delivery_at,seller_state,customer_state,items_count,sellers_count,price,freight_value',
    'order-dup-001,01001000,01001000,2018-01-10T10:00:00,2018-01-11T09:00:00,2018-01-20T00:00:00,SP,SP,1,1,350.00,35.00',
    'order-dup-001,01001000,01001000,2018-01-10T10:00:00,2018-01-11T09:00:00,2018-01-20T00:00:00,SP,SP,1,1,350.00,35.00',
  ].join('\n');

  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: ordersFile, HUBS_FILE: hubsFile, PREDICTIONS_FILE: predictionsFile, PREDICTIONS_JOURNAL_FILE: predictionsJournalFile };

  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;

    const res = await fetch(`http://127.0.0.1:${port}/api/v1/orders/import-csv`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ csv }),
    });

    assert.equal(res.status, 200, 'Deve retornar 200');
    const body = await res.json();
    assert.equal(body.imported, 1, 'Deve importar apenas 1 pedido');
    assert.equal(body.ignored, 1, 'Deve ignorar 1 duplicado');
    assert.equal(body.failed, 0, 'Nenhum com falha');

    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/orders/import-csv — CEP de destino inválido gera falha', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const ordersFile = path.join(tmpDir, 'orders.json');
  const hubsFile = path.join(tmpDir, 'hubs.json');
  const predictionsFile = path.join(tmpDir, 'predictions.json');
  const predictionsJournalFile = path.join(tmpDir, 'predictions.jsonl');

  await writeFile(ordersFile, '[]');
  await writeFile(hubsFile, '[]');
  await writeFile(predictionsFile, '[]');

  const csv = [
    'order_id,origin_zip_code,destination_zip_code,purchase_at,dispatched_at,estimated_delivery_at,seller_state,customer_state,items_count,sellers_count,price,freight_value',
    'order-bad-cep,01001000,invalid,2018-01-10T10:00:00,2018-01-11T09:00:00,2018-01-20T00:00:00,SP,SP,1,1,350.00,35.00',
  ].join('\n');

  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: ordersFile, HUBS_FILE: hubsFile, PREDICTIONS_FILE: predictionsFile, PREDICTIONS_JOURNAL_FILE: predictionsJournalFile };

  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;

    const res = await fetch(`http://127.0.0.1:${port}/api/v1/orders/import-csv`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ csv }),
    });

    assert.equal(res.status, 200, 'Deve retornar 200 (falha registrada no relatório)');
    const body = await res.json();
    assert.equal(body.imported, 0, 'Nenhum importado');
    assert.equal(body.failed, 1, '1 pedido com falha');
    assert.ok(body.data.failed[0].reason.includes('inválido'), 'Motivo deve indicar CEP inválido');

    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/orders/import-csv — UF inválido gera falha', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const ordersFile = path.join(tmpDir, 'orders.json');
  const hubsFile = path.join(tmpDir, 'hubs.json');
  const predictionsFile = path.join(tmpDir, 'predictions.json');
  const predictionsJournalFile = path.join(tmpDir, 'predictions.jsonl');

  await writeFile(ordersFile, '[]');
  await writeFile(hubsFile, '[]');
  await writeFile(predictionsFile, '[]');

  const csv = [
    'order_id,origin_zip_code,destination_zip_code,purchase_at,dispatched_at,estimated_delivery_at,seller_state,customer_state,items_count,sellers_count,price,freight_value',
    'order-bad-uf,01001000,01001000,2018-01-10T10:00:00,2018-01-11T09:00:00,2018-01-20T00:00:00,XX,SP,1,1,350.00,35.00',
  ].join('\n');

  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: ordersFile, HUBS_FILE: hubsFile, PREDICTIONS_FILE: predictionsFile, PREDICTIONS_JOURNAL_FILE: predictionsJournalFile };

  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;

    const res = await fetch(`http://127.0.0.1:${port}/api/v1/orders/import-csv`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ csv }),
    });

    assert.equal(res.status, 200, 'Deve retornar 200');
    const body = await res.json();
    assert.equal(body.imported, 0, 'Nenhum importado');
    assert.equal(body.failed, 1, '1 pedido com falha');
    assert.ok(body.data.failed[0].reason.includes('inválido'), 'Motivo deve indicar UF inválido');

    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/orders/import-csv — CSV vazio retorna 422', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const ordersFile = path.join(tmpDir, 'orders.json');
  const hubsFile = path.join(tmpDir, 'hubs.json');
  const predictionsFile = path.join(tmpDir, 'predictions.json');
  const predictionsJournalFile = path.join(tmpDir, 'predictions.jsonl');

  await writeFile(ordersFile, '[]');
  await writeFile(hubsFile, '[]');
  await writeFile(predictionsFile, '[]');

  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: ordersFile, HUBS_FILE: hubsFile, PREDICTIONS_FILE: predictionsFile, PREDICTIONS_JOURNAL_FILE: predictionsJournalFile };

  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;

    const res = await fetch(`http://127.0.0.1:${port}/api/v1/orders/import-csv`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ csv: '' }),
    });

    assert.equal(res.status, 422, 'Deve retornar 422 para CSV vazio');
    const body = await res.json();
    assert.equal(body.error, 'CSV_REQUIRED', 'Erro CSV_REQUIRED');

    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});

test('POST /api/v1/orders/import-csv — Múltiplos pedidos importados', async (t) => {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), 'logipredict-test-'));
  const ordersFile = path.join(tmpDir, 'orders.json');
  const hubsFile = path.join(tmpDir, 'hubs.json');
  const predictionsFile = path.join(tmpDir, 'predictions.json');
  const predictionsJournalFile = path.join(tmpDir, 'predictions.jsonl');

  const hubs = [{
    id: 'hub-test-001',
    code: 'HUB-SP-001',
    name: 'Hub Teste SP',
    city: 'São Paulo',
    state: 'SP',
    latitude: -23.5505,
    longitude: -46.6333,
    active: true,
    validationStatus: 'APROVADO',
    osm_id: '12345',
  }];
  await writeFile(hubsFile, JSON.stringify(hubs, null, 2));
  await writeFile(ordersFile, '[]');
  await writeFile(predictionsFile, '[]');

  const csv = [
    'order_id,origin_zip_code,destination_zip_code,purchase_at,dispatched_at,estimated_delivery_at,seller_state,customer_state,items_count,sellers_count,price,freight_value',
    'order-multi-001,01001000,01001000,2018-01-10T10:00:00,2018-01-11T09:00:00,2018-01-20T00:00:00,SP,SP,1,1,350.00,35.00',
    'order-multi-002,01001000,01001000,2018-02-10T10:00:00,2018-02-11T09:00:00,2018-02-20T00:00:00,SP,BA,2,1,500.00,50.00',
    'order-multi-003,01001000,01001000,2018-03-10T10:00:00,2018-03-11T09:00:00,2018-03-20T00:00:00,SP,MG,3,2,750.00,75.00',
  ].join('\n');

  const envBackup = process.env;
  process.env = { ...envBackup, ORDERS_FILE: ordersFile, HUBS_FILE: hubsFile, PREDICTIONS_FILE: predictionsFile, PREDICTIONS_JOURNAL_FILE: predictionsJournalFile };

  try {
    const app = await createApp({ mlUrl: new URL('http://localhost:9999'), timeoutMs: 5000 });
    const server = createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;

    const res = await fetch(`http://127.0.0.1:${port}/api/v1/orders/import-csv`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ csv }),
    });

    assert.equal(res.status, 200, 'Deve retornar 200');
    const body = await res.json();
    assert.equal(body.imported, 3, 'Deve importar 3 pedidos');
    assert.equal(body.ignored, 0, 'Nenhum ignorado');
    assert.equal(body.failed, 0, 'Nenhum com falha');
    assert.equal(body.total, 3, 'Total de 3');

    server.close();
    await new Promise((resolve) => server.on('close', resolve));
  } finally {
    process.env = envBackup;
    await rm(tmpDir, { recursive: true, force: true });
  }
});
