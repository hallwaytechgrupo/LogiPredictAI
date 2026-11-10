exports.up = async function (knex) {
  if (await knex.schema.hasColumn('orders', 'status')) return;
  await knex.schema.alterTable('orders', (table) => {
    table.string('status', 20).notNullable().defaultTo('unknown');
  });
  await knex('orders').whereNotNull('dispatched_at').update({ status: 'shipped' });
};

exports.down = async function (knex) {
  if (!(await knex.schema.hasColumn('orders', 'status'))) return;
  return knex.schema.alterTable('orders', (table) => table.dropColumn('status'));
};
