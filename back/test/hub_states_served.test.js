import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

let directory;
let hubsFile;
let ordersFile;
let predictionsFile;
let journalFile;
let server;
let baseUrl;

async function setup() {
  directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-states-'));
  hubsFile = path.join(directory, 'hubs.json');
  ordersFile = path.join(directory, 'orders.json');
  predictionsFile = path.join(directory, 'predictions.json');
  journalFile = `${predictionsFile}.jsonl`;
  await writeFile(hubsFile, '[]');
  await writeFile(ordersFile, '[]');
  await writeFile(predictionsFile, '[]');
  await writeFile(journalFile, '');
  server = createApp({ hubsFile, ordersFile, predictionsFile, predictionJournalFile: journalFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
}

async function teardown() {
  await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  await rm(directory, { recursive: true, force: true });
}

test('statesServed: validates valid UFs', async (t) => {
  await setup();
  t.after(teardown);

  const res = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-TEST-001',
      name: 'Hub Test',
      city: 'São Paulo',
      state: 'SP',
      statesServed: ['sp', 'mg', 'RJ'],
    }),
  });
  assert.equal(res.status, 201);
  const hub = (await res.json()).data;
  assert.deepEqual(hub.statesServed, ['MG', 'RJ', 'SP']);
});

test('statesServed: rejects invalid UFs', async (t) => {
  await setup();
  t.after(teardown);

  const res = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-TEST-002',
      name: 'Hub Test',
      city: 'São Paulo',
      state: 'SP',
      statesServed: ['XX', 'YZ'],
    }),
  });
  assert.equal(res.status, 422);
  const body = await res.json();
  assert.equal(body.error, 'VALIDATION_ERROR');
  assert.ok(body.details.some((d) => d.field === 'statesServed'));
});

test('statesServed: rejects non-array values', async (t) => {
  await setup();
  t.after(teardown);

  const res = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-TEST-003',
      name: 'Hub Test',
      city: 'São Paulo',
      state: 'SP',
      statesServed: 'SP,MG',
    }),
  });
  assert.equal(res.status, 422);
});

test('statesServed: creates hub without statesServed (legacy compatibility)', async (t) => {
  await setup();
  t.after(teardown);

  const res = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-LEGACY',
      name: 'Hub Legacy',
      city: 'Curitiba',
      state: 'PR',
    }),
  });
  assert.equal(res.status, 201);
  const hub = (await res.json()).data;
  // statesServed is not set, so it should be null or undefined
  assert.ok(hub.statesServed === null || hub.statesServed === undefined);
  assert.equal(hub.state, 'PR');
});

test('statesServed: PATCH endpoint updates coverage', async (t) => {
  await setup();
  t.after(teardown);

  // Create a hub first
  const createRes = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-PATCH',
      name: 'Hub Patch',
      city: 'Porto Alegre',
      state: 'RS',
    }),
  });
  const hub = (await createRes.json()).data;

  // Update states served
  const patchRes = await fetch(`${baseUrl}/api/v1/hubs/${hub.id}/states-served`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ statesServed: ['RS', 'SC', 'PR'] }),
  });
  assert.equal(patchRes.status, 200);
  const updated = (await patchRes.json()).data;
  assert.deepEqual(updated.statesServed, ['PR', 'RS', 'SC']);
});

test('statesServed: PATCH endpoint clears coverage with null', async (t) => {
  await setup();
  t.after(teardown);

  const createRes = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-CLEAR',
      name: 'Hub Clear',
      city: 'Florianópolis',
      state: 'SC',
      statesServed: ['SC', 'RS'],
    }),
  });
  const hub = (await createRes.json()).data;
  assert.deepEqual(hub.statesServed, ['RS', 'SC']);

  const patchRes = await fetch(`${baseUrl}/api/v1/hubs/${hub.id}/states-served`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ statesServed: null }),
  });
  assert.equal(patchRes.status, 200);
  const updated = (await patchRes.json()).data;
  assert.equal(updated.statesServed, null);
});

test('statesServed: PATCH endpoint validates UFs', async (t) => {
  await setup();
  t.after(teardown);

  const createRes = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-VAL',
      name: 'Hub Val',
      city: 'Recife',
      state: 'PE',
    }),
  });
  const hub = (await createRes.json()).data;

  const patchRes = await fetch(`${baseUrl}/api/v1/hubs/${hub.id}/states-served`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ statesServed: ['PE', 'INVALID'] }),
  });
  assert.equal(patchRes.status, 422);
});

test('statesServed: PATCH endpoint returns 404 for unknown hub', async (t) => {
  await setup();
  t.after(teardown);

  const patchRes = await fetch(`${baseUrl}/api/v1/hubs/fake-id/states-served`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ statesServed: ['SP'] }),
  });
  assert.equal(patchRes.status, 404);
});

