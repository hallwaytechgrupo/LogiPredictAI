exports.up = async function (knex) {
  // Compatibilidade com ambientes que já executaram a migração inicial da BE-02.
  if (await knex.schema.hasColumn('orders', 'status')) {
    await knex.raw('ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check');
    await knex.raw("ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'unknown'");
    return;
  }
  return knex.schema.alterTable('orders', (table) => {
    table.string('status', 20).notNullable().defaultTo('unknown');
  });
};

exports.down = async function (knex) {
  if (!(await knex.schema.hasColumn('orders', 'status'))) return;
  return knex.schema.alterTable('orders', (table) => {
    table.dropColumn('status');
  });
};
