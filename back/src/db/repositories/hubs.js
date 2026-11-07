import getKnex from '../knex.js';
import fs from 'node:fs';
import path from 'node:path';

let dbAvailable = null; // unknown until checked

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

function readHubsJson() {
  const file = process.env.HUBS_FILE
    || path.resolve(process.cwd(), 'data', 'hubs', 'hubs.json');
  if (!fs.existsSync(file)) return [];
  try {
    const raw = fs.readFileSync(file, 'utf8');
    return JSON.parse(raw);
  } catch {
    return [];
  }
}

// Haversine distance in km
function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

export async function listActive() {
  const available = await checkDb();
  if (available) {
    try {
      const knex = getKnex();
      const rows = await knex('hubs')
        .where({ active: true, approved: true })
        .whereNotNull('latitude')
        .whereNotNull('longitude');
      if (rows.length > 0) return rows;
    } catch (e) {
      dbAvailable = false;
    }
  }
  // Fallback: ler do JSON
  const all = readHubsJson();
  return all.filter(h => 
    (h.active === true || h.status === 'active') && 
    h.validationStatus === 'APROVADO' &&
    h.latitude != null && 
    h.longitude != null
  );
}

export async function findById(hubId) {
  const available = await checkDb();
  if (available) {
    try {
      const knex = getKnex();
      const row = await knex('hubs').where({ id: hubId }).first();
      if (row) return row;
    } catch (e) {
      dbAvailable = false;
    }
  }
  // Fallback: ler do JSON
  const all = readHubsJson();
  return all.find(h => h.id === hubId) || null;
}

export async function nearest(lat, lng) {
  const hubs = await listActive();
  if (hubs.length === 0) return null;

  let nearestHub = null;
  let minDistance = Infinity;

  for (const hub of hubs) {
    const dist = haversineKm(lat, lng, hub.latitude, hub.longitude);
    if (
      dist < minDistance ||
      (dist === minDistance &&
        (nearestHub === null || hub.id < nearestHub.id))
    ) {
      minDistance = dist;
      nearestHub = { ...hub, distance_km: Math.round(dist * 100) / 100 };
    }
  }

  return nearestHub;
}

export { haversineKm, checkDb };