test('statesServed: PUT endpoint updates coverage', async (t) => {
  await setup();
  t.after(teardown);

  const createRes = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-PUT',
      name: 'Hub Put',
      city: 'Salvador',
      state: 'BA',
    }),
  });
  const hub = (await createRes.json()).data;

  const putRes = await fetch(`${baseUrl}/api/v1/hubs/${hub.id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-PUT',
      name: 'Hub Put Updated',
      city: 'Salvador',
      state: 'BA',
      statesServed: ['BA', 'PE', 'CE'],
    }),
  });
  assert.equal(putRes.status, 200);
  const updated = (await putRes.json()).data;
  assert.deepEqual(updated.statesServed, ['BA', 'CE', 'PE']);
  assert.equal(updated.name, 'Hub Put Updated');
});

test('coverage endpoint: returns uncovered and covered states', async (t) => {
  await setup();
  t.after(teardown);

  // Create two approved hubs with different coverage
  const hub1Res = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-SE1',
      name: 'Hub SE1',
      city: 'São Paulo',
      state: 'SP',
      validationStatus: 'APROVADO',
      statesServed: ['SP', 'RJ'],
    }),
  });
  assert.equal(hub1Res.status, 201);
  const hub2Res = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-SE2',
      name: 'Hub SE2',
      city: 'Rio de Janeiro',
      state: 'RJ',
      validationStatus: 'APROVADO',
      statesServed: ['RJ', 'MG'],
    }),
  });
  assert.equal(hub2Res.status, 201);

  const res = await fetch(`${baseUrl}/api/v1/hubs/coverage`);
  assert.equal(res.status, 200);
  const body = await res.json();

  // SP, RJ, MG should be covered
  assert.ok(body.total_covered >= 3);
  assert.ok(body.total_uncovered > 0);

  // RJ should be shared (2 hubs)
  const sharedRj = body.shared_states.find((s) => s.state === 'RJ');
  assert.ok(sharedRj);
  assert.equal(sharedRj.hub_count, 2);

  // SP should have 1 hub
  const coveredSp = body.covered_states.find((s) => s.state === 'SP');
  assert.equal(coveredSp.hubs.length, 1);
});

test('coverage endpoint: hubs without explicit coverage', async (t) => {
  await setup();
  t.after(teardown);

  // Create an approved hub without statesServed
  const createRes = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-NO-COV',
      name: 'Hub No Coverage',
      city: 'Manaus',
      state: 'AM',
      validationStatus: 'APROVADO',
    }),
  });
  assert.equal(createRes.status, 201);

  const res = await fetch(`${baseUrl}/api/v1/hubs/coverage`);
  assert.equal(res.status, 200);
  const body = await res.json();

  // The hub should appear in hubs_without_coverage
  const noCov = body.hubs_without_coverage.find((h) => h.code === 'HUB-NO-COV');
  assert.ok(noCov);

  // AM should still be covered (fallback to hub.state)
  const coveredAm = body.covered_states.find((s) => s.state === 'AM');
  assert.ok(coveredAm);
});

test('assign-hubs-by-state: uses statesServed for hub assignment', async (t) => {
  await setup();
  t.after(teardown);

  // Create a hub in SP that serves SP and RJ
  await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-SP-RJ',
      name: 'Hub SP-RJ',
      city: 'São Paulo',
      state: 'SP',
      statesServed: ['SP', 'RJ'],
    }),
  });

  // Create orders for SP and RJ
  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [
        { order_id: 'order-sp-001', customer_state: 'SP' },
        { order_id: 'order-rj-001', customer_state: 'RJ' },
      ],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();

  // Both orders should be assigned to the same hub
  const spAssign = body.assignments.find((a) => a.order_id === 'order-sp-001');
  const rjAssign = body.assignments.find((a) => a.order_id === 'order-rj-001');
  assert.ok(spAssign.assigned_hub_id);
  assert.ok(rjAssign.assigned_hub_id);
  assert.equal(spAssign.assigned_hub_id, rjAssign.assigned_hub_id);
});

test('assign-hubs-by-state: legacy hub without statesServed falls back to hub.state', async (t) => {
  await setup();
  t.after(teardown);

  // Create a legacy hub without statesServed
  await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-LEGACY-SP',
      name: 'Hub Legacy SP',
      city: 'São Paulo',
      state: 'SP',
    }),
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [
        { order_id: 'order-sp-001', customer_state: 'SP' },
        { order_id: 'order-rj-001', customer_state: 'RJ' },
      ],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();

  // SP order should be assigned
  const spAssign = body.assignments.find((a) => a.order_id === 'order-sp-001');
  assert.ok(spAssign.assigned_hub_id);

  // RJ order should NOT be assigned (no hub serves RJ)
  const rjAssign = body.assignments.find((a) => a.order_id === 'order-rj-001');
  assert.equal(rjAssign.assigned_hub_id, null);
  assert.equal(rjAssign.reason, 'NO_HUB_FOR_STATE');
});

test('assign-hubs-by-state: no eligible hub returns clear reason', async (t) => {
  await setup();
  t.after(teardown);

  // Create a hub that only serves SP
  await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-SP-ONLY',
      name: 'Hub SP Only',
      city: 'São Paulo',
      state: 'SP',
      statesServed: ['SP'],
    }),
  });

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dry_run: true,
      orders: [
        { order_id: 'order-am-001', customer_state: 'AM' },
      ],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();

  const assign = body.assignments.find((a) => a.order_id === 'order-am-001');
  assert.equal(assign.assigned_hub_id, null);
  assert.equal(assign.reason, 'NO_HUB_FOR_STATE');
  assert.equal(body.summary.total_unassigned, 1);
});

test('assign-hubs-by-state: multiple eligible hubs distribute deterministically', async (t) => {
  await setup();
  t.after(teardown);

  // Create 3 hubs serving SP
  const hubIds = [];
  for (let i = 1; i <= 3; i++) {
    const res = await fetch(`${baseUrl}/api/v1/hubs`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        code: `HUB-SP-${i}`,
        name: `Hub SP ${i}`,
        city: 'São Paulo',
        state: 'SP',
        statesServed: ['SP'],
      }),
    });
    hubIds.push((await res.json()).data.id);
  }

  // Create 6 orders for SP
  const orders = [];
  for (let i = 1; i <= 6; i++) {
    orders.push({ order_id: `order-sp-${String(i).padStart(3, '0')}`, customer_state: 'SP' });
  }

  const res = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dry_run: true, orders }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();

  // Count assignments per hub
  const hubCounts = new Map();
  for (const assignment of body.assignments) {
    hubCounts.set(assignment.assigned_hub_id, (hubCounts.get(assignment.assigned_hub_id) || 0) + 1);
  }

  // All 6 orders should be assigned
  assert.equal(body.assignments.length, 6);
  assert.equal(body.summary.total_unassigned, 0);

  // Distribution should be balanced (2 per hub with 6 orders / 3 hubs)
  assert.equal(hubCounts.size, 3);
  for (const [, count] of hubCounts) {
    assert.equal(count, 2);
  }

  // Run again — should produce identical results (deterministic)
  const res2 = await fetch(`${baseUrl}/api/v1/orders/assign-hubs-by-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dry_run: true, orders }),
  });
  const body2 = await res2.json();
  assert.deepEqual(body2.assignments, body.assignments);
});

