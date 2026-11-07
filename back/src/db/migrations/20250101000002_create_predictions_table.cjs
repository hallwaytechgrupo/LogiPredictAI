exports.up = function (knex) {
  return knex.schema.createTable('predictions', (table) => {
    table.uuid('id').primary().defaultTo(knex.raw('gen_random_uuid()'));
    table.string('order_id').notNullable();
    table.string('hub_id');
    table.decimal('delay_probability', 6, 4);
    table.boolean('predicted_late');
    table.decimal('threshold', 6, 4);
    table.string('model_version');
    table.string('source');
    table.boolean('synthetic');
    table.jsonb('warnings');
    table.jsonb('input_features');
    table.dateTime('predicted_at').defaultTo(knex.fn.now());

    table.index('order_id');
    table.index('hub_id');
    table.index('predicted_at');
    table.index('predicted_late');

    table.foreign('order_id').references('orders.order_id').onDelete('CASCADE');
  });
};

exports.down = function (knex) {
  return knex.schema.dropTable('predictions');
};