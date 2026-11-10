import getKnex from '../knex.js';

let dbAvailable = null; // null = unknown, true = available, false = unavailable

async function checkDb() {
  if (dbAvailable === true) return true;
  if (dbAvailable === false) return false;
  try {
    const knex = getKnex();
    await knex.raw('SELECT 1');
    dbAvailable = true;
    return true;
  } catch (e) {
    dbAvailable = false;
    return false;
  }
}

// Allow resetting the cache (useful for tests)
export function resetDbCache() {
  dbAvailable = null;
}

export async function create(order) {
  const available = await checkDb();
  if (!available) return null;

  const knex = getKnex();
  try {
    const [id] = await knex('orders').insert(order, 'id');
    return { ...order, id };
  } catch (e) {
    if (e.code === '23505') {
      // Unique violation on order_id
      return await knex('orders').where({ order_id: order.order_id }).first();
    }
    throw e;
  }
}

export async function findById(orderId) {
  const available = await checkDb();
  if (!available) return null;

  try {
    const knex = getKnex();
    return await knex('orders').where({ order_id: orderId }).first();
  } catch (e) {
    dbAvailable = false;
    return null;
  }
}

export async function list(options = {}) {
  const available = await checkDb();
  if (!available) return { data: [], total: 0 };

  try {
    const knex = getKnex();
    const { page = 1, perPage = 20, hubId, search, status, source } = options;
    const offset = (page - 1) * perPage;

    const query = knex('orders');

    if (hubId) query.where({ hub_id: hubId });
    if (search) query.where('order_id', 'ilike', `%${search}%`);
    if (status) query.where({ status });
    if (source) query.where({ source });

    const total = Number((await query.clone().count('* as count').first()).count);
    const data = await query.offset(offset).limit(perPage).orderBy('created_at', 'desc');

    return { data, total, page, perPage };
  } catch (e) {
    dbAvailable = false;
    return { data: [], total: 0 };
  }
}

export async function summary() {
  const available = await checkDb();
  if (!available) return null;

  try {
    const knex = getKnex();
    // Only count operational orders (source = 'operational')
    const ops = knex('orders').where({ source: 'operational' });
    const total = Number((await ops.clone().count('* as count').first()).count);
    const withHub = Number((await ops.clone().whereNotNull('hub_id').count('* as count').first()).count);
    const withoutHub = Number((await ops.clone().whereNull('hub_id').count('* as count').first()).count);

    // Count orders with predictions
    const predicted = await knex('predictions')
      .join('orders', 'predictions.order_id', 'orders.order_id')
      .where({ 'orders.source': 'operational' })
      .countDistinct('predictions.order_id as count');
    const withPrediction = Number(predicted[0].count);

    return { total, withHub, withoutHub, withPrediction };
  } catch (e) {
    dbAvailable = false;
    return null;
  }
}

export async function updateHub(orderId, hubId) {
  const available = await checkDb();
  if (!available) return null;

  try {
    const knex = getKnex();
    await knex('orders')
      .where({ order_id: orderId })
      .update({
        hub_id: hubId,
        hub_association_manual: true,
        updated_at: knex.fn.now(),
      });
    return await knex('orders').where({ order_id: orderId }).first();
  } catch (e) {
    dbAvailable = false;
    return null;
  }
}

export async function associateHub(orderId, hubId, reason = null) {
  const available = await checkDb();
  if (!available) return null;

  const knex = getKnex();
  // Only associate if no manual association exists
  const existing = await knex('orders').where({ order_id: orderId }).first();
  if (existing && existing.hub_association_manual) {
    return existing; // Preserve manual association
  }

  await knex('orders')
    .where({ order_id: orderId })
    .update({
      hub_id: hubId,
      hub_association_reason: reason,
      hub_association_manual: false,
      updated_at: knex.fn.now(),
    });

  return knex('orders').where({ order_id: orderId }).first();
}

export async function exists(orderId) {
  const available = await checkDb();
  if (!available) return false;

  const knex = getKnex();
  const row = await knex('orders').where({ order_id: orderId }).first();
  return !!row;
}

export { checkDb };