test('statesServed: normalizes case and deduplicates', async (t) => {
  await setup();
  t.after(teardown);

  const res = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-NORM',
      name: 'Hub Norm',
      city: 'Brasília',
      state: 'DF',
      statesServed: ['sp', 'SP', '  mg  ', 'Mg'],
    }),
  });
  assert.equal(res.status, 201);
  const hub = (await res.json()).data;
  assert.deepEqual(hub.statesServed, ['MG', 'SP']);
});

test('statesServed: mixed valid and invalid UFs — accepts valid, rejects invalid', async (t) => {
  await setup();
  t.after(teardown);

  const res = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-MIX',
      name: 'Hub Mix',
      city: 'Goiânia',
      state: 'GO',
      statesServed: ['GO', 'XX'],
    }),
  });
  assert.equal(res.status, 422);
  const body = await res.json();
  assert.ok(body.details.some((d) => d.message.includes('XX')));
});

test('statesServed: import endpoint accepts statesServed field', async (t) => {
  await setup();
  t.after(teardown);

  const res = await fetch(`${baseUrl}/api/v1/hubs/import`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      candidates: [
        {
          code: 'HUB-IMPORT-1',
          name: 'Hub Import 1',
          city: 'Belém',
          state: 'PA',
          statesServed: ['PA', 'AM', 'AP'],
        },
      ],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.added, 1);

  // Verify the imported hub has statesServed
  const listRes = await fetch(`${baseUrl}/api/v1/hubs?status=all`);
  const hubs = (await listRes.json()).data;
  const imported = hubs.find((h) => h.code === 'HUB-IMPORT-1');
  assert.deepEqual(imported.statesServed, ['AM', 'AP', 'PA']);
});

test('statesServed: empty array treated as null', async (t) => {
  await setup();
  t.after(teardown);

  const res = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'HUB-EMPTY',
      name: 'Hub Empty',
      city: 'Vitória',
      state: 'ES',
      statesServed: [],
    }),
  });
  assert.equal(res.status, 201);
  const hub = (await res.json()).data;
  assert.equal(hub.statesServed, null);
});
