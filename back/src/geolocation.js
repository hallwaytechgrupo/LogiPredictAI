/**
 * Serviço de geolocalização compartilhado.
 *
 * Carrega o índice de geolocalização a partir do CSV da Olist (lazy loading),
 * e fornece funções para resolver CEPs e encontrar o hub mais próximo.
 */
import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { parseCsvRecord, haversineKm } from './utils.js';

let geolocationIndexPromise;
let geolocationFile;

/**
 * Configura o arquivo de geolocalização.
 */
export function initGeolocation(geoFile) {
  geolocationFile = geoFile;
  geolocationIndexPromise = null; // Reset cache quando o arquivo muda
}

/**
 * Carrega o índice de geolocalização a partir do CSV da Olist.
 */
async function loadGeolocationIndex() {
  if (!geolocationFile) {
    throw new Error('Geolocation não inicializada. Chame initGeolocation() primeiro.');
  }
  const groups = new Map();
  const stream = createReadStream(geolocationFile, { encoding: 'utf8' });
  const lines = createInterface({ input: stream, crlfDelay: Infinity });
  let columns;
  for await (const line of lines) {
    const row = parseCsvRecord(line);
    if (!row) continue;
    if (!columns) {
      columns = new Map(row.map((name, index) => [name.trim().toLowerCase(), index]));
      continue;
    }
    const at = (name) => row[columns.get(name)]?.trim() ?? '';
    const prefix = at('geolocation_zip_code_prefix').padStart(5, '0');
    const latitude = Number(at('geolocation_lat'));
    const longitude = Number(at('geolocation_lng'));
    if (!/^\d{5}$/.test(prefix) || !Number.isFinite(latitude) ||
        latitude < -90 || latitude > 90 || !Number.isFinite(longitude) ||
        longitude < -180 || longitude > 180) continue;
    let group = groups.get(prefix);
    if (!group) {
      group = { latitudes: [], longitudes: [], cities: new Map(), states: new Map() };
      groups.set(prefix, group);
    }
    group.latitudes.push(latitude);
    group.longitudes.push(longitude);
    const city = at('geolocation_city');
    const state = at('geolocation_state').toUpperCase();
    if (city) group.cities.set(city, (group.cities.get(city) ?? 0) + 1);
    if (state) group.states.set(state, (group.states.get(state) ?? 0) + 1);
  }
  const median = (values) => {
    values.sort((a, b) => a - b);
    const middle = Math.floor(values.length / 2);
    return values.length % 2 ? values[middle] : (values[middle - 1] + values[middle]) / 2;
  };
  const mode = (values) => [...values.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0] ?? '';
  for (const [prefix, group] of groups) {
    groups.set(prefix, {
      latitude: median(group.latitudes),
      longitude: median(group.longitudes),
      city: mode(group.cities),
      state: mode(group.states),
    });
  }
  return groups;
}

/**
 * Retorna o índice de geolocalização, carregando sob demanda.
 */
export async function getGeolocationIndex() {
  if (!geolocationIndexPromise) {
    geolocationIndexPromise = loadGeolocationIndex().catch((error) => {
      geolocationIndexPromise = null;
      throw error;
    });
  }
  return geolocationIndexPromise;
}

/**
 * Resolve um CEP para coordenadas e informações geográficas.
 */
export async function resolveCep(cep) {
  const index = await getGeolocationIndex();
  const zipPrefix = cep.slice(0, 5);
  const location = index.get(zipPrefix);
  if (!location) return null;
  return { cep, zip_prefix: zipPrefix, ...location };
}

/**
 * Encontra o hub mais próximo de um CEP.
 */
export async function findNearestHub(cep, hubs) {
  const index = await getGeolocationIndex();
  const zipPrefix = cep.slice(0, 5);
  const location = index.get(zipPrefix);
  if (!location) return { error: 'CEP_NOT_FOUND', message: `CEP ${cep} não encontrado na base geográfica.` };

  if (!hubs || hubs.length === 0) {
    return { error: 'NO_HUBS_AVAILABLE', message: 'Nenhum hub ativo disponível.' };
  }

  let nearest = null;
  let minDistance = Infinity;

  for (const hub of hubs) {
    if (hub.latitude == null || hub.longitude == null) continue;
    const dist = haversineKm(location.latitude, location.longitude, hub.latitude, hub.longitude);
    if (dist < minDistance || (dist === minDistance && (nearest === null || hub.id < nearest.id))) {
      minDistance = dist;
      nearest = { ...hub, distance_km: Math.round(dist * 100) / 100 };
    }
  }

  if (!nearest) {
    return { error: 'NO_ELIGIBLE_HUBS', message: 'Nenhum hub elegível encontrado para este CEP.' };
  }

  return { hub: nearest, location };
}
