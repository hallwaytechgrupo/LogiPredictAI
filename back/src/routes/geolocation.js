/**
 * Rotas de geolocalização.
 *
 * Fornece endpoints para resolver CEPs e encontrar o hub mais próximo.
 */
import express from 'express';
import { normalizeCep } from '../utils.js';
import { getGeolocationIndex, resolveCep, findNearestHub } from '../geolocation.js';
import { listActive as listActiveHubs } from '../db/repositories/hubs.js';

const router = express.Router();

/**
 * POST /api/v1/geolocation/nearest-hub
 *
 * Identifica o hub mais próximo de um CEP ou coordenada.
 *
 * Body: { cep: string } ou { latitude: number, longitude: number }
 * Retorna: { hub, distance_km, location }
 */
router.post('/nearest-hub', async (req, res) => {
  if (!req.is('application/json')) {
    return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
  }

  const { cep, latitude, longitude } = req.body || {};

  let cepNormalized;
  let lat, lng;

  if (cep) {
    cepNormalized = normalizeCep(cep);
    if (!cepNormalized) {
      return res.status(422).json({ error: 'INVALID_CEP', message: 'CEP inválido. Use o formato 00000-000.' });
    }
  } else if (latitude !== undefined && longitude !== undefined) {
    if (typeof latitude !== 'number' || typeof longitude !== 'number' ||
        !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return res.status(422).json({ error: 'INVALID_COORDINATES', message: 'Coordenadas inválidas.' });
    }
    lat = latitude;
    lng = longitude;
  } else {
    return res.status(422).json({ error: 'MISSING_INPUT', message: 'Envie "cep" ou "latitude"/"longitude".' });
  }

  try {
    // Buscar hubs ativos
    const hubs = await listActiveHubs();
    if (hubs.length === 0) {
      // Fallback: ler do JSON (deve ser raro, pois listActiveHubs já faz fallback)
      const { readFile } = await import('node:fs/promises');
      const hubsFile = process.env.HUBS_FILE || `${process.cwd()}/data/hubs/hubs.json`;
      try {
        const content = await readFile(hubsFile, 'utf8');
        const parsed = JSON.parse(content);
        if (Array.isArray(parsed)) {
          for (const h of parsed) {
            if (h.validationStatus === 'APROVADO' && h.active && h.latitude != null && h.longitude != null) {
              hubs.push(h);
            }
          }
        }
      } catch (e) {
        // Ignorar
      }
    }

    if (hubs.length === 0) {
      return res.status(503).json({ error: 'NO_HUBS_AVAILABLE', message: 'Nenhum hub ativo e aprovado disponível.' });
    }

    if (cepNormalized) {
      // Usar função shared
      const result = await findNearestHub(cepNormalized, hubs);
      if (result.error) {
        return res.status(404).json({ error: result.error, message: result.message });
      }
      // Determine geolocation method: Olist dataset uses 5-digit prefixes
      const zipPrefix = cepNormalized.slice(0, 5);
      const geolocationMethod = result.location?.zip_prefix === zipPrefix
        ? 'cep_prefix' // Approximate: based on 5-digit prefix
        : 'exact';

      return res.json({
        data: {
          cep: cepNormalized,
          location: result.location,
          hub: {
            id: result.hub.id,
            code: result.hub.code,
            name: result.hub.name,
            city: result.hub.city,
            state: result.hub.state,
            latitude: result.hub.latitude,
            longitude: result.hub.longitude,
          },
          distance_km: result.hub.distance_km,
          geolocation_method: geolocationMethod,
          association_status: 'auto',
        },
      });
    } else {
      // Coordenadas diretas
      const { haversineKm } = await import('../utils.js');
      let nearest = null;
      let minDistance = Infinity;
      for (const hub of hubs) {
        const dist = haversineKm(lat, lng, hub.latitude, hub.longitude);
        if (dist < minDistance || (dist === minDistance && (nearest === null || hub.id < nearest.id))) {
          minDistance = dist;
          nearest = hub;
        }
      }
      if (!nearest) {
        return res.status(503).json({ error: 'NO_ELIGIBLE_HUBS', message: 'Nenhum hub elegível encontrado.' });
      }
      return res.json({
        data: {
          latitude: lat,
          longitude: lng,
          hub: {
            id: nearest.id,
            code: nearest.code,
            name: nearest.name,
            city: nearest.city,
            state: nearest.state,
            latitude: nearest.latitude,
            longitude: nearest.longitude,
          },
          distance_km: Math.round(minDistance * 100) / 100,
        },
      });
    }
  } catch (error) {
    if (error.code === 'ENOENT') {
      return res.status(503).json({
        error: 'GEOLOCATION_SOURCE_UNAVAILABLE',
        message: 'A base geográfica não está disponível.',
      });
    }
    console.error('Falha ao encontrar hub mais próximo:', error.message);
    return res.status(500).json({
      error: 'GEOLOCATION_ERROR',
      message: 'Não foi possível encontrar o hub mais próximo.',
    });
  }
});

