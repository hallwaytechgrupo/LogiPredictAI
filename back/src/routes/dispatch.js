/**
 * Rotas de simulação de despacho.
 *
 * Permite simular despacho entre dois CEPs, selecionando automaticamente
 * os hubs mais próximos e calculando a rota via OpenRouteService.
 */
import express from 'express';
import { normalizeCep, haversineKm } from '../utils.js';
import { getGeolocationIndex } from '../geolocation.js';
import { listActive as listActiveHubs } from '../db/repositories/hubs.js';

const router = express.Router();

/**
 * Lê hubs do arquivo JSON (fallback).
 */
async function readHubsFromJson() {
  const { readFile } = await import('node:fs/promises');
  const hubsFile = process.env.HUBS_FILE || `${process.cwd()}/data/hubs.json`;
  try {
    const content = await readFile(hubsFile, 'utf8');
    const parsed = JSON.parse(content);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((h) =>
      h.validationStatus === 'APROVADO' &&
      h.active &&
      h.latitude != null &&
      h.longitude != null
    );
  } catch {
    return [];
  }
}

/**
 * Busca hubs ativos (PostgreSQL + JSON fallback).
 */
async function getActiveHubs() {
  let hubs = await listActiveHubs();
  if (hubs.length === 0) {
    hubs = await readHubsFromJson();
  }
  return hubs;
}

/**
 * Calcula rota via OpenRouteService.
 */
async function getRouteViaOpenRouteService(originHub, destHub) {
  const key = process.env.OPENROUTE_API_KEY;
  if (!key) {
    return { error: 'OPENROUTE_KEY_MISSING', message: 'Chave API OpenRouteService não configurada.' };
  }

  const url = `https://api.openrouteservice.org/v2/directions/driving-car?api_key=${key}`;
  const body = JSON.stringify({
    coordinates: [
      [originHub.longitude, originHub.latitude],
      [destHub.longitude, destHub.latitude],
    ],
  });

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
      signal: AbortSignal.timeout(10000),
    });

    if (!response.ok) {
      return { error: 'OPENROUTE_ERROR', message: `OpenRouteService retornou status ${response.status}.` };
    }

    const data = await response.json();
    // OpenRouteService v2 returns { routes: [{ segments: [{ distance, duration }], geometry, summary }] }
    const routes = data.routes;
    if (!routes || routes.length === 0) {
      return { error: 'OPENROUTE_NO_ROUTE', message: 'Nenhuma rota encontrada.' };
    }

    const routeData = routes[0];
    const segment = routeData.segments?.[0];
    if (!segment || !segment.distance) {
      return { error: 'OPENROUTE_NO_ROUTE', message: 'Nenhuma rota encontrada.' };
    }

    return {
      distance_km: Math.round(segment.distance / 1000 * 100) / 100,
      duration_seconds: Math.round(segment.duration),
      geometry: routeData.geometry || null,
    };
  } catch (e) {
    return { error: 'OPENROUTE_UNAVAILABLE', message: `Serviço de roteamento indisponível: ${e.message}` };
  }
}

/**
 * POST /api/v1/dispatch/simulate
 *
 * Simula despacho entre dois CEPs, selecionando automaticamente os hubs mais próximos.
 *
 * Body: { origin_cep: string, destination_cep: string }
 * Retorna: { origin, destination, origin_hub, destination_hub, distances, route }
 */
