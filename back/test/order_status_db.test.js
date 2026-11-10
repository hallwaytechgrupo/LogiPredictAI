import test from 'node:test';
import assert from 'node:assert/strict';
import createOrders from '../src/db/migrations/20250101000001_create_orders_table.cjs';
import statusMigration from '../src/db/migrations/20250101000004_add_order_status.cjs';
import upstreamStatusMigration from '../src/db/migrations/20261109000000_add_order_status.cjs';
import { getKnex } from '../src/db/knex.js';
import { create, findById, list } from '../src/db/repositories/orders.js';

test('PostgreSQL migration backfills legacy status and persists new statuses', {
  skip: process.env.TEST_ORDER_STATUS_DB !== '1',
}, async (t) => {
  // Este teste cria tabelas: execute apenas em uma base temporária dedicada.
  assert.match(process.env.DB_NAME ?? '', /^logipredict_be02_test_/);
  const db = getKnex();
  t.after(async () => {
    try {
      await db.schema.dropTableIfExists('orders');
    } finally {
      await db.destroy();
    }
  });
  await db.schema.dropTableIfExists('orders');
  await createOrders.up(db);
  await db('orders').insert([
    { order_id: 'legacy-pending', destination_zip_code: '01001000', customer_state: 'SP' },
    { order_id: 'legacy-shipped', destination_zip_code: '01001000', customer_state: 'SP', dispatched_at: '2026-10-02T10:00:00' },
  ]);
  await statusMigration.up(db);
  await upstreamStatusMigration.up(db);
  assert.equal((await findById('legacy-pending')).status, 'unknown');
  assert.equal((await findById('legacy-shipped')).status, 'shipped');
  await create({
    order_id: 'delivered', destination_zip_code: '01001000', customer_state: 'SP',
    status: 'delivered', estimated_delivery_at: '2026-10-09T00:00:00',
  });
  const detail = await findById('delivered');
  assert.equal(detail.status, 'delivered');
  assert.equal(detail.estimated_delivery_at.toISOString().slice(0, 10), '2026-10-09');
  const result = await list({ page: 1, perPage: 50, status: 'delivered' });
  assert.equal(Number(result.total), 1);
  assert.equal(result.data[0].order_id, 'delivered');
  await db('orders').where({ order_id: 'delivered' }).update({ status: 'processing' });
  assert.equal((await findById('delivered')).status, 'processing');
  await statusMigration.down(db);
  assert.equal(await db.schema.hasColumn('orders', 'status'), false);

  // Banco que recebeu primeiro a migração publicada na main.
  await upstreamStatusMigration.up(db);
  await statusMigration.up(db);
  assert.equal((await findById('delivered')).status, 'unknown');
  await upstreamStatusMigration.down(db);
  await statusMigration.down(db);

  // Banco local que já executou a versão antiga com quatro status restritos.
  await db.schema.alterTable('orders', (table) => {
    table.enu('status', ['pending', 'shipped', 'delivered', 'canceled'])
      .notNullable().defaultTo('pending');
  });
  await upstreamStatusMigration.up(db);
  await db('orders').where({ order_id: 'delivered' }).update({ status: 'processing' });
  assert.equal((await findById('delivered')).status, 'processing');
});
