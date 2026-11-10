exports.up = function (knex) {
  return knex.schema.alterTable('orders', (table) => {
    table.string('status', 20).notNullable().defaultTo('unknown');
  });
};

exports.down = function (knex) {
  return knex.schema.alterTable('orders', (table) => {
    table.dropColumn('status');
  });
};
