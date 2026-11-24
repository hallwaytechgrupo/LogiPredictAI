import getKnex from '../knex.js';
import { cloudStore } from '../cloud-context.js';

let dbAvailable = false;

async function checkDb() {
  if (cloudStore()) return true;
  if (dbAvailable) return true;
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

export async function create(prediction) {
  if (cloudStore()) {
    await cloudStore().appendPredictions([prediction]);
    return prediction;
  }
  const available = await checkDb();
  if (!available) return null;

  try {
    const knex = getKnex();
    const { id } = await knex('predictions').insert(prediction, 'id');
    return { ...prediction, id };
  } catch (e) {
    dbAvailable = false;
    return null;
  }
}

export async function findByOrderId(orderId) {
  if (cloudStore()) return (await cloudStore().read('predictions')).filter((item) => item.order_id === orderId);
  const available = await checkDb();
  if (!available) return [];

  try {
    const knex = getKnex();
    return await knex('predictions')
      .where({ order_id: orderId })
      .orderBy('predicted_at', 'desc');
  } catch (e) {
    dbAvailable = false;
    return [];
  }
}

export async function list(options = {}) {
  if (cloudStore()) {
    const { page = 1, perPage = 20, hubId, orderId } = options;
    const predictions = (await cloudStore().read('predictions')).filter((item) =>
      (!hubId || item.hub_id === hubId) && (!orderId || item.order_id === orderId));
    return { data: predictions.slice((page - 1) * perPage, page * perPage), total: predictions.length, page, perPage };
  }
  const available = await checkDb();
  if (!available) return { data: [], total: 0 };

  try {
    const knex = getKnex();
    const { page = 1, perPage = 20, hubId, orderId } = options;
    const offset = (page - 1) * perPage;

    const query = knex('predictions');

    if (hubId) query.where({ hub_id: hubId });
    if (orderId) query.where({ order_id: orderId });

    const total = (await query.count('* as count').first()).count;
    const data = await query.offset(offset).limit(perPage).orderBy('predicted_at', 'desc');

    return { data, total, page, perPage };
  } catch (e) {
    dbAvailable = false;
    return { data: [], total: 0 };
  }
}

export { checkDb };