router.post('/simulate', async (req, res) => {
  if (!req.is('application/json')) {
    return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
  }

  const originCep = normalizeCep(req.body?.origin_cep);
  const destCep = normalizeCep(req.body?.destination_cep);

  if (!originCep) {
    return res.status(422).json({ error: 'INVALID_ORIGIN_CEP', message: 'CEP de origem inválido. Use o formato 00000-000.' });
  }
  if (!destCep) {
    return res.status(422).json({ error: 'INVALID_DESTINATION_CEP', message: 'CEP de destino inválido. Use o formato 00000-000.' });
  }

  try {
    // Resolver CEPs
    const index = await getGeolocationIndex();
    const originPrefix = originCep.slice(0, 5);
    const destPrefix = destCep.slice(0, 5);

    const originGeo = index.get(originPrefix);
    if (!originGeo) {
      return res.status(404).json({ error: 'ORIGIN_CEP_NOT_FOUND', message: `CEP de origem ${originCep} não encontrado na base geográfica.` });
    }
    const destGeo = index.get(destPrefix);
    if (!destGeo) {
      return res.status(404).json({ error: 'DESTINATION_CEP_NOT_FOUND', message: `CEP de destino ${destCep} não encontrado na base geográfica.` });
    }

    // Buscar hubs ativos
    const hubs = await getActiveHubs();
    if (hubs.length === 0) {
      return res.status(503).json({ error: 'NO_HUBS_AVAILABLE', message: 'Nenhum hub ativo e aprovado disponível.' });
    }

    // Encontrar hub mais próximo da origem
    let originHub = null;
    let originHubDist = Infinity;
    for (const hub of hubs) {
      const dist = haversineKm(originGeo.latitude, originGeo.longitude, hub.latitude, hub.longitude);
      if (dist < originHubDist || (dist === originHubDist && (originHub === null || hub.id < originHub.id))) {
        originHubDist = dist;
        originHub = hub;
      }
    }

    // Encontrar hub mais próximo do destino
    let destHub = null;
    let destHubDist = Infinity;
    for (const hub of hubs) {
      const dist = haversineKm(destGeo.latitude, destGeo.longitude, hub.latitude, hub.longitude);
      if (dist < destHubDist || (dist === destHubDist && (destHub === null || hub.id < destHub.id))) {
        destHubDist = dist;
        destHub = hub;
      }
    }

    if (!originHub || !destHub) {
      return res.status(503).json({ error: 'NO_ELIGIBLE_HUBS', message: 'Nenhum hub elegível encontrado.' });
    }

    // Verificar se são o mesmo hub
    const sameHub = originHub.id === destHub.id;

    // Distância Haversine entre hubs
    const hubToHubHaversine = haversineKm(
      originHub.latitude, originHub.longitude,
      destHub.latitude, destHub.longitude
    );

    // Tentar rota rodoviária
    let route = null;
    let routeWarnings = [];
    if (!sameHub) {
      const routeResult = await getRouteViaOpenRouteService(originHub, destHub);
      if (routeResult.error) {
        // Provide structured warnings based on error type
        if (routeResult.error === 'OPENROUTE_KEY_MISSING') {
          routeWarnings.push({
            type: 'road_unavailable',
            code: 'OPENROUTE_KEY_MISSING',
            message: 'A chave API do OpenRouteService não está configurada.',
            detail: 'A distância entre hubs apresentada é geográfica (Haversine), em linha reta, e não representa a distância rodoviária real.',
          });
        } else if (routeResult.error === 'OPENROUTE_UNAVAILABLE') {
          routeWarnings.push({
            type: 'road_unavailable',
            code: 'OPENROUTE_UNAVAILABLE',
            message: 'Serviço de roteamento indisponível.',
            detail: `A rota rodoviária não pôde ser calculada: ${routeResult.message}. A distância geográfica (Haversine) é apresentada como alternativa.`,
          });
        } else {
          routeWarnings.push({
            type: 'road_unavailable',
            code: routeResult.error,
            message: 'Rota rodoviária não disponível.',
            detail: `A distância entre hubs é calculada em linha reta (Haversine). ${routeResult.message}`,
          });
        }
      } else {
        route = routeResult;
      }
    }

    // Build legacy warnings array for backward compatibility
    const legacyWarnings = sameHub
      ? ['Origem e destino estão associados ao mesmo hub.']
      : routeWarnings.map(w => `${w.message} ${w.detail}`).flat();

    return res.json({
      data: {
        origin: {
          cep: originCep,
          zip_prefix: originPrefix,
          latitude: originGeo.latitude,
          longitude: originGeo.longitude,
          city: originGeo.city,
          state: originGeo.state,
        },
        destination: {
          cep: destCep,
          zip_prefix: destPrefix,
          latitude: destGeo.latitude,
          longitude: destGeo.longitude,
          city: destGeo.city,
          state: destGeo.state,
        },
        origin_hub: {
          id: originHub.id,
          code: originHub.code,
          name: originHub.name,
          city: originHub.city,
          state: originHub.state,
          latitude: originHub.latitude,
          longitude: originHub.longitude,
        },
        destination_hub: {
          id: destHub.id,
          code: destHub.code,
          name: destHub.name,
          city: destHub.city,
          state: destHub.state,
          latitude: destHub.latitude,
          longitude: destHub.longitude,
        },
        same_hub: sameHub,
        distances: {
          origin_to_origin_hub_km: Math.round(originHubDist * 100) / 100,
          destination_to_dest_hub_km: Math.round(destHubDist * 100) / 100,
          hub_to_hub_haversine_km: Math.round(hubToHubHaversine * 100) / 100,
          route_distance_km: route?.distance_km || null,
          route_duration_seconds: route?.duration_seconds || null,
        },
        route: route ? {
          distance_km: route.distance_km,
          duration_seconds: route.duration_seconds,
          geometry: route.geometry,
        } : null,
        warnings: legacyWarnings,
        route_warnings: sameHub ? [] : routeWarnings,
      },
    });
  } catch (error) {
    if (error.code === 'ENOENT') {
      return res.status(503).json({
        error: 'GEOLOCATION_SOURCE_UNAVAILABLE',
        message: 'A base geográfica não está disponível.',
      });
    }
    console.error('Falha na simulação de despacho:', error.message);
    return res.status(500).json({
      error: 'DISPATCH_SIMULATION_ERROR',
      message: 'Não foi possível simular o despacho.',
    });
  }
});

export default router;
