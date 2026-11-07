import getKnex from '../knex.js';

let dbAvailable = false;

async function checkDb() {
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
