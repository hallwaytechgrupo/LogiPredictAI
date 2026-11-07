exports.up = function (knex) {
  return knex.schema.createTable('dispatch_simulations', (table) => {
    table.uuid('id').primary().defaultTo(knex.raw('gen_random_uuid()'));
    table.string('origin_cep', 10).notNullable();
    table.string('destination_cep', 10).notNullable();
    table.string('origin_hub_id');
    table.string('destination_hub_id');
    table.decimal('origin_to_origin_hub_km', 12, 2);
    table.decimal('destination_to_dest_hub_km', 12, 2);
    table.decimal('hub_to_hub_haversine_km', 12, 2);
    table.decimal('route_distance_km', 12, 2);
    table.integer('route_duration_seconds');
    table.jsonb('route_geometry');
    table.jsonb('metadata');
    table.dateTime('created_at').defaultTo(knex.fn.now());

    table.index('origin_cep');
    table.index('destination_cep');
    table.index('origin_hub_id');
    table.index('destination_hub_id');
    table.index('created_at');
  });
};

exports.down = function (knex) {
  return knex.schema.dropTable('dispatch_simulations');
};