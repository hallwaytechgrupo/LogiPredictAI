exports.up = function (knex) {
  return knex.schema.createTable('orders', (table) => {
    table.uuid('id').primary().defaultTo(knex.raw('gen_random_uuid()'));
    table.string('order_id').notNullable().unique();
    table.string('origin_zip_code', 10);
    table.string('destination_zip_code', 10).notNullable();
    table.dateTime('purchase_at');
    table.dateTime('dispatched_at');
    table.dateTime('estimated_delivery_at');
    table.string('seller_state', 2);
    table.string('customer_state', 2).notNullable();
    table.integer('items_count');
    table.integer('sellers_count');
    table.decimal('price', 12, 2);
    table.decimal('freight_value', 12, 2);
    table.decimal('distance_km', 12, 2);
    table.decimal('total_weight_g', 12, 2);
    table.decimal('total_volume_cm3', 15, 2);
    table.string('hub_id');
    table.string('source').defaultTo('operational');
    table.boolean('hub_association_manual').defaultTo(false);
    table.text('hub_association_reason');
    table.dateTime('created_at').defaultTo(knex.fn.now());
    table.dateTime('updated_at').defaultTo(knex.fn.now());

    table.index('order_id');
    table.index('hub_id');
    table.index('destination_zip_code');
    table.index('customer_state');
    table.index('created_at');
  });
};

exports.down = function (knex) {
  return knex.schema.dropTable('orders');
};
