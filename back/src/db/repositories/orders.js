import getKnex from '../knex.js';
import { orderStatus } from '../../order-status.js';
import { cloudStore } from '../cloud-context.js';

let dbAvailable = null; // null = unknown, true = available, false = unavailable

async function checkDb() {
  if (cloudStore()) return true;
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
  order = { ...order, status: orderStatus(order) };
  const store = cloudStore();
  if (store) {
    const orders = await store.read('orders');
    if (orders.some((item) => item.order_id === order.order_id)) {
      throw Object.assign(new Error('O pedido já existe.'), { code: '23505' });
    }
    const now = new Date().toISOString();
    const saved = { ...order, created_at: now, updated_at: now };
    await store.replace('orders', [...orders, saved]);
    return saved;
  }
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
  if (cloudStore()) return (await cloudStore().read('orders')).find((order) => order.order_id === orderId) ?? null;
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
  if (cloudStore()) {
    const { page = 1, perPage = 20, hubId, search, status, source } = options;
    const orders = (await cloudStore().read('orders')).filter((order) =>
      (!hubId || order.hub_id === hubId) &&
      (!search || order.order_id.toLowerCase().includes(search.toLowerCase())) &&
      (!status || orderStatus(order) === status) &&
      (!source || (order.source || 'operational') === source));
    return { data: orders.slice((page - 1) * perPage, page * perPage), total: orders.length, page, perPage };
  }
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
    const data = await query.clone().offset(offset).limit(perPage).orderBy('created_at', 'desc');

    return { data, total, page, perPage };
  } catch (e) {
    dbAvailable = false;
    return { data: [], total: 0 };
  }
}

export async function summary() {
  if (cloudStore()) {
    const orders = (await cloudStore().read('orders')).filter((order) => (order.source || 'operational') === 'operational');
    const ids = new Set(orders.map((order) => order.order_id));
    const predictions = await cloudStore().read('predictions');
    const withHub = orders.filter((order) => order.hub_id).length;
    return { total: orders.length, withHub, withoutHub: orders.length - withHub,
      withPrediction: new Set(predictions.filter((item) => ids.has(item.order_id)).map((item) => item.order_id)).size };
  }
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
  if (cloudStore()) return updateCloudHub(orderId, hubId, true);
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
  if (cloudStore()) return updateCloudHub(orderId, hubId, false, reason);
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
  if (cloudStore()) return (await findById(orderId)) != null;
  const available = await checkDb();
  if (!available) return false;

  const knex = getKnex();
  const row = await knex('orders').where({ order_id: orderId }).first();
  return !!row;
}

export { checkDb };

async function updateCloudHub(orderId, hubId, manual, reason = null) {
  const store = cloudStore();
  const orders = await store.read('orders');
  const order = orders.find((item) => item.order_id === orderId);
  if (!order) return null;
  if (!manual && order.hub_association_manual) return order;
  Object.assign(order, { hub_id: hubId, hub_association_manual: manual,
    hub_association_reason: reason, updated_at: new Date().toISOString() });
  await store.replace('orders', orders);
  return order;
}