/**
 * POST /api/v1/geolocation/route
 *
 * Calcula a distância Haversine entre CEPs (preserva endpoint existente).
 */
router.post('/route', async (req, res) => {
  if (!req.is('application/json')) {
    return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
  }
  const originInput = req.body?.origin_ceps;
  const destinationCep = normalizeCep(req.body?.destination_cep);
  if (!Array.isArray(originInput) || originInput.length < 1 || originInput.length > 100 ||
      !destinationCep || originInput.some((cep) => !normalizeCep(cep))) {
    return res.status(422).json({
      error: 'INVALID_CEP',
      message: 'Informe um CEP de destino e de 1 a 100 CEPs de origem no formato 00000-000.',
    });
  }
  try {
    const index = await getGeolocationIndex();
    const resolve = (cep) => {
      const normalized = normalizeCep(cep);
      const zipPrefix = normalized.slice(0, 5);
      const location = index.get(zipPrefix);
      return location ? { cep: normalized, zip_prefix: zipPrefix, ...location } : null;
    };
    const origins = originInput.map(resolve);
    const missingOrigin = origins.findIndex((location) => !location);
    if (missingOrigin >= 0) {
      return res.status(404).json({
        error: 'CEP_NOT_FOUND',
        message: 'O CEP de origem ' + normalizeCep(originInput[missingOrigin]) + ' não consta na base geográfica.',
      });
    }
    const destination = resolve(destinationCep);
    if (!destination) {
      return res.status(404).json({
        error: 'CEP_NOT_FOUND',
        message: 'O CEP de destino ' + destinationCep + ' não consta na base geográfica.',
      });
    }
    const { haversineKm } = await import('../utils.js');
    const routeDistances = origins.map((origin) => haversineKm(origin.latitude, origin.longitude, destination.latitude, destination.longitude));
    return res.json({
      data: {
        origins: origins.map((origin, index) => ({
          ...origin,
          distance_km: routeDistances[index],
        })),
        destination,
        seller_state: origins[0].state,
        customer_state: destination.state,
        distance_km: Math.max(...routeDistances),
        distance_method: 'Maior distância em linha reta entre os vendedores e o destino (Haversine, km).',
        geolocation_source: 'Base Olist geolocation; coordenadas medianas pelo prefixo CEP de 5 dígitos.',
      },
    });
  } catch (error) {
    if (error.code === 'ENOENT') {
      return res.status(503).json({
        error: 'GEOLOCATION_SOURCE_UNAVAILABLE',
        message: 'A base geográfica não está disponível.',
      });
    }
    console.error('Falha ao carregar base geográfica:', error.message);
    return res.status(500).json({
      error: 'GEOLOCATION_ERROR',
      message: 'Não foi possível resolver a localização dos CEPs.',
    });
  }
});

export default router;
